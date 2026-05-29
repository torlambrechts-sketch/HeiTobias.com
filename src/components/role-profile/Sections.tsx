import { AlertTriangle, BarChart3, Briefcase, CheckCircle2, Compass, FileText, Layers, ScrollText, TrendingUp, Users, ShieldCheck } from 'lucide-react'
import type { RoleProfileRow } from '../../types/roleProfile.js'
import { criticalWeightSum } from '../../types/roleProfile.js'
import { Card, CardBody, CardEyebrow, CardTitle } from '../ui/card.js'
import { Pill } from '../ui/badges.js'
import { TraitRangeControl } from '../TraitRangeControl.js'
import { StubPill } from './StubBanner.js'

// One <SectionAnchor /> per §2.7 section; the sticky subnav (CP6) scrolls
// to these. Kept tight per DESIGN.md tokens; no hardcoded colors.

export function SectionAnchor({ id, children }: { id: string; children: React.ReactNode }) {
  return <section id={id} className="scroll-mt-20">{children}</section>
}

// ============ 01 · Identity & governance ============
export function IdentityGovernanceSection({ row }: { row: RoleProfileRow }) {
  const ig = row.definition_json.identity_and_governance
  const codes = ig?.external_codes
  return (
    <SectionAnchor id="identity">
      <Card>
        <CardEyebrow><ShieldCheck size={12} /> 01 · Identity & governance</CardEyebrow>
        <CardTitle>Versioning, sign-off, external codes</CardTitle>
        <CardBody>
          <div className="grid lg:grid-cols-2 gap-3 text-sm">
            <Row k="Version status" v={<Pill>{ig?.version_status ?? '—'}</Pill>} />
            <Row k="Validation status" v={
              <span className="flex items-center gap-2">
                <Pill>{ig?.validation_status ?? '—'}</Pill>
                <StubPill on={ig?.validation_status === 'dev_stub'} />
              </span>
            } />
            <Row k="Effective from" v={ig?.effective_from ?? '—'} />
            <Row k="Effective to" v={ig?.effective_to ?? '—'} />
            <Row k="O*NET-SOC" v={codes?.onet_soc ?? <em className="text-faint">not coded</em>} />
            <Row k="ESCO" v={codes?.esco ?? <em className="text-faint">not coded</em>} />
            <Row k="Signed-off by" v={
              (ig?.signed_off_by?.length ?? 0) === 0
                ? <em className="text-faint">not yet signed off</em>
                : <span className="text-xs font-mono">{ig!.signed_off_by!.length} attestation(s)</span>
            } />
            <Row k="Evidence refs" v={
              (ig?.validation_evidence_refs?.length ?? 0) === 0
                ? <em className="text-faint">none</em>
                : <span className="text-xs font-mono">{(ig!.validation_evidence_refs as string[]).join(' · ')}</span>
            } />
          </div>
        </CardBody>
      </Card>
    </SectionAnchor>
  )
}

// ============ 02 · Tasks & outcomes ============
export function TasksSection({ row }: { row: RoleProfileRow }) {
  const tasks = row.definition_json.task_layer ?? []
  return (
    <SectionAnchor id="tasks">
      <Card>
        <CardEyebrow><Briefcase size={12} /> 02 · Tasks & outcomes</CardEyebrow>
        <CardTitle>Work activities anchoring this role</CardTitle>
        <CardBody>
          {tasks.length === 0 && <p className="text-faint text-sm"><em>No task layer recorded yet.</em></p>}
          <ul className="flex flex-col gap-3">
            {tasks.map((t, i) => (
              <li key={i} className="border-l-2 border-line pl-3">
                <div className="flex items-center gap-2 mb-1">
                  <span className="font-display text-base">{t.task}</span>
                  {t.criticality && <Pill>{t.criticality}</Pill>}
                  <StubPill on={Boolean(t._dev_stub)} />
                </div>
                <div className="text-xs text-faint flex flex-wrap gap-x-3 gap-y-1">
                  {t.frequency && <span>frequency: <strong>{t.frequency}</strong></span>}
                  {t.outcomes && <span>outcomes: <strong>{t.outcomes}</strong></span>}
                  {t.tools && <span>tools: <strong>{t.tools}</strong></span>}
                </div>
              </li>
            ))}
          </ul>
        </CardBody>
      </Card>
    </SectionAnchor>
  )
}

