import type { SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '../types/database.js'

// The team_definition_* tables + RPCs landed in CP3.1 (migrations
// 20260529095459 + 20260529095615) but were not yet regenerated into
// Database types. Until db:types runs, we cast `as never` on table
// names and rpc keys — same pattern ValidationCard.tsx uses for
// rpc_role_export_assemble. Once codegen catches up, these casts go.

export type TeamDefinitionStage =
  | 'setup' | 'rating' | 'divergence' | 'reconciliation' | 'signed_off' | 'abandoned'

export type TeamDefinitionPurpose =
  | 'initial_definition' | 'evolution_revision' | 'periodic_review'

export type TeamDefinitionEvaluatorRole =
  | 'manager' | 'team_member' | 'peer_team_lead' | 'recruiter' | 'sme_external'

export type EvaluatorInvite = {
  person_id: string
  role: TeamDefinitionEvaluatorRole
  allow_attribution_on_reveal?: boolean
}

export type RunRow = {
  id: string
  org_id: string
  role_family: string
  role_template_id: string | null
  purpose: TeamDefinitionPurpose
  owner_user_id: string
  deadline_at: string
  stage: TeamDefinitionStage
  starts_at: string
  completed_at: string | null
  target_role_version_id: string | null
  thresholds_json: Record<string, { value: number; validity_status: string; _dev_stub: boolean }>
  consensus_summary_json: Record<string, unknown>
  draft_definition_json: Record<string, unknown>
  created_at: string
  updated_at: string
}

export type EvaluatorRow = {
  id: string
  run_id: string
  user_id: string
  role: TeamDefinitionEvaluatorRole
  invited_at: string
  accepted_at: string | null
  submitted_at: string | null
  allow_attribution_on_reveal: boolean
  weight_in_aggregation: number
}

export async function fetchRun(supabase: SupabaseClient<Database>, runId: string): Promise<RunRow | null> {
  const { data, error } = await supabase
    .from('team_definition_runs' as never)
    .select('*')
    .eq('id', runId)
    .maybeSingle()
  if (error) throw error
  return (data as unknown as RunRow) ?? null
}

export async function fetchEvaluators(supabase: SupabaseClient<Database>, runId: string): Promise<EvaluatorRow[]> {
  const { data, error } = await supabase
    .from('team_definition_evaluators' as never)
    .select('*')
    .eq('run_id', runId)
  if (error) throw error
  return (data ?? []) as unknown as EvaluatorRow[]
}

export async function createRun(
  supabase: SupabaseClient<Database>,
  args: {
    p_org_id: string
    p_role_family: string
    p_role_template_id: string | null
    p_purpose: TeamDefinitionPurpose
    p_deadline_at: string
    p_evaluators: EvaluatorInvite[]
  },
): Promise<string> {
  const { data, error } = await supabase.rpc('rpc_create_role_definition_run' as never, args as never)
  if (error) throw error
  return data as unknown as string
}

export async function submitEvaluation(
  supabase: SupabaseClient<Database>,
  args: { p_run_id: string; p_rating_json: Record<string, unknown>; p_rationale_notes_json?: Record<string, unknown> },
): Promise<string> {
  const { data, error } = await supabase.rpc('rpc_submit_evaluation' as never, args as never)
  if (error) throw error
  return data as unknown as string
}

export async function sealEvaluations(supabase: SupabaseClient<Database>, runId: string): Promise<string> {
  const { data, error } = await supabase.rpc('rpc_seal_evaluations' as never, { p_run_id: runId } as never)
  if (error) throw error
  return data as unknown as string
}

// THE LOAD-BEARING owner read. Calling this pre-seal writes an audit
// row and returns 0 evaluations — that's the third lock. The UI must
// only call this when the owner CONFIRMS they intend to read post-seal,
// because the audit entry is permanent.
export async function fetchEvaluationsForOwner(
  supabase: SupabaseClient<Database>,
  runId: string,
): Promise<{ rows: unknown[]; stage: TeamDefinitionStage; attempted_read_during_seal: boolean }> {
  const { data, error } = await supabase.rpc('rpc_team_definition_evaluations_for_owner' as never, { p_run_id: runId } as never)
  if (error) throw error
  return data as unknown as { rows: unknown[]; stage: TeamDefinitionStage; attempted_read_during_seal: boolean }
}

export function formatStage(stage: TeamDefinitionStage): { num: 1 | 2 | 3 | 4; label: string } {
  switch (stage) {
    case 'setup':          return { num: 1, label: 'Setup' }
    case 'rating':         return { num: 2, label: 'Independent rating' }
    case 'divergence':     return { num: 3, label: 'Divergence' }
    case 'reconciliation': return { num: 4, label: 'Reconciliation & sign-off' }
    case 'signed_off':     return { num: 4, label: 'Signed off' }
    case 'abandoned':      return { num: 1, label: 'Abandoned' }
  }
}
