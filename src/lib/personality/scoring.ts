/**
 * Personality Module — scoring engine.
 *
 * Pure functions, no dependencies. TypeScript port of the reference
 * implementation `scoring_reference.js`. The server-side RPC (Step 4)
 * mirrors this logic in PL/pgSQL so the two engines stay congruent —
 * see supabase/tests/personality_step4_cross_engine.sql.
 *
 * Pipeline:
 *   raw responses → reverse-key → trait mean → percentile (vs norms)
 *                 → T-score → role match (weighted band-deviation) → flags
 *
 * Provenance discipline (CLAUDE.md §5):
 *   * This file produces NUMBERS from a real algorithm. The numbers it
 *     produces are only as good as the inputs:
 *       - real IPIP responses → real trait means (always)
 *       - dev_stub norms      → dev_stub percentiles + T-scores
 *       - dev_stub role bands → dev_stub match scores
 *     The caller is responsible for propagating the right
 *     validity_status + _dev_stub flag onto the rows it writes.
 *   * Dark Triad / sensitive traits with `review_flag=true` produce
 *     HUMAN-REVIEW FLAGS that never affect the numeric match score.
 *     This is "fit informs, never decides" — enforced here as well as
 *     in the DB CHECK constraint on role_template_traits.
 */

// ─── Types ──────────────────────────────────────────────────────────

export type Direction = 'higher_better' | 'lower_better' | 'target_band' | 'inverted_u'

export interface KeyedResponse {
  /** 1..points Likert response. null = unanswered / missing. */
  response: number | null
  /** True if the item is reverse-scored (substitute response := (points+1) - response). */
  reverseScore: boolean
}

export interface RoleTrait {
  trait: string
  /** [lo, hi] percentile band, both in 0..99. Required when `weight > 0`. */
  band: [number, number] | null
  direction: Direction
  /** Weight contribution to the role match (0..1). 0 for human-review-only traits. */
  weight: number
  /** If true, trait is a human-review flag only and never contributes to the numeric score. */
  review_flag?: boolean
  /** Percentile at-or-above which a flag is raised (1..99). Required when review_flag=true. */
  flag_threshold?: number | null
}

export interface RoleMatchFlag {
  trait: string
  percentile: number
  threshold: number
}

export interface RoleMatchContribution {
  trait: string
  percentile: number
  band: [number, number]
  direction: Direction
  weight: number
  /** dist / REF, capped at 1. */
  severity: number
  /** weight × severity. */
  penalty: number
}

export interface RoleMatchResult {
  /** Integer 0..100. 100 = every contributing trait inside its band. */
  match: number
  /** Human-review flags. NEVER influence `match`. */
  flags: RoleMatchFlag[]
  /** Penalty-sorted breakdown for explainability. */
  contributions: RoleMatchContribution[]
}

export interface InfrequencyResult {
  hits: number
  flagged: boolean
}

export interface InconsistencyResult {
  big: number
  flagged: boolean
}

// ─── 1. Reverse-key a single response ───────────────────────────────
/**
 * Reverse-key a 1..points Likert response when the item is reverse-scored.
 * (response, reverseScore=true, points=5) → 6 - response.
 * Pure; returns the input unchanged when reverseScore is false.
 */
export function applyKey(response: number, reverseScore: boolean, points = 5): number {
  return reverseScore ? (points + 1) - response : response
}

// ─── 2. Trait mean across keyed responses ───────────────────────────
/**
 * Mean of keyed responses for one trait. Tolerates missing items
 * (null response) — they are skipped, not zero-imputed.
 * Returns null when no usable responses are present.
 */
export function traitMean(responses: KeyedResponse[], points = 5): number | null {
  let sum = 0
  let n = 0
  for (const r of responses) {
    if (r.response == null) continue
    sum += applyKey(r.response, r.reverseScore, points)
    n++
  }
  return n === 0 ? null : sum / n
}

// ─── 3. Percentile vs a normative reference distribution ────────────
/**
 * Percentile rank of `rawMean` against a sorted-ascending reference
 * distribution `norms` (an array of trait means from the reference
 * sample). Returns an integer in 0..99, clamped at the edges.
 *
 * The reference algorithm uses strict-less comparison (< rather than ≤)
 * to match conventional percentile-rank semantics. Mirror that in PL/pgSQL.
 */
