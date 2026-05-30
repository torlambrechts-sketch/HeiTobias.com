# Public Surfaces — Report

> Output of the public-surfaces build. Five phases, ten items: the
> public-facing perimeter that turns HeiTobias from "operationally
> complete for internal users" into "approachable and shareable from the
> outside world."
>
> Companion to `PRODUCTION-HARDENING-REPORT.md` and
> `FEATURES-PRODUCTION-GRADE-REPORT.md`.

---

## TL;DR

A prospect can now land on `/`, read the methodology honestly, request a
demo, apply to be a design partner, and (founder-approved) get an org
provisioned. A recruiter can share a field-stripped, watermarked role
profile or placement report with a stakeholder who has no account. A
data subject — with or without an account — can exercise their GDPR
rights through a real surface.

Legal pages carry a prominent **TEMPLATE PENDING LEGAL REVIEW** banner
until a platform admin records counsel sign-off. The science discipline
is intact: marketing copy claims exactly what SCIENCE-SPEC permits, every
psychometric value keeps its `dev_stub` label, and H-1 through H-10 are
untouched.

---

## What landed, by phase

### Phase 1 — Legal compliance + DSR (highest urgency)
- **`platform_settings`** singleton table (legal entity, DPO contact,
  support email, `legal_review_status`) + anon-safe
  `platform_settings_public()` exposing only the columns legal pages
  render. Managed from the platform-admin Settings tab.
- **`/legal/privacy`** + **`/legal/terms`** — structured pages following
  GDPR Art. 13/14 + the consent purpose ladder, each with the
  `TemplateBanner`. "Fit informs, never decides" appears in the terms as
  a binding clause; the data-side refusal taxonomy becomes acceptable-use
  restrictions.
- **DSR UI**:
  - Authenticated: **`/me/privacy`** — download-my-data (calls
    `dsr_export_my_data`, offers a JSON file), request-deletion (opens a
    `dsr_open(erase)`), consent overview.
  - Unauthenticated: **`/privacy/request`** + `api/dsr/unauth` +
    `dsr_unauth_open / verify / summary` RPCs. Existence-leak discipline:
    the open step always returns the same neutral message; only after the
    requester proves email ownership does the summary reveal anything.
- **Cookie banner** — minimal, first-party-cookie acknowledgement
  (session + CSRF only; no tracking).

### Phase 2 — Public sharing (field-stripped, watermarked, logged)
- **`share_tokens`** + **`share_token_accesses`** tables; `share_entity_kind`
  enum.
- RPCs: `share_token_create` (RBAC-gated, expiry 1–90d),
  `share_token_revoke`, `share_tokens_for_entity`, and the anon public
  reads `public_role_view` / `public_placement_report_view` — both
  field-strip server-side and log every access to `audit_log` +
  `share_token_accesses`.
- **`/public/role/:token`** and **`/public/placement-report/:token`** —
  watermarked, "request access" CTA, `dev_stub` labels preserved,
  candidate anonymised by default on reports.
- **`ShareManager`** on the Role Profile Manage tab: create / copy /
  revoke links with live access counts.
- The placement-report public view is rebuilt from explicitly-whitelisted
  fields joined off `fit_results` — recruiter free-text never leaves the
  building because it's never selected.
- `my_shared_artefacts()` lets a data subject see (and the surface
  revoke) shares about their own data.

### Phase 3 — Marketing / trust
- **`/`** landing page (signed-in users bounce to `/home`). Honest copy:
  trait-ranges-not-maxima, structured-interview-front-loaded (cited),
  EU-AI-Act-native, honest-about-validation. Testimonials say "coming
  soon" (no fabrication); pricing says "to be announced / free for design
  partners."
- **`/trust`** (`/methodology`) — the SCIENCE-SPEC made public and
  readable: evidence base, instrument selection + exclusion list,
  trait-as-ranges, fairness-as-computation-not-verdict, Nordic-norms
  status, AI Act posture, the `dev_stub` discipline explained.
- **`/about`** — mission, approach, team (founder-only until others are
  real), and an "open questions" section consistent with the honesty
  discipline.
- **`/contact`** — demo-request form → `contact_requests` via
  `contact_request_submit` (honeypot + 60s rate-limit). "2 business days"
  is the founder's real commitment.
- **`/docs`** — searchable FAQ, citation-linked, "suggest an FAQ" → contact.

### Phase 4 — Signup + recovery (no auto-provisioning)
- **`/signup`** — 3-step application: account (Supabase `signUp` + email
  verification) → org basics + separate ToS/privacy checkboxes → design-
  partner vs commercial. Records a `contact_requests` row via
  `signup_submit`; **does not auto-provision**.
