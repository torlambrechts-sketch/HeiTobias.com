import { useCallback, useEffect, useMemo, useState } from 'react'
import { AlertTriangle, ChevronDown, ChevronRight, Loader2, RefreshCw, ShieldAlert } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import { Card, CardBody, CardEyebrow, CardTitle } from '../ui/card.js'
import { Button } from '../ui/button.js'
import { Pill, StubBadge } from '../ui/badges.js'
import { EmptyState } from '../ui/EmptyState.js'
import { ErrorState } from '../ui/ErrorState.js'

// Personality panel for the recruiter candidate detail.
//
// Renders three pieces:
//   1. Trait T-scores (one row per scored trait, with dev_stub badges).
//   2. The chosen role-template's match number + per-trait contributions
//      sorted by penalty desc.
//   3. HUMAN-REVIEW flags, clearly separated and labelled — these
//      NEVER reduced the match number (the schema enforces it too).
//
// CLAUDE.md "fit informs, never decides" appears on the panel as the
// canonical HitlNotice-style call-out. No surface here triggers an
// action — recruiters read this and use it as input to the structured
// interview + the hiring decision recorded elsewhere.
//
// All data comes from existing tables seeded by
// personality_compute_scores: assessment_scores (scale_key = 'trait:*')
// and personality_role_matches.

interface TraitScore {
  trait_key: string
  trait_name: string
  domain: string
  sensitive: boolean
  percentile: number | null
  t_score: number | null
  raw_mean: number | null
  norm_band: string | null
  n_responses: number | null
  is_stub: boolean
  validity_status: 'dev_stub' | 'licensed' | 'validated'
  note: string | null
}

interface RoleMatchContribution {
  trait: string
  percentile: number
  band: [number, number]
  direction: 'higher_better' | 'lower_better' | 'target_band'
  weight: number
  severity: number
  penalty: number
}

interface RoleMatchFlag {
  trait: string
  percentile: number
  threshold: number
}

interface RoleMatchRow {
  id: string
  role_key: string
  role_title: string
  match_score: number | null
  contributions: RoleMatchContribution[]
  flags: RoleMatchFlag[]
  is_stub: boolean
  validity_status: 'dev_stub' | 'licensed' | 'validated'
}

interface Props {
  /** The candidate's assessment_sessions.id. */
  sessionId: string
  /** Optional: pre-select a role template (e.g. the requisition's role family). */
  initialRoleKey?: string
  /** Org id; used for the recompute RPC's authorization path. */
  orgId: string
}