export function percentile(rawMean: number | null, norms: number[] | null | undefined): number | null {
  if (rawMean == null || !norms || norms.length === 0) return null
  let below = 0
  for (const n of norms) if (n < rawMean) below++
  const pct = Math.round((below / norms.length) * 100)
  return Math.max(0, Math.min(99, pct))
}

// ─── 4. Percentile → T-score (M=50, SD=10) via normal inverse-CDF ───
/**
 * Convert an integer percentile 0..99 to a T-score (M=50, SD=10).
 * Clamps probability inputs to [0.001, 0.999] before applying the
 * normal inverse-CDF (which diverges at the open interval ends).
 */
export function percentileToT(p: number | null): number | null {
  if (p == null) return null
  const prob = Math.min(0.999, Math.max(0.001, (p + 0.5) / 100))
  const z = invNormCdf(prob)
  return Math.round(50 + 10 * z)
}

// ─── 5. Role match: weighted band-deviation + flags ─────────────────
/**
 * Compute a role-match score against a target trait profile.
 *
 * @param candidate  { [trait]: percentile } — the candidate's percentile per trait.
 * @param roleTraits target profile entries.
 * @param REF        percentile distance outside the band that earns full per-trait penalty (default 40).
 *
 * Returns { match: 0..100, flags, contributions }. `flags` are human-
 * review flags — NEVER subtracted from `match`.
 */
export function roleMatch(
  candidate: Record<string, number | null | undefined>,
  roleTraits: RoleTrait[],
  REF = 40,
): RoleMatchResult {
  let penalty = 0
  const contributions: RoleMatchContribution[] = []
  const flags: RoleMatchFlag[] = []

  for (const t of roleTraits) {
    const x = candidate[t.trait]

    // Flag check runs independently of the score path. A trait can be
    // a flag (review_flag=true, weight=0) OR a contributor (weight>0,
    // band present) — the schema CHECK forbids both. The flag check
    // here is intentionally permissive so a misconfigured contributor
    // with a non-null flag_threshold would still raise its flag.
    if (t.review_flag && t.flag_threshold != null && x != null && x >= t.flag_threshold) {
      flags.push({ trait: t.trait, percentile: x, threshold: t.flag_threshold })
    }
    // Skip the score path when the trait isn't a numeric contributor.
    if (!t.weight || x == null || !t.band) continue

    const [lo, hi] = t.band
    let dist = 0
    if (t.direction === 'higher_better')      dist = x < lo ? (lo - x) : 0
    else if (t.direction === 'lower_better')  dist = x > hi ? (x - hi) : 0
    else /* target_band */                    dist = x < lo ? (lo - x) : (x > hi ? (x - hi) : 0)

    const severity = Math.min(1, dist / REF)  // REF points outside the band = full per-trait penalty
    const p = t.weight * severity
    penalty += p
    contributions.push({
      trait: t.trait,
      percentile: x,
      band: t.band,
      direction: t.direction,
      weight: t.weight,
      severity: round3(severity),
      penalty: round3(p),
    })
  }

  const match = Math.max(0, Math.min(100, Math.round(100 * (1 - penalty))))
  contributions.sort((a, b) => b.penalty - a.penalty)
  return { match, flags, contributions }
}

function round3(x: number): number {
  return Math.round(x * 1000) / 1000
}

// ─── invNormCdf — Acklam's rational approximation ───────────────────
/**
 * Rational approximation to the inverse normal CDF (Acklam, 2003).
 * Accurate to ~1.15e-9 across the central region. Defined on (0,1);
 * callers must clamp at the open ends.
 */
export function invNormCdf(p: number): number {
  // prettier-ignore
  const a = [-3.969683028665376e+01,  2.209460984245205e+02, -2.759285104469687e+02,
              1.383577518672690e+02, -3.066479806614716e+01,  2.506628277459239e+00]
  // prettier-ignore
  const b = [-5.447609879822406e+01,  1.615858368580409e+02, -1.556989798598866e+02,
              6.680131188771972e+01, -1.328068155288572e+01]
  // prettier-ignore
  const c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
             -2.549732539343734e+00,  4.374664141464968e+00,  2.938163982698783e+00]
  // prettier-ignore
  const d = [ 7.784695709041462e-03,  3.224671290700398e-01,  2.445134137142996e+00,
              3.754408661907416e+00]
  const plow = 0.02425
  const phigh = 1 - plow
  let q: number, r: number
  if (p < plow) {
    q = Math.sqrt(-2 * Math.log(p))
    return (((((c[0]!*q + c[1]!)*q + c[2]!)*q + c[3]!)*q + c[4]!)*q + c[5]!) /
           ((((d[0]!*q + d[1]!)*q + d[2]!)*q + d[3]!)*q + 1)
  }
  if (p <= phigh) {
    q = p - 0.5
    r = q * q
    return (((((a[0]!*r + a[1]!)*r + a[2]!)*r + a[3]!)*r + a[4]!)*r + a[5]!) * q /
           (((((b[0]!*r + b[1]!)*r + b[2]!)*r + b[3]!)*r + b[4]!)*r + 1)
  }
  q = Math.sqrt(-2 * Math.log(1 - p))
  return -(((((c[0]!*q + c[1]!)*q + c[2]!)*q + c[3]!)*q + c[4]!)*q + c[5]!) /
          ((((d[0]!*q + d[1]!)*q + d[2]!)*q + d[3]!)*q + 1)
}