// ============ 03 · Weighted competencies ============
export function CompetenciesSection({ row }: { row: RoleProfileRow }) {
  const comps = row.definition_json.competencies ?? []
  const cw = criticalWeightSum(row)
  return (
    <SectionAnchor id="competencies">
      <Card>
        <CardEyebrow><BarChart3 size={12} /> 03 · Weighted competencies</CardEyebrow>
        <CardTitle>What is being assessed against</CardTitle>
        <CardBody>
          {comps.length === 0 && <p className="text-faint text-sm"><em>No competencies recorded yet.</em></p>}
          <div className="grid gap-3">
            {comps.map((c, i) => (
              <div key={c.key ?? i} className="border border-line rounded p-3">
                <div className="flex items-center gap-2 mb-2 flex-wrap">
                  <span className="font-display text-base">{c.name ?? c.key}</span>
                  {c.criticality && <Pill>{c.criticality}</Pill>}
                  <span className="text-xs font-mono text-faint ml-auto">weight {c.weight.toFixed(2)}</span>
                  <StubPill on={Boolean(c._dev_stub)} />
                </div>
                <div className="h-1.5 bg-canvas-2 rounded-full overflow-hidden mb-2">
                  <div className="h-full bg-forest" style={{ width: `${Math.min(100, c.weight * 100)}%` }} />
                </div>
                {c.description && <p className="text-sm text-ink/90 mb-2">{c.description}</p>}
                {(c.bars_anchors?.length ?? 0) > 0 && (
                  <ul className="text-xs text-faint border-l-2 border-line pl-2 flex flex-col gap-0.5">
                    {c.bars_anchors!.map((a, ai) => <li key={ai}>{a}</li>)}
                  </ul>
                )}
                <div className="text-[11px] font-mono text-faint mt-2">
                  {c.framework_mapping && <>framework: {c.framework_mapping} · </>}
                  {c.derivation_method && <>derivation: {c.derivation_method}</>}
                </div>
              </div>
            ))}
          </div>
          {cw && (
            <div className={'mt-4 rounded border p-3 text-sm flex items-center gap-2 ' +
              (cw.satisfied ? 'border-green-300 bg-green-50 text-green-900' : 'border-red-300 bg-red-50 text-red-900')}>
              {cw.satisfied ? <CheckCircle2 size={14} /> : <AlertTriangle size={14} />}
              <span>
                Critical-set weights sum = <strong>{cw.sum.toFixed(2)}</strong>.{' '}
                {cw.satisfied
                  ? 'Schema check passed (1.00 ± 0.005).'
                  : 'Schema check FAILED — critical weights must sum to 1.00 (±0.005). The I/O psychologist needs to rebalance.'}
              </span>
            </div>
          )}
        </CardBody>
      </Card>
    </SectionAnchor>
  )
}

// ============ 04 · Trait target bands ============
export function TraitTargetsSection({ row }: { row: RoleProfileRow }) {
  const targets = row.definition_json.trait_targets ?? []
  return (
    <SectionAnchor id="trait_targets">
      <Card>
        <CardEyebrow><Compass size={12} /> 04 · Trait target bands</CardEyebrow>
        <CardTitle>Personality bands — RANGES, not maxima (SCIENCE-SPEC §2)</CardTitle>
        <CardBody>
          {targets.length === 0 && <p className="text-faint text-sm"><em>No trait targets recorded yet.</em></p>}
          <div className="grid gap-6 lg:grid-cols-2">
            {targets.map((t, i) => (
              <TraitRangeControl key={`${t.trait}-${i}`} target={t} />
            ))}
          </div>
          <p className="text-xs text-faint mt-4">
            Bands encode <strong>direction + centre + lower + upper</strong> per Le 2011 / Pierce & Aguinis 2013 / Grant 2013.
            A bare-maximum optimum target is a schema violation and renders as an error.
          </p>
        </CardBody>
      </Card>
    </SectionAnchor>
  )
}

