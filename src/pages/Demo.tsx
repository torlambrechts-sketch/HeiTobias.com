import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { ArrowRight, Briefcase, CheckCircle2, Users, Loader2 } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { Shell } from '../components/Shell.js'
import { Card, CardBody, CardEyebrow, CardTitle } from '../components/ui/card.js'
import { Pill } from '../components/ui/badges.js'

// /demo — operator-facing demo overview. Shows the two seeded demo orgs
// side-by-side + a 5-stop guided tour through the existing surfaces.
// NOT visible in production builds (dev/staging only — we read
// import.meta.env.DEV which is true in vite dev/preview).

type DemoOrg = { id: string; name: string; type: string; locale_default: string }
type DemoRole = { id: string; title: string; org_id: string }
type DemoReq = { id: string; status: string; org_id: string }
type DemoCand = { id: string; stage: string; full_name: string | null }
type TeamDefRun = { id: string; role_family: string; stage: string }

const TOUR_STOPS = [
  {
    n: 1, label: 'Agency role library',
    detail: 'Open the agency-side Senior Backend Engineer role. The page shows the full Role Profile with the dev_stub seam — every H-7 field is openly labelled.',
    cta: 'Open role profile', href: '/roles/dd000000-0000-0000-0000-000000000001',
  },
  {
    n: 2, label: 'Team-based definition (signed-off)',
    detail: 'The agency ran a Delphi-style definition for this role; the run lists in /team-def and you can open the signed-off result.',
    cta: 'Team-def runs', href: '/team-def',
  },
  {
    n: 3, label: 'Agency requisitions + candidates',
    detail: 'The agency has an open requisition against this role with 4 candidates at differentiated pipeline stages (sourced / screening / interview / placed).',
    cta: 'Open the requisition', href: '/req',
  },
  {
    n: 4, label: 'Add a candidate + mint a take-token',
    detail: 'From the requisition row, add a candidate. The mint flow shows the magic /take/<token> link to copy — operator emails it (SMTP wiring is pending).',
    cta: 'Requisitions list', href: '/req',
  },
  {
    n: 4.5, label: 'Walk the unified candidate session (demo mode)',
    detail: 'Open a take-token URL with ?demo=true in incognito. The candidate walks consent + personality + cognitive + values + structured-interview prep in ~15 min. Production length is honestly 45–75 min; the demo banner is unmissable. Back in the recruiter view, the candidate row shows ⚠ DEMO MODE so no recruiter mistakes it for production.',
    cta: 'Open requisition (demo flag on take URL)', href: '/req',
  },
  {
    n: 5, label: 'Operator-facing admin',
    detail: 'Switch to the agency admin (Sara Lindqvist) to invite users with rationale, change rbac roles, toggle modules, explore audit log with compliance view + export, register HRIS integration connectors.',
    cta: 'Workspace admin', href: '/admin',
  },
  {
    n: 6, label: 'Manager workspace',
    detail: 'Switch to the employer side. /team shows team members; clicking opens the existing manager detail surface with developmental framing throughout.',
    cta: 'Manager team', href: '/team',
  },
  {
    n: 7, label: 'Employee self-view (transparency)',
    detail: 'Sign in as Maria Lindqvist (or any employee). /me surfaces the same data the manager sees about you, with revoke-by-purpose consent controls + activity-about-me log.',
    cta: 'My self-view', href: '/me',
  },
  {
    n: 8, label: 'Reference architecture',
    detail: 'Step back from the operating surfaces — the 4-layer system + the Talent Data Spine + the recruiter-as-wedge land-and-expand motion as one document.',
    cta: 'architecture.html', href: '/architecture.html',
  },
]

