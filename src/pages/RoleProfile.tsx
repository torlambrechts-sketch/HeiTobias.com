import { useCallback, useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { ChevronRight, Loader2, LogOut, ShieldCheck, Users } from 'lucide-react'
import { browserSupabase } from '../lib/browser-supabase.js'
import { fetchRoleProfile, fetchRoleVersionHistory } from '../lib/roleProfile.js'
import type { RoleProfileRow } from '../types/roleProfile.js'
import { Shell } from '../components/Shell.js'
import { Button } from '../components/ui/button.js'
import { Card, CardBody } from '../components/ui/card.js'
import { TabBand, Tab } from '../components/ui/tabband.js'
import { Pill } from '../components/ui/badges.js'
import { StubBanner } from '../components/role-profile/StubBanner.js'
import { PageHeader } from '../components/role-profile/PageHeader.js'
import { SubNav } from '../components/role-profile/SubNav.js'
import {
  IdentityGovernanceSection, TasksSection, CompetenciesSection, TraitTargetsSection,
  CognitiveDemandSection, ContextFactorsSection, ValuesSection, SuccessCriteriaSection,
  EvolutionVectorSection, TeamGapSection,
} from '../components/role-profile/Sections.js'
import { ValidationCard } from '../components/role-profile/ValidationCard.js'

export function RoleProfilePage() {
  const { id, version } = useParams<{ id: string; version?: string }>()
  const supabase = browserSupabase()
  const [signedIn, setSignedIn] = useState<string | null>(null)
  const [row, setRow] = useState<RoleProfileRow | null | undefined>(undefined)
  const [err, setErr] = useState<string | null>(null)
  const [tab, setTab] = useState<'profile' | 'team_definition' | 'versions' | 'defensibility' | 'manage'>('profile')

  useEffect(() => {
    void supabase.auth.getSession().then(({ data }) => setSignedIn(data.session?.user?.email ?? null))
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSignedIn(s?.user?.email ?? null))
    return () => sub.subscription.unsubscribe()
  }, [supabase])

  const reload = useCallback(() => {
    if (!id) return
    setRow(undefined); setErr(null)
    const v = version ? Number(version) : undefined
    fetchRoleProfile(supabase, id, v)
      .then(r => setRow(r))
      .catch(e => { setErr(e instanceof Error ? e.message : 'Failed to load'); setRow(null) })
  }, [supabase, id, version])

  useEffect(() => { reload() }, [reload])

  if (!signedIn) {
    return (
      <Shell breadcrumb={<span>Role profile</span>}>
        <Card><CardBody>
          <p>You must sign in to view a role profile.</p>
          <Button onClick={async () => {
            import.meta.env.DEV && (await supabase.auth.signInWithPassword({ email: 'linnea.strand@fjordtech.test', password: 'demo' }))
          }}>Sign in as Linnea (demo)</Button>
        </CardBody></Card>
      </Shell>
    )
  }

  return (
    <Shell breadcrumb={<span>Role profile · <strong>{row?.title ?? '…'}</strong></span>} signedInLabel={signedIn}>
      <div className="flex flex-col gap-4">
        {err && <div className="rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-900">{err}</div>}
        {row === undefined && (
          <div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading role profile…</div>
        )}
        {row === null && !err && (
          <Card><CardBody><p className="text-faint">Not found, or you don't have access to this role.</p></CardBody></Card>
        )}

        {row && (
          <>
            <PageHeader row={row} onChanged={reload} />

            {/* Forest tab band — only the Profile tab is built in this work */}
            <TabBand>
              <Tab active={tab === 'profile'} onClick={() => setTab('profile')}>Profile</Tab>
              <Tab active={tab === 'team_definition'} onClick={() => setTab('team_definition')}>Team definition</Tab>
              <Tab active={tab === 'versions'} onClick={() => setTab('versions')}>Version history</Tab>
              <Tab active={tab === 'defensibility'} onClick={() => setTab('defensibility')}>Defensibility</Tab>
              <Tab active={tab === 'manage'} onClick={() => setTab('manage')}>Manage</Tab>
            </TabBand>

            {tab === 'team_definition' && <TeamDefinitionTab row={row} />}
            {tab === 'versions'        && <VersionsTab row={row} />}
            {tab === 'defensibility'   && <DefensibilityTab row={row} />}
            {tab === 'manage'          && <ManageTab row={row} />}

            {tab === 'profile' && (
              <>
                <StubBanner row={row} />
                <div className="flex gap-6">
                  <SubNav />
                  <div className="flex-1 flex flex-col gap-4 min-w-0">
                    <IdentityGovernanceSection row={row} />
                    <TasksSection row={row} />
                    <CompetenciesSection row={row} />
                    <TraitTargetsSection row={row} />
                    <CognitiveDemandSection row={row} />
                    <ContextFactorsSection row={row} />
                    <ValuesSection row={row} />
                    <SuccessCriteriaSection row={row} />
                    <EvolutionVectorSection row={row} />
                    <TeamGapSection row={row} />
                    <ValidationCard row={row} />
                  </div>
                </div>
              </>
            )}
          </>
        )}

        <div className="flex justify-end pt-4 border-t border-line">
          <Button variant="ghost" onClick={() => supabase.auth.signOut()}><LogOut size={14} /> Sign out</Button>
        </div>
      </div>
    </Shell>
  )
}

