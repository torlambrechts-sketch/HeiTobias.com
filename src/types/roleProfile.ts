// TypeScript types for the Role Profile (PHASE0-SPEC §2.7 + SCIENCE-SPEC
// §2/§3/§5 shape). Mirrors the JSONSchema in chk_role_definition_shape +
// the trait-target band rules. Every field is OPTIONAL because real role
// rows are at varying maturity levels — the page renders honest empty
// states for what's missing rather than inventing data.

export type RoleStatus = 'draft' | 'active' | 'archived'

// JSON-level version_status (the four-state model from PHASE0-SPEC §2.7).
export type VersionStatus = 'draft' | 'under_review' | 'signed_off' | 'archived'

export type ValidityStatus = 'dev_stub' | 'licensed' | 'validated'

export type TraitDirection = 'optimum' | 'minimum_threshold' | 'maximum_threshold' | 'linear'

export type Criticality = 'critical' | 'important' | 'supporting' | 'high' | 'medium' | 'low'

export type SuccessDimension = 'task' | 'contextual_ocb' | 'adaptive' | 'leadership' | 'cwb_avoidance'

export type SuccessHorizon = '90_day' | 'six_month' | 'annual'

export interface TraitTarget {
  trait: string
  direction: TraitDirection
  // Band fields — required when direction='optimum'.
  centre?: number
  lower?: number
  upper?: number
  weight?: number
  justification?: string
  evidence_refs?: string[]
  _dev_stub?: boolean
  _dev_stub_shape?: boolean
  // Legacy {min,max} shape — still accepted by the DB CHECK for backward
  // compat; backfilled to band shape with _dev_stub_shape=true.
  min?: number
  max?: number
}

export interface Competency {
  key: string
  name?: string
  weight: number
  criticality?: Criticality
  description?: string
  bars_anchors?: string[]
  derivation_method?: string
  framework_mapping?: string
  _dev_stub?: boolean
}

export interface TaskLayerItem {
  task: string
  criticality?: Criticality
  frequency?: string
  outcomes?: string
  tools?: string
  _dev_stub?: boolean
}

export interface SuccessCriterion {
  horizon: SuccessHorizon
  dimension: SuccessDimension
  behaviour: string
  _dev_stub?: boolean
}

export interface EvolutionVectorDelta {
  attribute: string
  delta: string
  _dev_stub?: boolean
}

export interface EvolutionVector {
  _label: 'forecast'
  _dev_stub?: boolean
  horizon_months?: number
  confidence?: 'low' | 'medium' | 'high'
  next_review_date?: string
  narrative?: string
  likely_to_rise?: EvolutionVectorDelta[]
  likely_to_fall?: EvolutionVectorDelta[]
  sources?: string[]
}

export interface ContextFactors {
  autonomy?: number
  ambiguity_tolerance_required?: number
  pace_and_urgency?: number
  collaboration_intensity?: number
  stakeholder_load?: number
  cognitive_complexity?: number
  adversity_exposure?: number
  psychological_safety_dependence?: number
  feedback_frequency?: number
  coherence_check_passed?: boolean
  notes?: string[]
  _dev_stub?: boolean
}

export interface CognitiveDemand {
  complexity_level?: number
  complexity_level_justification?: string
  target_band?: { lower?: number; upper?: number; _dev_stub?: boolean }
  use_as?: 'threshold' | 'banded' | 'continuous'
  validity_estimate_range?: { low?: number; high?: number; caveat?: string; _dev_stub?: boolean }
  _dev_stub?: boolean
}

export interface TeamGapContext {
  _dev_stub?: boolean
  _peer_rating_blocked_at_schema?: boolean
  note?: string
  complementary_pull_traits?: string[]
  supplementary_pull_traits?: string[]
}

export interface ValidationMetadata {
  _dev_stub?: boolean
  validation_method?: string
  sme_delphi_record_ref?: string | null
  inter_rater_agreement?: number | null
  adverse_impact_log_ref?: string | null
  differential_prediction_log_ref?: string | null
  last_review_date?: string | null
  next_review_date?: string | null
  ai_act_annex_iv_ref?: string | null
  dpia_ref?: string | null
  framing_default?: 'developmental' | 'evaluative'
}

export interface IdentityAndGovernance {
  version_status?: VersionStatus
  signed_off_by?: { person_id?: string; at?: string; _dev_stub?: boolean }[]
  signed_off_at?: string
  validation_status?: ValidityStatus
  effective_from?: string
  effective_to?: string | null
  validation_evidence_refs?: string[]
  external_codes?: { onet_soc?: string; esco?: string }
  _dev_stub?: boolean
}

export interface RoleDefinitionJson {
  identity_and_governance?: IdentityAndGovernance
  task_layer?: TaskLayerItem[]
  competencies?: Competency[]
  trait_targets?: TraitTarget[]
  cognitive_demand?: CognitiveDemand
  context_factors?: ContextFactors
  values_and_motivation?: Record<string, unknown>
  success_criteria?: SuccessCriterion[]
  evolution_vector?: EvolutionVector
  team_gap_context?: TeamGapContext
  validation_and_defensibility_metadata?: ValidationMetadata
  _dev_stub?: boolean
}

export interface RoleProfileRow {
  id: string
  org_id: string | null
  title: string
  family: string | null
  is_template: boolean
  template_source_id: string | null
  version: number
  supersedes_id: string | null
  status: RoleStatus
  definition_json: RoleDefinitionJson
  authored_by_json: unknown[] | null
  signed_off_by: string | null
  signed_off_at: string | null
  created_at: string
  updated_at: string
}

// Derived utility: which page sections are stubbed?
export function isStubbed(row: RoleProfileRow): { anyStubbed: boolean; perSection: Record<string, boolean> } {
  const d = row.definition_json ?? {}
  const perSection = {
    identity:     Boolean(d.identity_and_governance?._dev_stub),
    tasks:        Boolean(d.task_layer?.some(t => t._dev_stub)),
    competencies: Boolean(d.competencies?.some(c => c._dev_stub)),
    trait_targets:Boolean(d.trait_targets?.some(t => t._dev_stub || t._dev_stub_shape)),
    cognitive:    Boolean(d.cognitive_demand?._dev_stub),
    context:      Boolean(d.context_factors?._dev_stub),
    values:       Boolean((d.values_and_motivation as { _dev_stub?: boolean } | undefined)?._dev_stub),
    success:      Boolean(d.success_criteria?.some(s => s._dev_stub)),
    evolution:    Boolean(d.evolution_vector?._dev_stub),
    team_gap:     Boolean(d.team_gap_context?._dev_stub),
    validation:   Boolean(d.validation_and_defensibility_metadata?._dev_stub),
  }
  return {
    anyStubbed: Boolean(d._dev_stub) || Object.values(perSection).some(Boolean),
    perSection,
  }
}

// Critical-set weight sum check (Step 3 deliverable surfaces this as a
// red badge when violated). Returns null if there are no competencies.
export function criticalWeightSum(row: RoleProfileRow): { sum: number; satisfied: boolean } | null {
  const comps = row.definition_json.competencies
  if (!comps || comps.length === 0) return null
  const criticalSet = comps.filter(c => c.criticality === 'critical')
  if (criticalSet.length === 0) return null
  const sum = criticalSet.reduce((acc, c) => acc + (c.weight ?? 0), 0)
  return { sum, satisfied: Math.abs(sum - 1.0) <= 0.005 }
}