export function DemoPage() {
  const supabase = browserSupabase()
  const [orgs, setOrgs]   = useState<DemoOrg[]>([])
  const [roles, setRoles] = useState<DemoRole[]>([])
  const [reqs, setReqs]   = useState<DemoReq[]>([])
  const [cands, setCands] = useState<DemoCand[]>([])
  const [runs, setRuns]   = useState<TeamDefRun[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    void (async () => {
      const [o, r, q, c, td] = await Promise.all([
        supabase.from('organizations').select('id, name, type, locale_default').eq('is_demo_data' as never, true),
        supabase.from('roles_catalog').select('id, title, org_id').eq('is_demo_data' as never, true),
        supabase.from('requisitions').select('id, status, org_id').eq('is_demo_data' as never, true),
        supabase.from('requisition_candidates').select('id, stage, person:people!inner(full_name)').eq('is_demo_data' as never, true),
        supabase.from('team_definition_runs' as never).select('id, role_family, stage').eq('is_demo_data', true),
      ])
      setOrgs((o.data ?? []) as DemoOrg[])
      setRoles((r.data ?? []) as DemoRole[])
      setReqs((q.data ?? []) as DemoReq[])
      setCands(((c.data as { id: string; stage: string; person: { full_name: string } }[] | null) ?? [])
        .map(x => ({ id: x.id, stage: x.stage, full_name: x.person?.full_name ?? null })))
      setRuns(((td.data as TeamDefRun[] | null) ?? []))
      setLoading(false)
    })()
  }, [supabase])

  return (
    <Shell breadcrumb={<><strong>Demo overview</strong></>}>
      <div className="flex flex-col gap-5">
        <div className="rounded-lg border border-amber/40 bg-internal-bg/60 p-4 text-sm">
          <p className="font-semibold">This page is dev/staging only. It does not ship in production builds.</p>
          <p className="text-muted mt-1">All rows visible from this page carry <code className="font-mono">is_demo_data = true</code>. Every flow you can walk here uses the existing surfaces — no demo-only code paths.</p>
        </div>

        {loading && <div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading…</div>}

        <div className="grid lg:grid-cols-2 gap-4">
          {orgs.map(o => {
            const orgRoles = roles.filter(r => r.org_id === o.id)
            const orgReqs  = reqs.filter(r => r.org_id === o.id)
            const orgRuns  = o.type === 'agency' ? runs : []
            return (
              <Card key={o.id}>
                <CardEyebrow>{o.type}</CardEyebrow>
                <CardTitle>{o.name}</CardTitle>
                <CardBody className="flex flex-col gap-3 text-sm">
                  <div className="flex items-center gap-2 flex-wrap">
                    <Pill>locale {o.locale_default}</Pill>
                    <Pill>{o.type}</Pill>
                    <Pill tone="reject">demo data</Pill>
                  </div>
                  <div className="flex flex-col gap-1.5">
                    <div className="text-xs font-bold uppercase tracking-wider text-muted">Roles ({orgRoles.length})</div>
                    {orgRoles.map(r => (
                      <Link key={r.id} to={`/roles/${r.id}`} className="text-role hover:underline text-xs font-mono">{r.title}</Link>
                    ))}
                  </div>
                  {orgReqs.length > 0 && (
                    <div className="flex flex-col gap-1.5">
                      <div className="text-xs font-bold uppercase tracking-wider text-muted">Requisitions ({orgReqs.length})</div>
                      {orgReqs.map(r => (
                        <Link key={r.id} to={`/requisitions/${r.id}`} className="text-role hover:underline text-xs font-mono">{r.id.slice(0, 8)} · {r.status}</Link>
                      ))}
                    </div>
                  )}
                  {o.type === 'agency' && (
                    <div className="flex flex-col gap-1.5">
                      <div className="text-xs font-bold uppercase tracking-wider text-muted">Candidates in pipeline</div>
                      <ul className="text-xs flex flex-col gap-1">
                        {cands.map(c => <li key={c.id}><strong>{c.full_name}</strong> · <Pill>{c.stage}</Pill></li>)}
                      </ul>
                    </div>
                  )}
                  {orgRuns.length > 0 && (
                    <div className="flex flex-col gap-1.5">
                      <div className="text-xs font-bold uppercase tracking-wider text-muted">Team-def runs</div>
                      {orgRuns.map(r => (
                        <div key={r.id} className="text-xs"><span className="font-mono">{r.id.slice(0,8)}</span> · {r.role_family} · <Pill tone="open">{r.stage}</Pill></div>
                      ))}
                    </div>
                  )}
                </CardBody>
              </Card>
            )
          })}
        </div>

        {/* Guided tour */}
        <Card data-test="guided-tour">
          <CardEyebrow><CheckCircle2 size={12} /> Guided tour · 5 stops</CardEyebrow>
          <CardTitle>Walk the demo end-to-end</CardTitle>
          <CardBody>
            <ol className="flex flex-col gap-3">
              {TOUR_STOPS.map(s => (
                <li key={s.n} className="flex gap-3 border-b border-line pb-3 last:border-b-0">
                  <span className="w-7 h-7 rounded-full bg-forest text-white flex items-center justify-center font-bold text-sm flex-shrink-0">{s.n}</span>
                  <div className="flex-1">
                    <div className="font-semibold text-sm">{s.label}</div>
                    <p className="text-xs text-muted leading-snug mt-1">{s.detail}</p>
                    <Link to={s.href} className="text-xs text-role hover:underline mt-1.5 inline-flex items-center gap-1">
                      {s.cta} <ArrowRight size={11} />
                    </Link>
                  </div>
                </li>
              ))}
            </ol>
          </CardBody>
        </Card>

        <Card>
          <CardEyebrow><Users size={12} /> Demo personas</CardEyebrow>
          <CardTitle>Who to sign in as</CardTitle>
          <CardBody>
            <p className="text-xs text-muted mb-3">
              Sign-in flow uses the existing Supabase auth. Demo personas don't have real auth.users
              entries — the admin invite flow is the path to create real sessions. For now, sign in
              as one of the existing fixtures (e.g. Linnea Strand at fjordtech.test) to exercise the
              surfaces; demo data becomes visible if your fixture happens to be in a demo org.
            </p>
            <ul className="text-xs flex flex-col gap-1 font-mono">
              <li><strong>Sara Lindqvist</strong> · agency org_admin · sara.lindqvist@demo-lindqvist.test</li>
              <li><strong>Anders Karlsson</strong> · agency recruiter</li>
              <li><strong>Ingrid Holst</strong> · employer org_admin · ingrid.holst@demo-holst.test</li>
              <li><strong>Magnus Berg</strong> · employer hiring_manager</li>
              <li><strong>Maria Lindqvist</strong> · employer employee (emerging misfit demo case — Part 2)</li>
            </ul>
          </CardBody>
        </Card>

        <Card data-test="architecture-link">
          <CardEyebrow>Reference architecture</CardEyebrow>
          <CardTitle>The 4-layer system + the Talent Data Spine</CardTitle>
          <CardBody>
            <p className="text-sm text-muted leading-relaxed mb-3">
              Client surfaces · Application &amp; domain logic · Intelligence &amp; science · Data &amp;
              platform foundation — with the Role Profile + Person Profile as co-equal entities
              and the recruiter-channel land-and-expand motion built into the schema.
            </p>
            <a href="/architecture.html" target="_blank" rel="noopener" className="text-role hover:underline font-semibold text-sm">
              Open architecture.html → (full-screen reference)
            </a>
          </CardBody>
        </Card>

        <p className="text-xs text-faint mt-2">
          <Briefcase size={11} className="inline mr-1" />
          The demo is the unlock for design-partner conversations. Operator (EU
          Supabase, SMTP, audit retention) + HANDOFF (H-1 to H-10) items remain
          OUT-OF-SCOPE per the closure prompt.
        </p>
      </div>
    </Shell>
  )
}