// ─── Team definition tab ────────────────────────────────────────────
// Lists team_definition_runs that target this role version or share
// its role_family. Each row links to /team-def/<run.id> for the full
// driver page. Empty state explains what would populate the list and
// how to start one.
function TeamDefinitionTab({ row }: { row: RoleProfileRow }) {
  const supabase = browserSupabase()
  type Run = {
    id: string
    role_family: string
    purpose: string
    stage: string
    deadline_at: string
    target_role_version_id: string | null
    created_at: string
  }
  const [runs, setRuns] = useState<Run[] | null>(null)
  const [err, setErr] = useState<string | null>(null)
  useEffect(() => {
    void (async () => {
      // Surface runs that already target this role version, OR runs in
      // the same role_family (so a recruiter on a freshly-created role
      // sees the parent family's most recent work).
      const orFilter = row.family
        ? `target_role_version_id.eq.${row.id},role_family.eq.${row.family}`
        : `target_role_version_id.eq.${row.id}`
      const { data, error } = await supabase
        .from('team_definition_runs' as never)
        .select('id, role_family, purpose, stage, deadline_at, target_role_version_id, created_at')
        .or(orFilter)
        .order('created_at', { ascending: false })
        .limit(20)
      if (error) setErr(error.message)
      setRuns((data ?? []) as Run[])
    })()
  }, [supabase, row.id, row.family])

  if (err) return <Card><CardBody><div className="text-sm text-rust">{err}</div></CardBody></Card>
  if (runs === null) return <Card><CardBody><div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading team-definition history…</div></CardBody></Card>
  if (runs.length === 0) return (
    <Card><CardBody className="flex flex-col gap-3">
      <div className="flex items-center gap-2 text-muted">
        <Users size={14} />
        <span className="text-sm">No team-definition runs touch this role yet.</span>
      </div>
      <p className="text-xs text-faint max-w-prose">
        Team-based role definition produces a signed-off role version through independent
        rating → divergence surfacing → reconciliation. Use it when an existing role needs
        to be re-anchored to current reality, or when a new role family is being defined.
      </p>
      <div>
        <Link to={`/team-def/new?family=${encodeURIComponent(row.family ?? '')}&template_role_id=${row.id}`}
              className="inline-flex items-center gap-1.5 text-sm text-role hover:underline">
          Start a team-definition run <ChevronRight size={14} />
        </Link>
      </div>
    </CardBody></Card>
  )
  return (
    <Card><CardBody className="flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <p className="eyebrow">Team-definition runs ({runs.length})</p>
        <Link to={`/team-def/new?family=${encodeURIComponent(row.family ?? '')}&template_role_id=${row.id}`}
              className="text-xs text-role hover:underline">Start a new run →</Link>
      </div>
      <ul className="flex flex-col gap-2">
        {runs.map(r => (
          <li key={r.id}>
            <Link to={`/team-def/${r.id}`}
                  className="flex items-center justify-between gap-3 border border-line rounded p-3 hover:bg-canvas-2 transition-colors">
              <div className="flex-1 min-w-0">
                <div className="text-sm font-mono">run #{r.id.slice(0, 8)}</div>
                <div className="text-xs text-faint mt-0.5">
                  {r.role_family} · {r.purpose.replace(/_/g, ' ')} · deadline {new Date(r.deadline_at).toLocaleDateString()}
                </div>
              </div>
              <Pill tone={r.stage === 'signed_off' ? 'open' : r.stage === 'reconciliation' ? 'interview' : 'draft'}>
                {r.stage.replace(/_/g, ' ')}
              </Pill>
              <ChevronRight size={14} className="text-faint" />
            </Link>
          </li>
        ))}
      </ul>
    </CardBody></Card>
  )
}

