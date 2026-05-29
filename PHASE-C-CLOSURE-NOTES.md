# Phase C — Closure notes

> Edge cases, empty states, error states, concurrent access. Every
> list has a real empty state. Every form has real validation. Every
> async operation handles failure. The platform stops blanking when
> data is missing or the network hiccups.

## What landed

### C-primitives — reusable UI components
Three small components that the rest of the codebase can adopt
incrementally without breaking changes:

- **`src/components/ui/EmptyState.tsx`** — canonical "nothing to show"
  panel. Icon + headline + body paragraph + optional CTA. `role="status"`
  for screen readers. Used wherever a list/table/dashboard might
  legitimately be empty.
- **`src/components/ui/ErrorState.tsx`** — canonical "load failed"
  panel. `role="alert"`. Surfaces the underlying error message (does
  not invent friendlier text) + optional Retry button for idempotent
  ops.
- **`src/components/ui/Toast.tsx`** — minimal toast system with
  `ToastProvider` + `useToast()`. Three kinds: success / error / info.
  5s auto-dismiss; user can close earlier. Max 4 stacked. `role="alert"`
  for errors (assertive); `role="status"` for the rest (polite).
- **`src/components/ErrorBoundary.tsx`** — app-level React error
  boundary. Catches uncaught render crashes, logs to the structured
  logger (Sentry seam in `src/lib/log.ts`), shows a designed crash
  page with Try-Again. Replaces the default blank screen.

### Applied to representative surfaces
Not a full sweep (19 page files × N lists is too large for one pass);
instead the new components are applied to the most visible empty/error
paths so the pattern is established and the future sweep is
straightforward.

- `RequisitionsList.tsx` — empty state when no requisitions in scope
  (with a Create CTA); empty state when a requisition has no
  candidates yet (explaining the add-candidate flow + take-token).
  Toast on successful requisition create.
- `Team.tsx` — replaced the inline "No team members visible" card
  with the new `EmptyState` for consistency.
- `Me.tsx` — `EmptyState` on Active Consents (explains where consents
  come from) and on Recent Activity (explains what would populate the
  audit feed).

### C0 — Designed 404 page
`App.tsx` previously had `<Route path="*" element={<Navigate to="/" />}>`
— silently redirected to home, hiding link rot and making typos
invisible. Replaced with a designed `NotFoundPage` that says "404 Page
not found" clearly and offers a Back to home link.

### C0 — Designed crash page
The new `ErrorBoundary` wraps the entire routes tree (inside
`ToastProvider`, outside `BrowserRouter`). Render errors get caught,
logged, and presented to the user with a Try-Again button.

### Route-name corrections
While auditing for C-applied surfaces, I noticed three route bugs
introduced in Phase A:
- RoleProfile.tsx linked `/role/:id` — the registered route is
  `/roles/:id`. Fixed.
- RoleProfile.tsx linked `/team-def/:id` — the registered route is
  `/team-def/runs/:id`. Fixed.
- CommandPalette had the same `/role/...` issue. Fixed.

These would have produced 404s after the new NotFoundPage landed,
which is exactly what the 404 page is there to surface — but better
to ship the right links.

### C4 — Concurrent-edit detection for requisitions
Migration `20260530500200_phaseC_concurrent_edit.sql` adds a
`requisition_update_optimistic(id, expected_updated_at, ...)` RPC.
The caller passes the `updated_at` they last saw; if the row has
moved on, the RPC returns `{ ok: false, reason: 'stale_write',
actual_updated_at }` so the UI can re-fetch and present the diff
instead of silently overwriting.

The current UI does not yet call this RPC — the requisition page is
read-mostly today (status changes go through `placement_execute` and
`hiring_decision_record`, both of which are append-only). The RPC is
the seam; the wire-up happens alongside the future
edit-requisition-status surface.

## What did NOT land in Phase C (deferred / out of scope)

- **Full empty-state sweep across all 19 pages** — the pattern is
  established; the sweep is mechanical. Done for the highest-visibility
  surfaces; the rest is a small follow-up PR.
- **Form validation pass** — most forms in the codebase already do
  client-side `disabled={…}` validation (rationale ≥20 chars, email
  format etc.). The pass would be tightening error message text +
  inline validation feedback as the user types. Deferred to D5 polish.
- **C5 permission revocation graceful redirect** — when a user loses
  permission mid-action, the RPC returns an error and the page
  currently surfaces it as toast/error-state. A graceful auto-redirect
  to "/" with a "your permission was revoked" toast is a polish item.
  Same: pattern is in place; the wire-up is rote.
- **C6 browser support matrix** — no automated cross-browser tests in
  this environment. The CSS uses standard features (Tailwind 3,
  CSS variables, flexbox, grid) all supported in current Chrome /
  Firefox / Safari / Edge per caniuse. Documented in the launch
  checklist; the actual QA needs real browsers.

## Verification

```
npm run typecheck      # clean
npm test               # 66/66 pass
npm run build          # OK; index chunk +6kB (toast + boundary)
node scripts/invariant-checks.mjs   # ✓ pass
```

Phase C leaves the platform with: a 404 page that doesn't lie, an
error boundary instead of a white screen, a toast system the whole
app can opt into, designed empty states on the most visible lists, a
concurrent-edit detection seam on requisitions, and three URL link
bugs from Phase A repaired.