export function PersonalityPanel({ sessionId, initialRoleKey, orgId }: Props) {
  const supabase = browserSupabase()
  const [traits, setTraits] = useState<TraitScore[] | null>(null)
  const [matches, setMatches] = useState<RoleMatchRow[] | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [selectedRole, setSelectedRole] = useState<string | null>(initialRoleKey ?? null)

  const load = useCallback(async () => {
    setError(null)
    // CRITICAL: scope trait scores to this session's assessment, not all
    // org-visible scores. Without this filter the panel would render
    // every candidate's trait rows the recruiter can read (RLS scopes
    // to the org, not to one candidate) — the audit caught this as a
    // real data-leak.
    //
    // We resolve the session → invite.assessment_id mapping first, then
    // fetch scores filtered by it. Role-matches are already session-id-
    // keyed so they need no extra hop.
    const sessRaw = await supabase.from('assessment_sessions' as never)
      .select('invite_id')
      .eq('id', sessionId)
      .maybeSingle()
    const sessRes = sessRaw as { data: { invite_id: string } | null; error: { message: string } | null }
    if (sessRes.error) { setError(sessRes.error.message); setTraits([]); setMatches([]); return }
    if (!sessRes.data) { setError('Session not found.'); setTraits([]); setMatches([]); return }

    const invRaw = await supabase.from('assessment_invites' as never)
      .select('assessment_id')
      .eq('id', sessRes.data.invite_id)
      .maybeSingle()
    const invRes = invRaw as { data: { assessment_id: string } | null; error: { message: string } | null }
    if (invRes.error) { setError(invRes.error.message); setTraits([]); setMatches([]); return }
    const assessmentId = invRes.data?.assessment_id ?? null

    const [scoresRaw, matchesRaw] = await Promise.all([
      supabase.from('assessment_scores' as never)
        .select('scale_key, raw_score, scaled_score, norm_band, validity_status, _dev_stub, validity_flags_json, assessment_id')
        .like('scale_key', 'trait:%')
        .eq('assessment_id', assessmentId ?? '00000000-0000-0000-0000-000000000000'),
      supabase.from('personality_role_matches' as never)
        .select('id, role_key, match_score, contributions_json, flags_json, validity_status, _dev_stub, session_id')
        .eq('session_id', sessionId),
    ])
    const scoresRes  = scoresRaw  as { data: unknown[] | null; error: { message: string } | null }
    const matchesRes = matchesRaw as { data: unknown[] | null; error: { message: string } | null }
    if (scoresRes.error)  { setError(scoresRes.error.message);  setTraits([]);  return }
    if (matchesRes.error) { setError(matchesRes.error.message); setMatches([]); return }

    // Trait metadata join. We fetch trait registry rows for every
    // trait_key referenced by a score, in one round-trip.
    const scoreRows = (scoresRes.data ?? []) as Array<{
      scale_key: string
      raw_score: number | null
      scaled_score: number | null
      norm_band: string | null
      validity_status: 'dev_stub' | 'licensed' | 'validated'
      _dev_stub: boolean
      validity_flags_json: { percentile?: number | null; n_keyed_responses?: number | null; note?: string | null } | null
    }>
    const traitKeys = scoreRows.map(s => s.scale_key.replace(/^trait:/, ''))
    const traitRes = await supabase.from('personality_traits' as never)
      .select('trait_key, name, domain, sensitive')
      .in('trait_key', traitKeys)
    const traitMeta = ((traitRes as { data: unknown[] | null }).data ?? []) as Array<{
      trait_key: string; name: string; domain: string; sensitive: boolean
    }>
    const metaByKey = new Map(traitMeta.map(m => [m.trait_key, m]))

    setTraits(scoreRows.map<TraitScore>(s => {
      const key = s.scale_key.replace(/^trait:/, '')
      const meta = metaByKey.get(key)
      return {
        trait_key: key,
        trait_name: meta?.name ?? key,
        domain: meta?.domain ?? '',
        sensitive: meta?.sensitive ?? false,
        percentile: s.validity_flags_json?.percentile ?? null,
        t_score: s.scaled_score,
        raw_mean: s.raw_score,
        norm_band: s.norm_band,
        n_responses: s.validity_flags_json?.n_keyed_responses ?? null,
        is_stub: s._dev_stub,
        validity_status: s.validity_status,
        note: s.validity_flags_json?.note ?? null,
      }
    }))

    // Role-match enrichment with title.
    const matchRows = (matchesRes.data ?? []) as Array<{
      id: string
      role_key: string
      match_score: number | null
      contributions_json: RoleMatchContribution[]
      flags_json: RoleMatchFlag[]
      validity_status: 'dev_stub' | 'licensed' | 'validated'
      _dev_stub: boolean
    }>
    const roleKeys = matchRows.map(m => m.role_key)
    const templateRes = await supabase.from('personality_role_templates' as never)
      .select('role_key, title')
      .in('role_key', roleKeys)
    const templates = ((templateRes as { data: unknown[] | null }).data ?? []) as Array<{
      role_key: string; title: string
    }>
    const titleByKey = new Map(templates.map(t => [t.role_key, t.title]))

    const matchList = matchRows.map<RoleMatchRow>(m => ({
      id: m.id,
      role_key: m.role_key,
      role_title: titleByKey.get(m.role_key) ?? m.role_key,
      match_score: m.match_score,
      contributions: Array.isArray(m.contributions_json) ? m.contributions_json : [],
      flags: Array.isArray(m.flags_json) ? m.flags_json : [],
      is_stub: m._dev_stub,
      validity_status: m.validity_status,
    }))
    matchList.sort((a, b) => (b.match_score ?? -1) - (a.match_score ?? -1))
    setMatches(matchList)
    if (!selectedRole && matchList[0]) setSelectedRole(matchList[0].role_key)
  }, [supabase, sessionId, selectedRole])

  useEffect(() => { void load() }, [load])

  const recompute = useCallback(async () => {
    setBusy(true)
    const { error } = await supabase.rpc('personality_compute_scores' as never, { p_session_id: sessionId } as never)
    setBusy(false)
    if (error) { setError(error.message); return }
    await load()
  }, [supabase, sessionId, load])

  // Identify the dominant match for the selected role.
  const selected = useMemo(() => matches?.find(m => m.role_key === selectedRole) ?? null, [matches, selectedRole])

  if (error) {
    return <Card><CardBody><ErrorState message={error} onRetry={() => void load()} /></CardBody></Card>
  }
  if (traits === null || matches === null) {
    return (
      <Card><CardBody>
        <div className="text-faint text-sm flex items-center gap-2"><Loader2 size={14} className="animate-spin" /> Loading personality results…</div>
      </CardBody></Card>
    )
  }
  if (traits.length === 0 && matches.length === 0) {
    return (
      <Card><CardBody>
        <EmptyState
          title="No personality results yet"
          body={<>The candidate hasn't completed the personality section, or scoring hasn't run.
            Run the scoring engine when the section is complete.</>}
          action={<Button onClick={recompute} disabled={busy}>
            {busy ? <Loader2 size={14} className="animate-spin" /> : <RefreshCw size={14} />}
            Run scoring
          </Button>}
        />
      </CardBody></Card>
    )
  }

  return (
    <div className="flex flex-col gap-4" data-test="personality-panel">
      {/* Inform-not-decide notice — the canonical HitlNotice voice. */}
      <Card>
        <CardBody className="flex items-start gap-3 border-l-2 border-l-forest pl-4 py-3">
          <ShieldAlert size={16} className="text-forest flex-shrink-0 mt-0.5" />
          <div className="text-sm leading-relaxed">
            <strong>Fit informs, never decides.</strong> These numbers support your structured
            interview and decision-making — they do not make the decision. Every hiring action
            requires a named human rationale (GDPR Art. 22 + EU AI Act Art. 14).
          </div>
        </CardBody>
      </Card>

      {/* Trait T-scores table. */}
      <Card>
        <CardEyebrow>Personality</CardEyebrow>
        <CardTitle>Trait scores</CardTitle>
        <CardBody>
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-line text-[10.5px] uppercase tracking-wider text-muted">
                  <th className="text-left py-2">Trait</th>
                  <th className="text-left">Domain</th>
                  <th className="text-right">Percentile</th>
                  <th className="text-right">T-score</th>
                  <th className="text-left pl-3">Band</th>
                  <th className="text-left pl-3">Provenance</th>
                </tr>
              </thead>
              <tbody>
                {traits.map(t => (
                  <tr key={t.trait_key} className="border-b border-line">
                    <td className="py-2">
                      <div className="font-semibold flex items-center gap-2">
                        {t.trait_name}
                        {t.sensitive && (
                          <span className="text-[10.5px] text-amber font-mono uppercase tracking-wider" title="Human-review trait: surfaced as a flag on role matches, never as a numeric input.">
                            sensitive
                          </span>
                        )}
                      </div>
                    </td>
                    <td className="text-xs text-muted">{t.domain}</td>
                    <td className="text-right font-mono">{t.percentile ?? '—'}</td>
                    <td className="text-right font-mono">{t.t_score ?? '—'}</td>
                    <td className="pl-3">
                      {t.norm_band ? <Pill tone={t.norm_band === 'high' ? 'open' : t.norm_band === 'low' ? 'reject' : 'draft'}>{t.norm_band}</Pill> : '—'}
                    </td>
                    <td className="pl-3">
                      {t.is_stub && <StubBadge />}
                      {t.note && <div className="text-[10.5px] text-faint mt-1 max-w-[200px]">{t.note}</div>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <p className="text-xs text-faint mt-3">
            T-scores are normed to M=50, SD=10. Higher = more of the trait as scored
            (see the methodology page for each trait's <em>scored direction</em>).
          </p>
        </CardBody>
      </Card>

      {/* Role-match selector + per-template breakdown. */}
      <Card>
        <CardEyebrow>Role match</CardEyebrow>
        <CardTitle>How this candidate's profile compares to role benchmarks</CardTitle>
        <CardBody className="flex flex-col gap-4">
          <div className="flex items-center gap-3 flex-wrap">
            <label className="text-xs text-muted">Role template</label>
            <select
              value={selectedRole ?? ''}
              onChange={e => setSelectedRole(e.target.value)}
              className="border border-line rounded px-3 py-1.5 text-sm bg-surface"
              data-test="personality-role-select"
            >
              {matches.map(m => (
                <option key={m.role_key} value={m.role_key}>
                  {m.role_title} — match {m.match_score ?? '—'}
                </option>
              ))}
            </select>
            <Button variant="ghost" onClick={recompute} disabled={busy} className="text-xs">
              {busy ? <Loader2 size={12} className="animate-spin" /> : <RefreshCw size={12} />}
              Recompute
            </Button>
            <span className="ml-auto text-xs text-muted" data-test="org-context">org {orgId.slice(0, 8)}</span>
          </div>

          {selected && (
            <>
              <div className="flex items-baseline gap-4 border border-line rounded-lg p-4 bg-canvas-2">
                <div>
                  <p className="text-[10.5px] uppercase tracking-wider font-bold text-muted">Match</p>
                  <p className="font-display text-4xl font-bold">{selected.match_score ?? '—'}</p>
                  {selected.is_stub && <div className="mt-1"><StubBadge /></div>}
                </div>
                <div className="flex-1 text-xs text-muted leading-relaxed">
                  This is a <strong>band-deviation score</strong>: 100 means every contributing
                  trait sits inside its target band. Penalties accumulate as a trait drifts
                  outside its band, capped at one band-width-equivalent
                  ({selected.contributions.length > 0 ? 'see contributions below' : 'no contributions'}).
                </div>
              </div>

              {/* HUMAN-REVIEW flags box. Distinct visual treatment so it
                  cannot be mistaken for a contribution to the score. */}
              {selected.flags.length > 0 && (
                <div className="rounded-lg border-2 border-amber/60 bg-internal-bg/40 p-3" data-test="personality-flags">
                  <div className="flex items-start gap-2 mb-2">
                    <AlertTriangle size={16} className="text-amber flex-shrink-0 mt-0.5" />
                    <div className="text-sm">
                      <strong>Human-review flag{selected.flags.length > 1 ? 's' : ''}.</strong>{' '}
                      These percentiles crossed a review threshold. <strong>They do not
                      reduce the match number above.</strong> Use them as discussion / probe
                      inputs in the structured interview — never as an automatic
                      disqualifier (CLAUDE.md / EU AI Act Annex III).
                    </div>
                  </div>
                  <ul className="text-sm flex flex-col gap-1 mt-1">
                    {selected.flags.map(f => (
                      <li key={f.trait} className="flex items-center justify-between border-t border-amber/40 pt-1">
                        <span className="font-medium">{f.trait}</span>
                        <span className="font-mono text-xs">percentile {f.percentile} ≥ threshold {f.threshold}</span>
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              {/* Contributions, sorted by penalty desc (the engine already
                  sorts; we render in order). */}
              <div>
                <p className="eyebrow mb-2">Contributions (highest-penalty first)</p>
                {selected.contributions.length === 0 ? (
                  <p className="text-sm text-faint">Every contributing trait is inside its band. The match is at ceiling.</p>
                ) : (
                  <ContributionsList rows={selected.contributions} />
                )}
              </div>
            </>
          )}
        </CardBody>
      </Card>

      {/* All-templates compact ranking. Useful when a recruiter wants to
          see at a glance which roles this candidate matches best,
          independent of the requisition's pinned role. */}
      <Card>
        <CardEyebrow>All role templates</CardEyebrow>
        <CardTitle>Match across the library</CardTitle>
        <CardBody>
          <ul className="text-sm flex flex-col gap-1">
            {matches.map(m => (
              <li key={m.role_key} className="flex items-center gap-3 border-b border-line py-1.5">
                <button
                  type="button"
                  onClick={() => setSelectedRole(m.role_key)}
                  className={'flex-1 text-left ' + (m.role_key === selectedRole ? 'text-forest font-medium' : 'hover:text-ink text-muted')}
                >
                  {m.role_title}
                </button>
                {m.flags.length > 0 && (
                  <span className="text-[10.5px] text-amber" title={m.flags.length + ' human-review flag(s)'}>
                    ⚑ {m.flags.length}
                  </span>
                )}
                <span className="font-mono text-xs w-8 text-right">{m.match_score ?? '—'}</span>
                {m.is_stub && <StubBadge />}
              </li>
            ))}
          </ul>
        </CardBody>
      </Card>
    </div>
  )
}

function ContributionsList({ rows }: { rows: RoleMatchContribution[] }) {
  const [expanded, setExpanded] = useState(false)
  const visible = expanded ? rows : rows.slice(0, 5)
  return (
    <>
      <ul className="text-sm flex flex-col gap-1">
        {visible.map(c => (
          <li key={c.trait} className="grid grid-cols-[1fr_auto_auto_auto] gap-3 items-center border-b border-line py-1.5">
            <span className="font-medium">{c.trait}</span>
            <span className="text-xs text-muted">{c.direction.replace('_', ' ')} · band {c.band[0]}–{c.band[1]} · pct {c.percentile}</span>
            <span className="font-mono text-xs w-20 text-right">w {c.weight.toFixed(2)}</span>
            <span className="font-mono text-xs w-20 text-right">penalty {c.penalty.toFixed(3)}</span>
          </li>
        ))}
      </ul>
      {rows.length > 5 && (
        <button
          type="button"
          onClick={() => setExpanded(v => !v)}
          className="mt-2 text-xs text-role hover:underline flex items-center gap-1"
        >
          {expanded ? <ChevronDown size={12} /> : <ChevronRight size={12} />}
          {expanded ? 'Show fewer' : `Show all ${rows.length}`}
        </button>
      )}
    </>
  )
}