// ─── Version history tab ────────────────────────────────────────────
// Pulls sibling versions via fetchRoleVersionHistory. Renders the
// version timeline with the currently-viewed version highlighted.
function VersionsTab({ row }: { row: RoleProfileRow }) {
  const supabase = browserSupabase()
  const [history, setHistory] = useState<RoleProfileRow[] | null>(null)
  const [err, setErr] = useState<string | null>(null)
  useEffect(() => {
    fetchRoleVersionHistory(supabase, row.id)
      .then(h => setHistory(h))
      .catch(e => setErr(e instanceof Error ? e.message : 'Failed to load'))
  }, [supabase, row.id])

  if (err) return <Card><CardBody><div className="text-sm text-rust">{err}</div></CardBody></Card>
  if (history === null) return <Card><CardBody><div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading version history…</div></CardBody></Card>
  if (history.length === 0) return (
    <Card><CardBody>
      <p className="text-sm text-muted">No version history found for this role.</p>
    </CardBody></Card>
  )
  return (
    <Card><CardBody className="flex flex-col gap-3">
      <p className="eyebrow">Version history ({history.length})</p>
      <ul className="flex flex-col gap-1.5">
        {history.map(v => {
          const isCurrent = v.id === row.id
          return (
            <li key={v.id} className={'flex items-center gap-3 border rounded px-3 py-2 ' + (isCurrent ? 'border-role bg-canvas-2' : 'border-line')}>
              <div className="font-mono text-xs w-12">v{v.version}</div>
              <div className="flex-1 min-w-0">
                <div className="text-sm">{v.title}</div>
                <div className="text-xs text-faint mt-0.5">
                  {v.is_template ? 'template' : 'instance'} · {v.signed_off_at ? `signed off ${new Date(v.signed_off_at).toLocaleDateString()}` : 'draft'}
                </div>
              </div>
              {isCurrent && <Pill tone="open">viewing</Pill>}
              {!isCurrent && (
                <Link to={`/role/${v.id}`} className="text-xs text-role hover:underline">View →</Link>
              )}
            </li>
          )
        })}
      </ul>
    </CardBody></Card>
  )
}

