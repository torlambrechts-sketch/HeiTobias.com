# HeiTobias

> A talent lifecycle platform: candidate → hire → high-performing
> employee, on one continuous data spine. Two co-equal entities — Role
> Profile (the target) and Person Profile (what's measured) — with a
> recruiter-channel land-and-expand motion (agencies seed profiles;
> employers inherit them and activate the lifecycle layer).

**Stack:** PostgreSQL (Supabase) · Row-Level Security · Edge functions
· React + TypeScript · Tailwind + shadcn/ui · EU-region hosting.

---

## Quick start (local development)

```bash
# 1. Clone and install
git clone <repo> && cd HeiTobias.com
npm ci

# 2. Configure environment
cp .env.example .env.local
# Edit .env.local — at minimum:
#   VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY
#   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (for scripts)

# 3. Apply migrations to your dev Supabase project
npx supabase db push --linked

# 4. Seed the demo data (guarded; triple check before running)
SEED_DEMO_DATA=true npm run seed:demo

# 5. Start the dev server
npm run dev
```

The dev server is at `http://localhost:5173`. The unified candidate
take-flow lives at `/take/<token>` (use a seeded demo token from
`supabase/seed-demo/`).

## Scripts

| Script | Purpose |
|---|---|
| `npm run dev` | Vite dev server |
| `npm run build` | Production build |
| `npm run typecheck` | `tsc -b --noEmit` |
| `npm test` | Vitest |
| `npm run seed:demo` | Seed demo data (`SEED_DEMO_DATA=true` required) |
| `npm run seed:demo:wipe` | Wipe demo data (same guards) |
| `node scripts/invariant-checks.mjs` | Run the four CI invariants |

## Repository layout

```
api/                # Vercel edge functions (/api/health, /api/ready, /api/dsr/*)
docs/               # Operator runbooks (BACKUPS, RETENTION, MONITORING,
                    # AUTH-HARDENING) + USER-DOCUMENTATION + OPERATOR-RUNBOOK
public/             # Static assets (architecture.html, robots.txt)
scripts/            # CI scripts (invariant-checks, seed-demo, sql-tests)
src/
  components/       # Shared UI (Shell, NotificationBell, CommandPalette,
                    # ToastProvider, ErrorBoundary, EmptyState, ErrorState,
                    # ModuleGate, …)
  components/ui/    # Design-system primitives (Card, Button, Pill, …)
  lib/              # Cross-cutting (browser-supabase, currentOrg, env,
                    # config, csrf, email, i18n, log, usePageTitle, …)
  pages/            # Route components (one per top-level surface)
  types/            # Hand-authored TypeScript types layered on top of
                    # Supabase-generated types
supabase/
  migrations/       # Versioned schema migrations — applied in timestamp order
  seed-demo/        # Demo seed migrations (NOT applied automatically;
                    # gated behind SEED_DEMO_DATA=true via seed:demo script)
  seed.sql          # Production seed (RBAC roles, modules, frameworks)
.github/workflows/  # CI/CD: pr.yml (typecheck+test+build+invariants),
                    # staging.yml, production.yml (with manual approval gate)
```

## Key reference docs (load-bearing)

| File | Purpose |
|---|---|
| `CLAUDE.md` | Engineering principles + the hard never-list |
| `SCIENCE-SPEC.md` | I/O psych + EU AI Act / GDPR discipline. Authoritative for measurement, fairness, decision architecture |
| `PHASE0-SPEC.md` | Phase 0 entity model + RLS + consent + audit |
| `DESIGN.md` | UI system, design tokens, visual signatures |
| `PRODUCTION-LAUNCH-CHECKLIST.md` | Operator checklist for going live |
| `PRODUCTION-HARDENING-REPORT.md` | What landed in the production-hardening pass |
| `docs/OPERATOR-RUNBOOK.md` | Day-to-day operations: incidents, DSRs, backups |
| `docs/USER-DOCUMENTATION.md` | In-app help for end users |

## Deployment

Deployments are triggered by pushing to a tracked branch:
- `staging` branch → `.github/workflows/staging.yml` → Vercel staging env
- `main` branch → `.github/workflows/production.yml` → Vercel production
  (with a manual-approval gate)

Both workflows reuse `.github/workflows/pr.yml` for CI (typecheck →
vitest → build → invariant-checks). `production.yml` explicitly
refuses to deploy if `SEED_DEMO_DATA=true` is set in the production
environment.

## The five pillars (do not violate)

From `CLAUDE.md` §"The five pillars":

1. **Database-first.** Schema is source of truth. Migrations are the
   unit of change. Types generated from the DB.
2. **Modular.** Capabilities are modules; core (orgs, people, RBAC,
   audit) is stable; modules compose on top.
3. **Template-driven.** Roles, layouts, workflows are data, not code.
4. **Security & privacy by construction.** Multi-tenant from row zero,
   RLS default-deny, consent-gated, audit-everything, EU-only.
5. **Scientific integrity.** Never fabricate validated psychometric
   values. Stubs are clearly labelled; DB CHECK constraints enforce
   that `validity_status='validated'` requires real numeric values.

## Status

- **Build:** all CI checks pass on `main`.
- **Production:** not yet flipped. Operator handoff items in
  `PRODUCTION-LAUNCH-CHECKLIST.md`.
- **H-1 through H-10:** all `_dev_stub` by design. Expert sign-off
  closes them; see `SCIENCE-SPEC.md`.
