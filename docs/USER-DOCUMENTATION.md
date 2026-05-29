# User Documentation

> The load-bearing flows for each role. Read this before training the
> first design partners. Sections per role; each section shows the one
> path the user is expected to walk repeatedly.

---

## For candidates

### What you'll be asked to do
You'll receive an email with a magic link to **/take/your-token**. The
link opens a four-section assessment session:

1. **Personality** — a structured questionnaire. There are no right or
   wrong answers; honest responses produce a better match.
2. **Cognitive** — a short timed reasoning section. Each item has 90
   seconds; you can't go back to a prior item.
3. **Values** — a short value-prioritisation questionnaire.
4. **Structured-interview prep** — you'll write 2–6 STAR-format
   reflections on competencies the role calls for.

The session **saves as you go**. You can close the tab and come back
to the same link later; it resumes where you left off.

### What we will NOT do with your data
- Auto-decide whether you get the job. Every hiring decision is made
  by a named human; the platform shows them context, never an answer.
- Share your data with another employer without your explicit
  consent. Cross-organisation hand-offs are gated by a consent grant
  you have to accept.
- Use your data outside the EU. All processing is EU-region.
- Generate personality ratings about you from anyone else's input.
  Your profile is built only from instruments **you** completed.

### How to revoke consent later
Visit **/me/your-token** (the consent dashboard). You can see every
active consent you've granted and revoke any of them with one click.
Revoking removes the corresponding data's visibility immediately;
artefacts already generated stay in the audit log for compliance
reasons but are no longer displayed.

### What "DEV STUB" means in the UI
Many surfaces show "DEV STUB" badges next to numbers. This means the
*system* generated a value, but the underlying I/O-psychology
calibration is still being validated. We don't claim those numbers
are scientifically validated until the relevant expert has signed
them off. The number is honest about what it is.

---

## For recruiters

### The end-to-end flow
1. **Create a requisition** (`/req` → Create requisition).
   - Pick a signed-off role version.
   - Optionally select a collaborating org (for agency / employer
     pairing).
   - Record a rationale (≥ 20 chars — this lands in the audit trail).
2. **Add candidates** to the requisition.
   - Existing person: search and attach.
   - New person: enter email + name + rationale; the system mints a
     take-token and queues the invite email.
3. **Track sessions** inline on `/req`.
   - Each candidate row shows their session status + section
     completion counts.
4. **Open `/requisitions/:id`** for the deep view.
   - Review per-candidate detail.
   - Compute fit (when the four-section session is complete).
   - Generate the placement report (HTML opens in new tab).
   - Record hiring decisions (advance / hire / reject / withdraw)
     with rationale.
5. **Execute the placement** (when the candidate has hire decision +
   `profile_portability` consent).
   - Pick the target employer org from the dropdown.
   - The platform atomically: ends the agency membership, starts the
     employer position, transfers the profile with `profile_portability`
     intact, requests `ongoing_management` consent from the candidate.

### The two consents you'll encounter
- **`profile_portability`** — gates the cross-org data move at
  placement.
- **`ongoing_management`** — gates the employer-side manager's
  visibility into the placed employee.

A candidate can decline either. The placement still works without
`profile_portability` (a fresh profile is built on the employer side);
the employer manager surface is empty until `ongoing_management` is
granted.

### Job-ad generator (when wired)
On a role profile, generate an inclusive job ad. Three guardrails fire:
- maximum-not-allowed traits (e.g. don't say "extreme drive")
- protected-characteristic mentions (refused)
- skill-laundry-list cap

Overrides require a rationale; the rationale lands in `admin_decisions`.

---

## For hiring managers

You'll receive in-app notifications (bell icon, top right) for:
- candidate completed assessment
- recruiter requested your review
- fit / placement report generated

Click the notification to navigate to the relevant surface. Your
visibility is gated by your role's `requisition.read` permission on
the relevant requisitions.

---

## For people managers (post-hire)

### The Manager Workspace (`/team`)
Lists employees in your reporting scope (subject to RLS + scope
helpers). Click an employee to open their detail.

### The Employee Detail
- **Re-fit trajectory** — the four-quadrant visualisation showing
  trait/role fit over time. This is a **practitioner synthesis**, not
  a validated psychometric instrument (the label is in the UI).
- **Signals** — flight-risk / well-being indicators from pulse data.
  These are **engagement signals, not performance proxies** (per
  CLAUDE.md §5). They inform conversations; they never auto-decide.
- **Grounded guidance** — 1:1 prep generated from the Frameworks
  Library + the employee's structured profile data. The guidance
  composer **refuses** medical / legal / dismissal / compensation /
  protected-characteristic-inference prompts and logs the refusal.

### What you cannot do (by design)
- Rate this employee's personality. The platform blocks peer-personality
  rating at the schema level.
- View the employee's data unless they've granted you
  `ongoing_management` consent.
- Auto-act on a signal. Every consequential action requires a recorded
  human decision (`decision_artefact`).

---

## For employees (post-hire)

### Your self-view (`/me`)
- **Profile** — what your manager sees.
- **Active consents** — who you've granted access to your data, by
  purpose. Revoke any of them with one click.
- **Recent activity** — every read or write of your data lands here,
  with the actor + timestamp. You see what your manager sees about you
  + what they did with it.

The framing throughout is developmental, not evaluative — the platform
is built to help you grow into the role, not to grade you.

---

## For org admins (in `/admin`)

### The four tabs
- **Audit** — query the audit log (filter by action, date range, person,
  entity). Export to CSV.
- **Users** — invite, role-change (requires rationale), deactivate
  (7-day grace period for active users).
- **Modules** — enable / disable per-org capabilities. Expert-gated
  modules (modeling, fairness) stay disabled until expert sign-off.
- **Settings** — brand (logo + accent color), default locale, DPA URL.

### My Profile (within `/admin`)
Your personal settings: locale, notification preferences (per channel
+ kind), leave-org request (with 7-day grace).

---

## Common-question quick reference

> "I don't see [X] in my list."
RLS scoped you out. Either you don't have the permission, or the row
isn't in your org. Org admin can verify.

> "I clicked a button and got 'forbidden'."
RPC-level permission refusal. Your role doesn't include the required
permission. Org admin can re-grant.

> "I clicked a notification and got a 404."
The linked surface was removed or you lost permission since the
notification was generated. Report so we can fix the dead link.

> "Where do I download my data?"
`/me/<consent-token>` → DSR Export. Or contact your org admin to
issue a DSR on your behalf.

> "Someone made a decision about me — how do I see the reasoning?"
The decision-artefact ID is in your audit feed. Ask your manager or
the recruiter who recorded it; the rationale is captured at decision
time per CLAUDE.md §human-in-the-loop.