// ─── Defensibility tab ──────────────────────────────────────────────
// Renders the role's `validation_and_defensibility_metadata` JSON in
// human-readable form. The metadata is populated when a team-definition
// run reaches sign-off. For roles without it (e.g. legacy templates
// before team-def existed), we render an honest "this role has no
// defensibility provenance" panel rather than a blank.
function DefensibilityTab({ row }: { row: RoleProfileRow }) {
  // The schema parks defensibility metadata inside definition_json (see
  // types/roleProfile.ts §ValidationMetadata). It is not a top-level
  // column on roles_catalog. Keep the read close to the schema shape
  // so a future migration that promotes specific fields to columns
  // can be done without touching this view.
  const meta = row.definition_json?.validation_and_defensibility_metadata
  const sof  = row.signed_off_at
  const runId = (meta as { sme_delphi_record_ref?: string } | undefined)?.sme_delphi_record_ref ?? null
  if (!meta || Object.keys(meta).length === 0) {
    return (
      <Card><CardBody className="flex flex-col gap-2">
        <div className="flex items-center gap-2 text-muted">
          <ShieldCheck size={14} />
          <span className="text-sm">No defensibility provenance attached to this version.</span>
        </div>
        <p className="text-xs text-faint max-w-prose">
          A team-definition sign-off attaches structured provenance: who evaluated, when, the
          method (Delphi / single-expert / kickstart), and the run that produced it. Without
          that, defending this role under audit means showing the rationale by hand. Re-anchor
          via Team-based Role Definition to produce a signed-off version with full provenance.
        </p>
      </CardBody></Card>
    )
  }
  return (
    <Card><CardBody className="flex flex-col gap-4">
      <p className="eyebrow">Defensibility provenance</p>
      <dl className="grid grid-cols-1 sm:grid-cols-2 gap-4 text-sm">
        <div>
          <dt className="text-xs text-muted">Method</dt>
          <dd className="font-mono">{meta.validation_method ?? 'unspecified'}</dd>
        </div>
        <div>
          <dt className="text-xs text-muted">Inter-rater agreement</dt>
          <dd className="font-mono">{meta.inter_rater_agreement ?? '—'}</dd>
        </div>
        <div>
          <dt className="text-xs text-muted">Signed off</dt>
          <dd>{sof ? new Date(sof).toLocaleString() : '—'}</dd>
        </div>
        <div>
          <dt className="text-xs text-muted">Run</dt>
          <dd>
            {runId ? (
              <Link to={`/team-def/${runId}`} className="font-mono text-xs text-role hover:underline">
                {runId.slice(0, 8)} →
              </Link>
            ) : '—'}
          </dd>
        </div>
        <div>
          <dt className="text-xs text-muted">Framing default</dt>
          <dd className="font-mono">{meta.framing_default ?? '—'}</dd>
        </div>
        <div>
          <dt className="text-xs text-muted">Next review</dt>
          <dd>{meta.next_review_date ? new Date(meta.next_review_date).toLocaleDateString() : '—'}</dd>
        </div>
      </dl>
      {meta._dev_stub && (
        <div className="rounded border border-line bg-canvas p-3 text-xs text-muted">
          This provenance carries <code>_dev_stub=true</code>. The structural fields above are
          real; the numeric values they reference (validity, fairness verdicts) remain expert-
          gated until I/O-psych and legal sign-off (see SCIENCE-SPEC.md §H-1 through §H-6).
        </div>
      )}
    </CardBody></Card>
  )
}

// ─── Manage tab ─────────────────────────────────────────────────────
// Operational actions on the role version: archive (if currently
// signed-off), open the team-definition flow to supersede with a new
// version, link to use-for-requisition. Archive is intentionally a
// stub UI — the underlying RPC for archive isn't built yet; we show
// the seam honestly rather than fabricating it.
function ManageTab({ row }: { row: RoleProfileRow }) {
  return (
    <Card><CardBody className="flex flex-col gap-4">
      <p className="eyebrow">Manage this version</p>
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
        <Link to={`/team-def/new?family=${encodeURIComponent(row.family ?? '')}&template_role_id=${row.id}`}
              className="border border-line rounded p-3 hover:bg-canvas-2 transition-colors">
          <div className="font-semibold">Supersede via team definition</div>
          <p className="text-xs text-faint mt-1">
            Open a new team-definition run anchored on this version. Sign-off creates a new
            version that supersedes this one.
          </p>
        </Link>
        <Link to="/req"
              className="border border-line rounded p-3 hover:bg-canvas-2 transition-colors">
          <div className="font-semibold">Use for a requisition</div>
          <p className="text-xs text-faint mt-1">
            Open the requisitions list to attach this signed-off role version to an open
            hiring intent.
          </p>
        </Link>
      </div>
      <div className="border border-line rounded p-3 text-xs text-muted">
        <strong>Archive this version</strong> — not yet implemented. The signed-off role
        version is the system of record for past hiring decisions and cannot be silently
        retracted. A future migration adds a <code>roles_catalog.archived_at</code> column
        plus a <code>role_archive(role_id, rationale)</code> RPC that writes to audit_log.
        Until then, archive by superseding via team-definition (above).
      </div>
    </CardBody></Card>
  )
}