// ============ 05 · Cognitive demand (CP4 placeholder; full in CP4) ============
export function CognitiveDemandSection({ row }: { row: RoleProfileRow }) {
  const c = row.definition_json.cognitive_demand
  return (
    <SectionAnchor id="cognitive">
      <Card>
        <CardEyebrow><Layers size={12} /> 05 · Cognitive demand</CardEyebrow>
        <CardTitle>Complexity-conditioned, range-with-caveat</CardTitle>
        <CardBody>
          {!c && <p className="text-faint text-sm"><em>No cognitive demand recorded yet.</em></p>}
          {c && (
            <div className="grid lg:grid-cols-2 gap-3 text-sm">
              <Row k="Complexity level" v={
                <span className="flex items-center gap-2">
                  <Pill>{c.complexity_level ?? '—'}</Pill>
                  <span className="text-xs text-faint">(1–5)</span>
                </span>
              } />
              <Row k="Use as" v={<Pill>{c.use_as ?? '—'}</Pill>} />
              <Row k="Target band" v={
                c.target_band ? `${c.target_band.lower?.toFixed(2) ?? '—'} – ${c.target_band.upper?.toFixed(2) ?? '—'}` : <em className="text-faint">none</em>
              } />
              <Row k="Validity (range)" v={
                c.validity_estimate_range ?
                  <span className="text-xs">
                    ρ ≈ {c.validity_estimate_range.low?.toFixed(2)} – {c.validity_estimate_range.high?.toFixed(2)}
                    {c.validity_estimate_range.caveat && <em className="text-faint"> · {c.validity_estimate_range.caveat}</em>}
                  </span> : <em className="text-faint">none</em>
              } />
              {c.complexity_level_justification && (
                <div className="lg:col-span-2 border-l-2 border-line pl-3 text-sm text-ink/90">
                  {c.complexity_level_justification}
                </div>
              )}
              <div className="lg:col-span-2 flex items-center gap-2">
                <StubPill on={Boolean(c._dev_stub)} />
              </div>
            </div>
          )}
        </CardBody>
      </Card>
    </SectionAnchor>
  )
}

// ============ 06 · Context factors (Trait Activation) ============
const CTX_KEYS: { k: keyof NonNullable<RoleProfileRow['definition_json']['context_factors']>; label: string }[] = [
  { k: 'autonomy', label: 'Autonomy' },
  { k: 'ambiguity_tolerance_required', label: 'Ambiguity tolerance' },
  { k: 'pace_and_urgency', label: 'Pace & urgency' },
  { k: 'collaboration_intensity', label: 'Collaboration intensity' },
  { k: 'stakeholder_load', label: 'Stakeholder load' },
  { k: 'cognitive_complexity', label: 'Cognitive complexity' },
  { k: 'adversity_exposure', label: 'Adversity exposure' },
  { k: 'psychological_safety_dependence', label: 'Psych safety dependence' },
  { k: 'feedback_frequency', label: 'Feedback frequency' },
]

export function ContextFactorsSection({ row }: { row: RoleProfileRow }) {
  const ctx = row.definition_json.context_factors
  return (
    <SectionAnchor id="context">
      <Card>
        <CardEyebrow><Compass size={12} /> 06 · Context factors</CardEyebrow>
        <CardTitle>Trait Activation context (Tett & Burnett 2003)</CardTitle>
        <CardBody>
          {!ctx && <p className="text-faint text-sm"><em>No context factors recorded yet.</em></p>}
          {ctx && (
            <>
              <div className="grid lg:grid-cols-3 gap-3 text-sm">
                {CTX_KEYS.map(({ k, label }) => {
                  const v = ctx[k] as number | undefined
                  return (
                    <div key={k} className="border border-line rounded p-2">
                      <div className="flex items-center justify-between mb-1">
                        <span className="text-xs uppercase tracking-wider font-bold text-muted">{label}</span>
                        <span className="text-xs font-mono">{v ?? '—'}/5</span>
                      </div>
                      <div className="h-1.5 bg-canvas-2 rounded-full overflow-hidden">
                        <div className="h-full bg-forest" style={{ width: `${Math.min(100, (v ?? 0) / 5 * 100)}%` }} />
                      </div>
                    </div>
                  )
                })}
              </div>
              <div className={'mt-4 rounded border p-3 text-sm ' +
                (ctx.coherence_check_passed === false ? 'border-red-300 bg-red-50 text-red-900' : 'border-role/30 bg-role/5 text-ink')}>
                <div className="font-semibold mb-1">
                  Coherence check: {ctx.coherence_check_passed === false ? 'failed' : 'passed (per engine)'}
                </div>
                {(ctx.notes?.length ?? 0) === 0 ? (
                  <p className="text-xs text-faint"><em>No notes from the coherence engine.</em></p>
                ) : (
                  <ul className="text-xs">{ctx.notes!.map((n, i) => <li key={i}>· {n}</li>)}</ul>
                )}
              </div>
              <StubPill on={Boolean(ctx._dev_stub)} />
            </>
          )}
        </CardBody>
      </Card>
    </SectionAnchor>
  )
}

