import { useCallback, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Briefcase, Calendar, Loader2, Plus, Trash2, UserPlus } from 'lucide-react'
import { browserSupabase } from '../../lib/browser-supabase.js'
import { createRun, type EvaluatorInvite, type TeamDefinitionEvaluatorRole, type TeamDefinitionPurpose } from '../../lib/teamDefinition.js'
import { Button } from '../ui/button.js'
import { Card, CardBody } from '../ui/card.js'
import { Pill } from '../ui/badges.js'

// Stage 1 — Setup. Run owner picks a role template, role family,
// purpose, and deadline; invites evaluators with their roles + their
// "allow attribution on reveal" consent flag.
//
// Notes:
//  * Even at Setup we surface the min_evaluators_for_valid_run threshold
//    as live feedback — adding fewer than 4 means seal will fail.
//  * No "allow seal without quorum" knob — that's an I/O-psych decision,
//    not an owner one.
//  * The form ONLY captures owner-side metadata. Per-criterion ratings
//    happen in Stage 2 by each evaluator independently.

const PURPOSES: { value: TeamDefinitionPurpose; label: string; description: string }[] = [
  { value: 'initial_definition', label: 'Initial definition',  description: 'A new role is being defined from a family template.' },
  { value: 'evolution_revision', label: 'Evolution revision',  description: 'Re-baselining an existing role as the team / strategy shifts.' },
  { value: 'periodic_review',    label: 'Periodic review',     description: 'Routine validity check; no major strategic change anticipated.' },
]

const EVALUATOR_ROLES: { value: TeamDefinitionEvaluatorRole; label: string }[] = [
  { value: 'manager',        label: 'Manager' },
  { value: 'team_member',    label: 'Team member' },
  { value: 'peer_team_lead', label: 'Peer team lead' },
  { value: 'recruiter',      label: 'Recruiter' },
  { value: 'sme_external',   label: 'External SME' },
]

type Person = { id: string; full_name: string; primary_email: string }

type DraftEvaluator = {
  person_id: string
  role: TeamDefinitionEvaluatorRole
  allow_attribution_on_reveal: boolean
}

const MIN_EVALUATORS_DEV_STUB = 4