// ─── Validity / quality checks ──────────────────────────────────────
/**
 * Infrequency flag — counts strong-endorsements (≥4 on 1..5) on bogus
 * low-base-rate items. A respondent who endorses several "I sometimes
 * eat at restaurants" / "I have visited every planet" -type items is
 * likely careless or random.
 */
export function infrequencyFlag(infreqResponses: number[], threshold = 2): InfrequencyResult {
  const hits = infreqResponses.filter(r => r >= 4).length
  return { hits, flagged: hits >= threshold }
}

/**
 * Inconsistency flag — counts large gaps (|a-b| ≥ 3) on near-synonym
 * item pairs after keying. A respondent who says "I am organised" and
 * "I keep things tidy" with 5 and 1 is likely inattentive.
 */
export function inconsistencyFlag(pairs: { a: number; b: number }[], threshold = 2): InconsistencyResult {
  const big = pairs.filter(p => Math.abs(p.a - p.b) >= 3).length
  return { big, flagged: big >= threshold }
}

// ─── H-1c: Generic Curvilinear Trait-Band Fit (mirror of PG) ─────────
//
// Mirrors public.compute_trait_band_fit_v1(score, direction, band_low,
// band_high, inflection_point, half_width) in PL/pgSQL.
//
// CONTRACT: identical output to the PG function for every input.
// The cross-engine fixture in `src/lib/personality/__fixtures__/bandFitV1.json`
// is generated from the PG function and tested by BOTH engines.
//
// score 0..99 (or null → null out). Severity 0..1; 0 = perfect fit,
// 1 = worst. The roleMatchScore function further above uses its own
// (older, linear) math; this V1 helper is the canonical reference for
// new code and for any consumer that needs inverted-U support.

export interface BandFitV1Inputs {
  score: number | null
  direction: Direction
  bandLow: number | null
  bandHigh: number | null
  inflectionPoint?: number | null
  halfWidth?: number | null
}

export function computeTraitBandFitV1(inputs: BandFitV1Inputs): number | null {
  const { score: x, direction, bandLow, bandHigh, inflectionPoint, halfWidth } = inputs
  if (x === null || x === undefined) return null
  if (x < 0 || x > 99) {
    throw new Error(`score ${x} out of [0,99]`)
  }
  if (direction === 'higher_better') {
    if (bandLow === null || bandLow === undefined) throw new Error('higher_better requires bandLow')
    const dist = Math.max(0, bandLow - x)
    return Math.min(1, dist / 99)
  }
  if (direction === 'lower_better') {
    if (bandHigh === null || bandHigh === undefined) throw new Error('lower_better requires bandHigh')
    const dist = Math.max(0, x - bandHigh)
    return Math.min(1, dist / 99)
  }
  if (direction === 'target_band') {
    if (bandLow === null || bandHigh === null || bandLow === undefined || bandHigh === undefined) {
      throw new Error('target_band requires bandLow and bandHigh')
    }
    if (x >= bandLow && x <= bandHigh) return 0
    const dist = x < bandLow ? (bandLow - x) : (x - bandHigh)
    return Math.min(1, dist / 99)
  }
  if (direction === 'inverted_u') {
    if (inflectionPoint === null || inflectionPoint === undefined || halfWidth === null || halfWidth === undefined) {
      throw new Error('inverted_u requires inflectionPoint and halfWidth')
    }
    const dist = Math.abs(x - inflectionPoint)
    return Math.min(1, dist / halfWidth)
  }
  throw new Error(`unknown direction: ${String(direction)}`)
}