- **Platform-admin Signup-requests tab** — approve (provisions the org
  via `platform_org_create` from A9) or decline.
- **`/login`** — password + magic-link alternative + links out.
- **`/login/forgot-password`** + **`/login/reset-password/:token`** —
  Supabase recovery flow, neutral responses, strength rules.
- **`/preferences/notifications/:token`** — token-keyed email preferences
  for external users (candidates, SMEs, pre-claim employees). Mandatory
  transactional categories can't be switched off (the page says so and
  explains the alternative — revoke the relationship).

### Phase 5 — Accessibility, status, help, perf, SEO
- **`/accessibility`** — WCAG 2.1 AA commitment, current status, known
  limitations, EU 2025/2122 posture; third-party audit line is a labelled
  template (operator work).
- **`/status`** — reads `platform_status_public()`. **Deliberately does
  not** read per-org `monitoring_incidents` (that would leak customer
  data); shows an operator-controlled banner instead, settable via
  `platform_status_set`.
- **In-app help panel** — a `?` in the app bar with route-contextual
  articles (e.g. "What is Delphi independence?" on Team-Def) + a
  feedback form → `feedback_submissions` via `feedback_submit`.
- **SEO** — `index.html` gets description, canonical, OpenGraph, Twitter
  Card, and schema.org Organization JSON-LD. `robots.txt` rewritten to
  allow public surfaces and block app/api/public-share/auth surfaces.
  `sitemap.xml` lists the public pages.

---

## What stays in TEMPLATE state (pending counsel)

- `/legal/privacy` and `/legal/terms` carry the **TEMPLATE PENDING LEGAL
  REVIEW** banner until a platform admin flips
  `platform_settings.legal_review_status` to `current` with a reviewer
  name. The RPC refuses `current` without a reviewer, and the flip is
  recorded in the investigation log. **Do not remove the banner before
  counsel has reviewed.**

## What stays pending operator action

- **Third-party accessibility audit** — the `/accessibility` audit
  date/auditor line is a labelled template.
- **Official status page** — `/status` reads our own operator banner. If
  a hosting-platform status service is adopted, point users there.
- **SMTP** — the unauthenticated-DSR magic link, signup verification,
  password-reset, and external-notification emails all rely on the
  operator-wired SMTP from the production-hardening pass. In non-prod the
  DSR intake echoes the token so the flow is walkable without email.
- **Status notifications (email + RSS)** — not built; noted on `/status`.

## What is unchanged, by design

- **H-1 through H-10** remain `dev_stub`. No closure.
- **No fabricated science in marketing copy.** Claims are SCIENCE-SPEC-
  bounded; the trust page explains the `dev_stub` discipline to prospects.
- **No fabricated testimonials or pricing.** Both say "coming soon".
- **No third-party analytics / tracking.** Cookie banner is a notice, not
  a consent gate, because there's nothing non-essential to gate.
- **Signup does not auto-provision.** Founder approval is in the loop —
  correct for design-partner stage.

---

## Security notes

- Every public read RPC is anon-callable but **field-strips at the
  database layer** (SECDEF, explicit column whitelists) — not in the
  client. Verified: recruiter notes / evaluator attributions / raw
  provenance never appear in the public payloads.
- Share tokens are unguessable (two concatenated UUIDs), expiring,
  revocable, and access-logged. `robots.txt` blocks `/public/` from
  indexing.
- The unauthenticated DSR flow does not leak whether an email has data
  until ownership is proven by magic link.
- New tables all `enable` + `force` RLS; reads/writes go through SECDEF
  RPCs with `set search_path = ''`. The CI invariant checker confirms
  (INVARIANT-2 search_path, INVARIANT-3 FORCE RLS).

---

## Verification

```
npm run typecheck      # clean
npm test               # 66/66 pass
npm run build          # OK; per-page chunks for all public surfaces
node scripts/invariant-checks.mjs   # ✓ all four invariants pass
```

Migrations added (apply in timestamp order):
```
20260530700000_public_phase1_legal.sql
20260530700100_public_phase2_sharing.sql
20260530700200_public_phase3_contact.sql
20260530700300_public_phase4_signup.sql
20260530700400_public_phase5_feedback.sql
```

---

## After this lands

The platform has a complete public perimeter. The remaining work is what
it has always been: the I/O-psychologist engagement closing H-1–H-10, the
legal advisor signing off the templates, the real Nordic norm collection,
and the first design-partner activation. The surfaces are ready and
waiting on those.