export function SetupForm({ orgId }: { orgId: string }) {
  const supabase = browserSupabase()
  const navigate = useNavigate()
  const [people, setPeople]               = useState<Person[]>([])
  const [roleTemplates, setRoleTemplates] = useState<{ id: string; title: string; family: string }[]>([])
  const [templateId, setTemplateId]       = useState<string>('')
  const [family, setFamily]               = useState<string>('')
  const [purpose, setPurpose]             = useState<TeamDefinitionPurpose>('initial_definition')
  const defaultDeadline = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10)
  const [deadline, setDeadline]           = useState<string>(defaultDeadline)
  const [drafts, setDrafts]               = useState<DraftEvaluator[]>([])
  const [busy, setBusy]                   = useState(false)
  const [err, setErr]                     = useState<string | null>(null)

  useEffect(() => {
    let live = true
    void (async () => {
      const [{ data: ppl }, { data: tpls }] = await Promise.all([
        supabase.from('people').select('id, full_name, primary_email').order('full_name').limit(200),
        supabase.from('roles_catalog').select('id, title, family').eq('is_template', true).order('family'),
      ])
      if (!live) return
      setPeople((ppl ?? []) as Person[])
      setRoleTemplates((tpls ?? []) as { id: string; title: string; family: string }[])
    })()
    return () => { live = false }
  }, [supabase])

  const onPickTemplate = (id: string) => {
    setTemplateId(id)
    const tpl = roleTemplates.find(t => t.id === id)
    if (tpl) setFamily(tpl.family)
  }

  const addDraft = () => setDrafts(d => [...d, { person_id: '', role: 'team_member', allow_attribution_on_reveal: true }])
  const removeDraft = (idx: number) => setDrafts(d => d.filter((_, i) => i !== idx))
  const updateDraft = (idx: number, patch: Partial<DraftEvaluator>) =>
    setDrafts(d => d.map((row, i) => i === idx ? { ...row, ...patch } : row))

  const validInvites: EvaluatorInvite[] = drafts.filter(d => d.person_id).map(d => ({
    person_id: d.person_id, role: d.role, allow_attribution_on_reveal: d.allow_attribution_on_reveal,
  }))

  const submit = useCallback(async () => {
    if (!family.trim()) { setErr('Pick a role template or enter a role family.'); return }
    if (validInvites.length === 0) { setErr('Add at least one evaluator.'); return }
    setBusy(true); setErr(null)
    try {
      const runId = await createRun(supabase, {
        p_org_id: orgId,
        p_role_family: family,
        p_role_template_id: templateId || null,
        p_purpose: purpose,
        p_deadline_at: new Date(deadline + 'T17:00:00').toISOString(),
        p_evaluators: validInvites,
      })
      navigate(`/team-def/runs/${runId}`)
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e))
      setBusy(false)
    }
  }, [supabase, orgId, family, templateId, purpose, deadline, validInvites, navigate])

  const tooFew = validInvites.length > 0 && validInvites.length < MIN_EVALUATORS_DEV_STUB

  return (
    <Card>
      <CardBody className="flex flex-col gap-6">
        <div>
          <h2 className="font-display text-2xl font-semibold">Stage 1 — Setup</h2>
          <p className="text-muted text-sm mt-1 max-w-2xl">
            Pick the role to define and the evaluators who'll rate it independently in Stage 2.
            Aim for role-balanced representation: manager + team members + a peer team lead +
            recruiter, plus an external SME if available.{' '}
            <span className="font-mono text-xs text-faint">SCIENCE-SPEC §7; Linstone &amp; Turoff (1975)</span>
          </p>
        </div>

        {/* Role pick */}
        <div className="grid lg:grid-cols-2 gap-4">
          <label className="flex flex-col gap-1.5">
            <span className="text-[10.5px] uppercase tracking-wider font-bold text-muted">Role template (seed)</span>
            <select
              value={templateId}
              onChange={e => onPickTemplate(e.target.value)}
              className="border border-line rounded px-3 py-2 bg-surface text-sm"
            >
              <option value="">— none (start from blank shape) —</option>
              {roleTemplates.map(t => <option key={t.id} value={t.id}>{t.title}</option>)}
            </select>
            <span className="text-xs text-faint">
              Evaluators tune the template — they never start blank.
            </span>
          </label>

          <label className="flex flex-col gap-1.5">
            <span className="text-[10.5px] uppercase tracking-wider font-bold text-muted">Role family</span>
            <input
              value={family}
              onChange={e => setFamily(e.target.value)}
              placeholder="engineering · sales · customer_success …"
              className="border border-line rounded px-3 py-2 bg-surface text-sm"
            />
          </label>
        </div>

        {/* Purpose */}
        <div>
          <span className="text-[10.5px] uppercase tracking-wider font-bold text-muted mb-2 block">Purpose</span>
          <div className="grid lg:grid-cols-3 gap-3">
            {PURPOSES.map(p => (
              <button
                key={p.value}
                type="button"
                onClick={() => setPurpose(p.value)}
                className={'text-left border rounded p-3 transition-colors ' +
                  (purpose === p.value
                    ? 'border-forest bg-canvas-2'
                    : 'border-line bg-surface hover:bg-canvas')}
              >
                <div className="text-sm font-semibold">{p.label}</div>
                <div className="text-xs text-muted mt-1 leading-snug">{p.description}</div>
              </button>
            ))}
          </div>
        </div>

        {/* Deadline */}
        <label className="flex flex-col gap-1.5 max-w-xs">
          <span className="text-[10.5px] uppercase tracking-wider font-bold text-muted flex items-center gap-1.5">
            <Calendar size={12} /> Submission deadline
          </span>
          <input
            type="date"
            value={deadline}
            onChange={e => setDeadline(e.target.value)}
            className="border border-line rounded px-3 py-2 bg-surface text-sm"
          />
        </label>

        {/* Evaluators */}
        <div>
          <div className="flex items-center justify-between mb-2">
            <span className="text-[10.5px] uppercase tracking-wider font-bold text-muted">Evaluators</span>
            <Button variant="ghost" onClick={addDraft} className="border border-line text-xs">
              <Plus size={12} /> Add evaluator
            </Button>
          </div>
          {drafts.length === 0 && (
            <div className="text-xs text-faint italic border border-dashed border-line rounded p-4 text-center">
              No evaluators yet. <strong>Aim for at least {MIN_EVALUATORS_DEV_STUB}</strong> with role-balanced representation.
            </div>
          )}
          <div className="flex flex-col gap-2">
            {drafts.map((d, idx) => (
              <div key={idx} className="grid grid-cols-[1fr_auto_auto_auto] gap-2 items-center">
                <select
                  value={d.person_id}
                  onChange={e => updateDraft(idx, { person_id: e.target.value })}
                  className="border border-line rounded px-2 py-1.5 bg-surface text-sm"
                >
                  <option value="">— pick a person —</option>
                  {people.map(p => <option key={p.id} value={p.id}>{p.full_name} · {p.primary_email}</option>)}
                </select>
                <select
                  value={d.role}
                  onChange={e => updateDraft(idx, { role: e.target.value as TeamDefinitionEvaluatorRole })}
                  className="border border-line rounded px-2 py-1.5 bg-surface text-sm"
                >
                  {EVALUATOR_ROLES.map(r => <option key={r.value} value={r.value}>{r.label}</option>)}
                </select>
                <label className="flex items-center gap-1.5 text-xs text-muted whitespace-nowrap">
                  <input
                    type="checkbox"
                    checked={d.allow_attribution_on_reveal}
                    onChange={e => updateDraft(idx, { allow_attribution_on_reveal: e.target.checked })}
                  />
                  Named on reveal
                </label>
                <Button variant="ghost" onClick={() => removeDraft(idx)} className="text-rust">
                  <Trash2 size={13} />
                </Button>
              </div>
            ))}
          </div>
          {tooFew && (
            <div className="mt-2 text-xs text-rust flex items-center gap-1.5">
              <UserPlus size={12} />
              Below the <code className="font-mono">min_evaluators_for_valid_run</code> dev_stub threshold ({MIN_EVALUATORS_DEV_STUB}).
              You can still create the run, but seal will fail until you reach the threshold or the I/O-psych signs off a lower one.
            </div>
          )}
          <div className="mt-2 text-xs text-faint">
            <Pill tone="internal" className="mr-2">Stub threshold</Pill>
            <code className="font-mono">min_evaluators_for_valid_run = {MIN_EVALUATORS_DEV_STUB}</code> · tune per I/O-psych sign-off (SCIENCE-SPEC §7).
          </div>
        </div>

        {err && <div className="text-sm text-rust border border-rust/40 rounded p-3 bg-reject-bg">{err}</div>}

        <div className="flex items-center gap-3 border-t border-line pt-4">
          <Button onClick={submit} disabled={busy || validInvites.length === 0}>
            {busy ? <Loader2 size={14} className="animate-spin" /> : <Briefcase size={14} />}
            Create run &amp; open Stage 2
          </Button>
          <span className="text-xs text-faint">
            On creation, evaluators receive an invite; each sees ONLY their own rating throughout Stage 2.
          </span>
        </div>
      </CardBody>
    </Card>
  )
}
