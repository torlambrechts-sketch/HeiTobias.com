# Monitoring + alerting — operator runbook

The application emits structured JSON logs via `src/lib/log.ts`. The
hosting platform (Vercel by default) ships those logs to its log pipeline.
The custom metrics in `metric.inc(...)` calls are namespaced
`metric.<name>` and can be filtered/aggregated downstream.

## What to alert on

| Alert | Condition | Severity | Who |
|---|---|---|---|
| **read_during_seal > 0** | Any log line with `_metric=read_during_seal_count` | **Critical (page on-call)** | Engineering + science lead |
| **error rate > 1%** | Errors / total requests over 5min | High (page on-call) | Engineering |
| `/api/health` failing | 5min of consecutive 503s | High (page on-call) | Engineering |
| **failed RLS > 50/min** from single IP | Per-IP rate counter | High (auto rate-limit + alert) | Engineering |
| email_outbox stuck pending > 30min | row count of `email_outbox where status='pending' and created_at < now()-30min` | Medium | Operator |
| email_suppressions add rate | Bounce rate spike | Medium | Operator |
| Vercel deploy failed | Build hook | Medium | Engineering |
| Backups not running | No row in `backup_runs` for 26h | High | Operator |
| Cross-org bridge invoked | metric.cross_org_bridge | Audit only — no alert, but tracked |

## The `read_during_seal` alert is special

This is the only alert on the list that signals a **science-defensibility
incident**, not a performance or availability issue. The
`team_def.read_during_seal` audit row + the matching `metric.read_during_seal_count`
log line both fire when someone attempts to read evaluator submissions
during the seal window. Production should never see this — if it does,
either the methodology has been bypassed (bad) or there's a code bug
that's exposing pre-seal data (worse). Either way: page on-call, do not
auto-resolve, escalate to the science lead.

## Sentry setup (operator action)

1. Create a Sentry project, EU data residency (Sentry has EU hosting).
2. Set `SENTRY_DSN` and `VITE_SENTRY_DSN` in production env vars.
3. Add the Sentry SDK initialisation by running:
   ```
   npm install @sentry/react @sentry/browser
   ```
   then wire it in `src/lib/sentry.ts` (file scaffold below) and import
   in `main.tsx`.

Sentry init scaffold:

```ts
// src/lib/sentry.ts
import * as Sentry from '@sentry/react'
import { env } from './env.js'
import { setSentryCapture } from './log.js'

export function initSentry(): void {
  const dsn = import.meta.env.VITE_SENTRY_DSN
  if (!dsn) return
  Sentry.init({
    dsn,
    environment: env().mode,
    tracesSampleRate: env().isProd ? 0.1 : 1.0,
    replaysSessionSampleRate: 0,
    replaysOnErrorSampleRate: env().isProd ? 0.1 : 0,
  })
  setSentryCapture((msg, fields) => {
    Sentry.captureMessage(msg, { extra: fields })
  })
}
```

This stays as documentation rather than committed code so the closure pass
doesn't introduce a runtime dep before the operator has decided on the
provider. Swap Sentry for Bugsnag / Honeybadger / etc by re-implementing
`initSentry` to call `setSentryCapture` with the equivalent capture call.

## Uptime monitoring

Pick any of:
- **UptimeRobot** — free tier, 5-min checks
- **BetterStack** — paid, sub-minute checks, integrated incident management
- **Pingdom** — paid, geographic checks

Configure with two checks:
- `GET https://app.heitobias.com/api/health` — every 5 min, alert if non-200
- `GET https://app.heitobias.com/api/ready` — every 5 min, alert if non-200

Both endpoints return JSON; the monitor can also assert `body.status==="ok"`
or `"ready"` for an extra signal.

## Log retention

Vercel retains logs for 7 days on the standard tier. For longer retention
ship to a destination (Datadog / Logflare / S3). Documented in
`DEPLOY.md → log retention`.
