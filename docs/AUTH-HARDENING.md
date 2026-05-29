# Auth hardening — operator checklist

Most of the production auth posture lives in **Supabase Dashboard
settings** (not in code), because Supabase Auth handles email verification,
rate limiting, and breached-password checks. This file documents what the
operator must configure when provisioning the production Supabase project.

## Supabase Dashboard → Authentication → Settings

| Setting | Production value | Reason |
|---|---|---|
| Site URL | `https://app.heitobias.com` | Matches `APP_URL` env |
| Redirect URLs | `https://app.heitobias.com/**` (+ staging URL) | Magic-link allow-list |
| Disable signups | **OFF** for first launch (org admin invites users); revisit if self-serve later | |
| Email confirmations required | **ON** | Production-grade email verify |
| Secure email change | **ON** | Confirm on both old + new addresses |
| Mailer auto-confirm | **OFF** | Force the click-to-verify flow |

## Supabase Dashboard → Authentication → Providers → Email

| Setting | Value |
|---|---|
| Enable Email provider | ON |
| Confirm email | ON |
| Secure password change | ON |
| Use custom SMTP | ON (point at Postmark / SendGrid EU / SES eu-central-1) |
| SMTP host / port / user / pass | From your SMTP_API_KEY values |

## Supabase Dashboard → Authentication → Rate limits

| Setting | Production value | Reason |
|---|---|---|
| Email-token requests / hour | 10 | Prevents magic-link bombing |
| Token verifications / hour | 30 | Standard floor |
| Password sign-ins / hour | 30 | Rate-limit dictionary attacks |
| Anonymous sign-ins / hour | 0 | Anon is disabled — token-only flows reach SECDEF RPCs |

## Supabase Dashboard → Authentication → Sessions

| Setting | Production value |
|---|---|
| Refresh token reuse interval | 10s |
| Refresh token rotation | ON |
| JWT expiry | 3600s (1 hour) |
| Inactivity timeout | 24h standard users (configure via session refresh) |
| Admin inactivity | 4h — enforced client-side via session-age check |

The admin-shorter-session enforcement lives in `src/lib/session-policy.ts` —
checks `session.user.created_at` against role and forces re-auth at the 4h
mark. Implementation note: this is a CLIENT-SIDE soft-expire that signs the
user out and prompts re-auth; the server-side JWT expiry remains 1h with
rotation, which is the hard floor.

## Password policy

Supabase has built-in minimum length + complexity. Set in Dashboard →
Authentication → Policies:

| Setting | Production value |
|---|---|
| Minimum length | 12 |
| Require uppercase | ON |
| Require lowercase | ON |
| Require number | ON |
| Require symbol | ON |
| Block compromised passwords | ON (HIBP integration) |

## Magic-link expiry policy

| Token type | Expiry | Notes |
|---|---|---|
| User invite (`invite_tokens.expires_at`) | 7 days | Enforced in `org_invite_user` RPC |
| Candidate take-token (`assessment_invites.expires_at`) | 14 days default, configurable up to 30 | Enforced in `assessment_invite_create` |
| Consent token (`consent_tokens.token`) | Long-lived (no expiry) | Lives for the consent grant's lifetime |
| Password reset | 1 hour | Supabase default; do not extend |

The 7-day and 14-day defaults are encoded in the RPCs; changing the policy
requires a migration that updates the default + a comment explaining the
rationale.

## Headers (configured in `vercel.json`)

Security headers applied to every response. See `vercel.json` for the full
list. Highlights:

- **HSTS** — `max-age=63072000; includeSubDomains; preload`
- **X-Frame-Options** — DENY (no embedding)
- **CSP** — Restricts script/style/connect sources; allows Supabase + Sentry
- **Referrer-Policy** — `strict-origin-when-cross-origin`
- **Permissions-Policy** — Denies camera/microphone/geolocation/payment

## Cookies

Supabase Auth's session lives in `localStorage` by default. For the take-token
flow (anonymous, no session needed) we don't set cookies at all. The CSRF
helper at `src/lib/csrf.ts` exists as a forward-looking shim for any future
cookie-based endpoint.

## What's NOT done in code (operator items)

- Sign up for SMTP provider, supply credentials via Supabase Dashboard
- Configure SPF / DKIM / DMARC records at DNS registrar
- Verify HSTS preload submission (after 6-month soak)
- Enable HIBP integration in Supabase Auth settings (above)
- Verify EU-region project after launch (Dashboard → General → Region)