// ============ 07 · Values & motivation ============
export function ValuesSection({ row }: { row: RoleProfileRow }) {
  const v = row.definition_json.values_and_motivation as
    | { schwartz_values?: Record<string, string>; sdt_needs_supply?: Record<string, string>; _dev_stub?: boolean }
    | undefined
  return (
    <SectionAnchor id="values">
      <Card>
        <CardEyebrow><FileText size={12} /> 07 · Values & motivation</CardEyebrow>
        <CardTitle>Schwartz values + SDT needs-supply</CardTitle>
        <CardBody>
          {!v && <p className="text-faint text-sm"><em>No values/motivation recorded yet.</em></p>}
          {v && (
            <div className="grid lg:grid-cols-2 gap-4 text-sm">
              <div>
                <div className="text-xs uppercase tracking-wider font-bold text-muted mb-2">Schwartz values</div>
                <ul className="flex flex-col gap-1">
                  {Object.entries(v.schwartz_values ?? {}).filter(([k]) => !k.startsWith('_')).map(([key, val]) => (
                    <li key={key} className="flex items-center justify-between border-b border-line pb-1">
                      <span>{key}</span><Pill>{val}</Pill>
                    </li>
                  ))}
                </ul>
              </div>
              <div>
                <div className="text-xs uppercase tracking-wider font-bold text-muted mb-2">SDT needs-supply</div>
                <ul className="flex flex-col gap-1">
                  {Object.entries(v.sdt_needs_supply ?? {}).filter(([k]) => !k.startsWith('_')).map(([key, val]) => (
                    <li key={key} className="flex items-center justify-between border-b border-line pb-1">
                      <span>{key}</span><Pill>{val}</Pill>
                    </li>
                  ))}
                </ul>
              </div>
              <div className="lg:col-span-2"><StubPill on={Boolean(v._dev_stub)} /></div>
            </div>
          )}
        </CardBody>
      </Card>
    </SectionAnchor>
  )
}

// ============ 08 · Success criteria ============
export function SuccessCriteriaSection({ row }: { row: RoleProfileRow }) {
  const all = row.definition_json.success_criteria ?? []
  const horizons: { h: '90_day' | 'six_month' | 'annual'; label: string }[] = [
    { h: '90_day', label: '90 days' },
    { h: 'six_month', label: '6 months' },
    { h: 'annual', label: 'Annual' },
  ]
  return (
    <SectionAnchor id="success">
      <Card>
        <CardEyebrow><ScrollText size={12} /> 08 · Success criteria</CardEyebrow>
        <CardTitle>Multi-dimensional, time-bounded (Campbell 1990; Pulakos 2000)</CardTitle>
        <CardBody>
          {all.length === 0 && <p className="text-faint text-sm"><em>No success criteria recorded yet.</em></p>}
          {all.length > 0 && (
            <div className="grid lg:grid-cols-3 gap-3 text-sm">
              {horizons.map(({ h, label }) => {
                const items = all.filter(s => s.horizon === h)
                return (
                  <div key={h} className="border border-line rounded p-3">
                    <div className="text-xs uppercase tracking-wider font-bold text-muted mb-2">{label}</div>
                    {items.length === 0 && <p className="text-xs text-faint"><em>none</em></p>}
                    <ul className="flex flex-col gap-2">
                      {items.map((s, i) => (
                        <li key={i} className="border-l-2 border-line pl-2">
                          <div className="flex items-center gap-1 mb-0.5">
                            <Pill>{s.dimension}</Pill>
                            <StubPill on={Boolean(s._dev_stub)} />
                          </div>
                          <p className="text-sm">{s.behaviour}</p>
                        </li>
                      ))}
                    </ul>
                  </div>
                )
              })}
            </div>
          )}
          <p className="text-xs text-faint mt-3">
            Dimensions: task · contextual_ocb · adaptive · leadership · cwb_avoidance.
            Framing default: <strong>developmental</strong>.
          </p>
        </CardBody>
      </Card>
    </SectionAnchor>
  )
}

// ============ 09 · Evolution vector (FORECAST panel) ============
export function EvolutionVectorSection({ row }: { row: RoleProfileRow }) {
  const ev = row.definition_json.evolution_vector
  return (
    <SectionAnchor id="evolution">
      <div className="rounded-lg border border-internal-fg/40 bg-internal-bg/30 p-5">
        <div className="flex items-center justify-between mb-3 flex-wrap gap-2">
          <div className="flex items-center gap-2 text-internal-fg">
            <TrendingUp size={14} />
            <span className="text-xs uppercase tracking-wider font-bold">9. Evolution vector</span>
          </div>
          <span className="text-[10.5px] uppercase tracking-wider font-bold px-2 py-0.5 rounded bg-internal-bg text-internal-fg border border-internal-fg/30">
            Forecast — not a measurement
          </span>
        </div>
        <h2 className="font-display text-xl text-ink mb-2">How this role is changing</h2>
        {!ev && <p className="text-faint text-sm"><em>No evolution vector recorded yet.</em></p>}
        {ev && (
          <>
            <div className="grid lg:grid-cols-3 gap-2 text-sm mb-3">
              <Row k="Horizon" v={`${ev.horizon_months ?? '—'} months`} />
              <Row k="Confidence" v={<Pill>{ev.confidence ?? '—'}</Pill>} />
              <Row k="Next review" v={ev.next_review_date ?? '—'} />
            </div>
            {ev.narrative && <p className="text-sm text-ink mb-3">{ev.narrative}</p>}
            <div className="grid lg:grid-cols-2 gap-3 text-sm">
              <div>
                <div className="text-xs uppercase tracking-wider font-bold text-muted mb-1">Likely to rise</div>
                <ul className="flex flex-col gap-1">
                  {(ev.likely_to_rise ?? []).map((d, i) => (
                    <li key={i} className="text-green-700 flex items-center gap-2">
                      <span className="font-mono text-xs">{d.delta}</span>
                      <span>{d.attribute}</span>
                    </li>
                  ))}
                </ul>
              </div>
              <div>
                <div className="text-xs uppercase tracking-wider font-bold text-muted mb-1">Likely to fall</div>
                <ul className="flex flex-col gap-1">
                  {(ev.likely_to_fall ?? []).map((d, i) => (
                    <li key={i} className="text-rust flex items-center gap-2">
                      <span className="font-mono text-xs">{d.delta}</span>
                      <span>{d.attribute}</span>
                    </li>
                  ))}
                </ul>
              </div>
            </div>
            {(ev.sources?.length ?? 0) > 0 && (
              <p className="text-[11px] font-mono text-faint mt-3">sources: {ev.sources!.join(' · ')}</p>
            )}
            <p className="text-xs text-internal-fg/80 mt-3 border-t border-internal-fg/20 pt-2">
              Forecast confidence is <strong>{ev.confidence ?? 'unspecified'}</strong> — used only for development-conversation framing, NOT in placement scoring.
            </p>
          </>
        )}
      </div>
    </SectionAnchor>
  )
}

// ============ 10 · Team-gap context (surveillance guardrail visible) ============
export function TeamGapSection({ row }: { row: RoleProfileRow }) {
  const tg = row.definition_json.team_gap_context
  return (
    <SectionAnchor id="team_gap">
      <Card>
        <CardEyebrow><Users size={12} /> 10 · Team-gap context</CardEyebrow>
        <CardTitle>Complementary + supplementary pull traits</CardTitle>
        <CardBody>
          {/* Visible body-copy surveillance guardrail per the prompt §E. */}
          <div className="border border-role/30 bg-role/5 rounded p-3 text-sm mb-4">
            <div className="font-semibold text-ink mb-1">How team-gap is computed</div>
            <p className="text-ink/80">
              Team-gap is computed <strong>from members' OWN validated profiles</strong> only.
              Peer-rating of individuals' personality is <strong>blocked at the schema level</strong>
              (SCIENCE-SPEC §7; CLAUDE.md hard-never list).
            </p>
          </div>
          {!tg && <p className="text-faint text-sm"><em>No team-gap context recorded yet.</em></p>}
          {tg && (
            <div className="grid lg:grid-cols-2 gap-3 text-sm">
              <div>
                <div className="text-xs uppercase tracking-wider font-bold text-muted mb-1">Complementary pull (gap fillers)</div>
                <ul className="flex flex-col gap-1">
                  {(tg.complementary_pull_traits ?? []).map(t => <li key={t}><Pill>{t}</Pill></li>)}
                  {(tg.complementary_pull_traits?.length ?? 0) === 0 && <em className="text-faint">none</em>}
                </ul>
              </div>
              <div>
                <div className="text-xs uppercase tracking-wider font-bold text-muted mb-1">Supplementary pull (reinforcers)</div>
                <ul className="flex flex-col gap-1">
                  {(tg.supplementary_pull_traits ?? []).map(t => <li key={t}><Pill>{t}</Pill></li>)}
                  {(tg.supplementary_pull_traits?.length ?? 0) === 0 && <em className="text-faint">none</em>}
                </ul>
              </div>
              <div className="lg:col-span-2"><StubPill on={Boolean(tg._dev_stub)} /></div>
            </div>
          )}
        </CardBody>
      </Card>
    </SectionAnchor>
  )
}

// Small row helper
function Row({ k, v }: { k: string; v: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between border-b border-line pb-1">
      <span className="text-xs uppercase tracking-wider font-bold text-muted">{k}</span>
      <span>{v}</span>
    </div>
  )
}
