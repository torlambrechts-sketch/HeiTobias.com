import { describe, it, expect } from 'vitest'
import {
  applyKey, traitMean, percentile, percentileToT, roleMatch,
  invNormCdf, infrequencyFlag, inconsistencyFlag,
} from './scoring.js'

// ─── applyKey ───────────────────────────────────────────────────────
describe('applyKey', () => {
  it('returns the response unchanged when not reverse-scored', () => {
    for (const r of [1, 2, 3, 4, 5]) expect(applyKey(r, false)).toBe(r)
  })
  it('reverses on a 1..5 scale (6 - r)', () => {
    expect(applyKey(1, true)).toBe(5)
    expect(applyKey(2, true)).toBe(4)
    expect(applyKey(3, true)).toBe(3)
    expect(applyKey(4, true)).toBe(2)
    expect(applyKey(5, true)).toBe(1)
  })
  it('respects a different `points` argument', () => {
    expect(applyKey(7, true, 7)).toBe(1)
    expect(applyKey(1, true, 7)).toBe(7)
    expect(applyKey(4, true, 7)).toBe(4)  // midpoint
  })
})

// ─── traitMean ──────────────────────────────────────────────────────
describe('traitMean', () => {
  it('averages a mix of positive-keyed items', () => {
    const r = [
      { response: 4, reverseScore: false },
      { response: 5, reverseScore: false },
      { response: 3, reverseScore: false },
    ]
    expect(traitMean(r)).toBeCloseTo(4, 10)
  })
  it('keys reverse items before averaging', () => {
    // Three reverse items at 1 should each become 5 → mean 5.
    const r = [
      { response: 1, reverseScore: true },
      { response: 1, reverseScore: true },
      { response: 1, reverseScore: true },
    ]
    expect(traitMean(r)).toBe(5)
  })
  it('mixes positive and reverse correctly', () => {
    const r = [
      { response: 5, reverseScore: false },  // → 5
      { response: 1, reverseScore: true  },  // → 5
      { response: 3, reverseScore: false },  // → 3
      { response: 3, reverseScore: true  },  // → 3 (midpoint)
    ]
    expect(traitMean(r)).toBe(4)
  })
  it('skips null (missing) responses', () => {
    const r = [
      { response: 5, reverseScore: false },
      { response: null, reverseScore: false },
      { response: 3, reverseScore: false },
    ]
    expect(traitMean(r)).toBe(4)
  })
  it('returns null when every response is null', () => {
    const r = [
      { response: null, reverseScore: false },
      { response: null, reverseScore: true },
    ]
    expect(traitMean(r)).toBeNull()
  })
  it('returns null on empty input', () => {
    expect(traitMean([])).toBeNull()
  })
})

// ─── percentile ─────────────────────────────────────────────────────
describe('percentile', () => {
  const norms = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  it('returns 0 for a value strictly below every norm', () => {
    expect(percentile(0.5, norms)).toBe(0)
  })
  it('returns 99 (clamped) for a value strictly above every norm', () => {
    expect(percentile(100, norms)).toBe(99)
  })
  it('returns ~50 for the midpoint of a uniform-discrete distribution', () => {
    // 5 of the 10 norms are < 5.5 → 50%.
    expect(percentile(5.5, norms)).toBe(50)
  })
  it('uses strict-less (not ≤) comparison (matches the reference)', () => {
    // No norms < 1 → 0
    expect(percentile(1, norms)).toBe(0)
    // 1 norm < 2 → 10
    expect(percentile(2, norms)).toBe(10)
  })
  it('returns null when rawMean is null', () => {
    expect(percentile(null, norms)).toBeNull()
  })
  it('returns null when norms are missing or empty', () => {
    expect(percentile(5, null)).toBeNull()
    expect(percentile(5, undefined)).toBeNull()
    expect(percentile(5, [])).toBeNull()
  })
  it('clamps to 0..99 even with a single-element norms array', () => {
    expect(percentile(0, [5])).toBe(0)
    expect(percentile(10, [5])).toBe(99)
  })
})

// ─── percentileToT ──────────────────────────────────────────────────
describe('percentileToT', () => {
  it('returns ~50 for the 50th percentile', () => {
    expect(percentileToT(50)).toBe(50)
  })
  it('returns ~60 (M+1SD) for the 84th percentile', () => {
    // 84th percentile ≈ z=1 → T = 60
    expect(percentileToT(84)).toBe(60)
  })
  it('returns ~40 (M-1SD) for the 16th percentile', () => {
    expect(percentileToT(16)).toBe(40)
  })
  it('returns ~70-72 (≈M+2SD) for the 98th percentile', () => {
    // The algorithm uses (p+0.5)/100 as a half-percentile continuity
    // correction → p=98 maps to z=invNormCdf(0.985) ≈ 2.17 → T ≈ 72.
    const t = percentileToT(98)!
    expect(t).toBeGreaterThanOrEqual(70)
    expect(t).toBeLessThanOrEqual(73)
  })
  it('clamps probability inputs at the edges (no NaN)', () => {
    // p=0 → (p+0.5)/100 = 0.005 → clamped to 0.005 (above 0.001 floor) → finite T
    expect(Number.isFinite(percentileToT(0)!)).toBe(true)
    expect(Number.isFinite(percentileToT(99)!)).toBe(true)
  })
  it('returns null on null input', () => {
    expect(percentileToT(null)).toBeNull()
  })
})

// ─── invNormCdf ─────────────────────────────────────────────────────
describe('invNormCdf', () => {
  it('returns ~0 for p=0.5', () => {
    expect(invNormCdf(0.5)).toBeCloseTo(0, 6)
  })
  it('returns ~1 for p≈0.8413', () => {
    expect(invNormCdf(0.8413)).toBeCloseTo(1, 3)
  })
  it('returns ~-1 for p≈0.1587', () => {
    expect(invNormCdf(0.1587)).toBeCloseTo(-1, 3)
  })
  it('handles the low-tail branch (p < 0.02425)', () => {
    const z = invNormCdf(0.01)
    expect(z).toBeLessThan(-2)  // p=0.01 → z ≈ -2.33
    expect(z).toBeGreaterThan(-3)
  })
  it('handles the high-tail branch (p > 0.97575)', () => {
    const z = invNormCdf(0.99)
    expect(z).toBeGreaterThan(2)
    expect(z).toBeLessThan(3)
  })
})

// ─── roleMatch ──────────────────────────────────────────────────────
describe('roleMatch', () => {
  const baseTrait = {
    trait: 'conscientiousness',
    band: [60, 95] as [number, number],
    direction: 'higher_better' as const,
    weight: 0.20,
  }

  it('returns match=100 when every contributor is inside its band', () => {
    const candidate = { conscientiousness: 75 }
    const r = roleMatch(candidate, [baseTrait])
    expect(r.match).toBe(100)
    expect(r.flags).toHaveLength(0)
    expect(r.contributions).toHaveLength(1)
    expect(r.contributions[0]!.severity).toBe(0)
    expect(r.contributions[0]!.penalty).toBe(0)
  })

  it('penalises a higher_better candidate below the band', () => {
    // band lo=60, REF=40 → 20 percentile below = severity 0.5, weight 0.2 → penalty 0.1
    const candidate = { conscientiousness: 40 }
    const r = roleMatch(candidate, [baseTrait])
    expect(r.contributions[0]!.severity).toBeCloseTo(0.5, 3)
    expect(r.contributions[0]!.penalty).toBeCloseTo(0.1, 3)
    expect(r.match).toBe(90)  // 100 × (1 - 0.1)
  })

  it('does not penalise higher_better when candidate is above the band', () => {
    const candidate = { conscientiousness: 99 }
    const r = roleMatch(candidate, [baseTrait])
    expect(r.contributions[0]!.severity).toBe(0)
    expect(r.match).toBe(100)
  })

  it('penalises lower_better above the band only', () => {
    const trait = { ...baseTrait, direction: 'lower_better' as const, band: [0, 30] as [number, number] }
    expect(roleMatch({ conscientiousness: 10 }, [trait]).match).toBe(100)  // inside
    // 50 above band of [0,30] = 20 over; severity 0.5; penalty 0.1; match 90
    expect(roleMatch({ conscientiousness: 50 }, [trait]).match).toBe(90)
  })

  it('penalises target_band on both sides', () => {
    const trait = { ...baseTrait, direction: 'target_band' as const, band: [40, 60] as [number, number] }
    // Inside the band → no penalty
    expect(roleMatch({ conscientiousness: 50 }, [trait]).match).toBe(100)
    // 20 below lo → penalty 0.1
    expect(roleMatch({ conscientiousness: 20 }, [trait]).match).toBe(90)
    // 20 above hi → penalty 0.1
    expect(roleMatch({ conscientiousness: 80 }, [trait]).match).toBe(90)
  })

  it('caps severity at 1 (full-penalty plateau beyond REF points outside)', () => {
    // 100 percentile below band of [60,95]: dist=60; severity = min(1, 60/40) = 1
    const candidate = { conscientiousness: 0 }
    const r = roleMatch(candidate, [baseTrait])
    expect(r.contributions[0]!.severity).toBe(1)
    expect(r.contributions[0]!.penalty).toBeCloseTo(0.2, 3)
    expect(r.match).toBe(80)  // 100 × (1 - 0.2)
  })

  it('skips contributors when the candidate has no percentile for them', () => {
    const candidate = { conscientiousness: null }
    const r = roleMatch(candidate, [baseTrait])
    expect(r.match).toBe(100)  // no penalty applied
    expect(r.contributions).toHaveLength(0)
  })

  it('skips contributors when band is null (treat as non-scoring)', () => {
    const trait = { ...baseTrait, band: null, weight: 0.2 }
    const r = roleMatch({ conscientiousness: 50 }, [trait])
    expect(r.match).toBe(100)
    expect(r.contributions).toHaveLength(0)
  })

  it('raises a human-review flag without penalising the score', () => {
    const traits = [
      baseTrait,
      {
        trait: 'psychopathy',
        band: null,
        direction: 'lower_better' as const,
        weight: 0,
        review_flag: true,
        flag_threshold: 80,
      },
    ]
    // Candidate inside conscientiousness band, psychopathy ≥ threshold
    const r = roleMatch({ conscientiousness: 75, psychopathy: 90 }, traits)
    expect(r.match).toBe(100)            // psychopathy does NOT reduce the match
    expect(r.flags).toHaveLength(1)
    expect(r.flags[0]).toEqual({ trait: 'psychopathy', percentile: 90, threshold: 80 })
  })

  it('does not raise a flag when the candidate is below the threshold', () => {
    const traits = [{
      trait: 'psychopathy', band: null, direction: 'lower_better' as const, weight: 0,
      review_flag: true, flag_threshold: 80,
    }]
    const r = roleMatch({ psychopathy: 50 }, traits)
    expect(r.flags).toHaveLength(0)
  })

  it('sorts contributions by penalty descending', () => {
    const traits = [
      { trait: 'a', band: [60, 95] as [number, number], direction: 'higher_better' as const, weight: 0.1 },
      { trait: 'b', band: [60, 95] as [number, number], direction: 'higher_better' as const, weight: 0.3 },
      { trait: 'c', band: [60, 95] as [number, number], direction: 'higher_better' as const, weight: 0.2 },
    ]
    // All candidates the same percentile, so penalty is proportional to weight.
    const r = roleMatch({ a: 20, b: 20, c: 20 }, traits)
    expect(r.contributions.map(c => c.trait)).toEqual(['b', 'c', 'a'])
  })

  it('clamps match at 0 when total penalty exceeds 1', () => {
    // Two traits at full severity, weight 0.6 each → penalty 1.2 → clamped match=0
    const traits = [
      { trait: 'a', band: [60, 95] as [number, number], direction: 'higher_better' as const, weight: 0.6 },
      { trait: 'b', band: [60, 95] as [number, number], direction: 'higher_better' as const, weight: 0.6 },
    ]
    const r = roleMatch({ a: 0, b: 0 }, traits)
    expect(r.match).toBe(0)
  })

  it('returns match=100 with empty roleTraits', () => {
    const r = roleMatch({}, [])
    expect(r.match).toBe(100)
    expect(r.contributions).toHaveLength(0)
    expect(r.flags).toHaveLength(0)
  })

  it('uses a custom REF when supplied', () => {
    // REF=20 (tighter): the same 20 below band saturates severity at 1.
    const candidate = { conscientiousness: 40 }  // band lo=60, dist=20
    const r = roleMatch(candidate, [baseTrait], 20)
    expect(r.contributions[0]!.severity).toBe(1)
    expect(r.match).toBe(80)
  })
})

// ─── infrequencyFlag ────────────────────────────────────────────────
describe('infrequencyFlag', () => {
  it('counts items with response ≥ 4 as hits', () => {
    expect(infrequencyFlag([1, 2, 3, 4, 5]).hits).toBe(2)
  })
  it('flags when hits ≥ threshold (default 2)', () => {
    expect(infrequencyFlag([5, 5]).flagged).toBe(true)
    expect(infrequencyFlag([5]).flagged).toBe(false)
  })
  it('respects a custom threshold', () => {
    expect(infrequencyFlag([5, 5, 5], 4).flagged).toBe(false)
    expect(infrequencyFlag([5, 5, 5, 5], 4).flagged).toBe(true)
  })
})

// ─── inconsistencyFlag ──────────────────────────────────────────────
describe('inconsistencyFlag', () => {
  it('counts |a-b| ≥ 3 pairs as big', () => {
    const pairs = [{ a: 5, b: 1 }, { a: 4, b: 4 }, { a: 1, b: 4 }]
    expect(inconsistencyFlag(pairs).big).toBe(2)
  })
  it('flags when big ≥ threshold', () => {
    expect(inconsistencyFlag([{ a: 5, b: 1 }, { a: 5, b: 1 }]).flagged).toBe(true)
    expect(inconsistencyFlag([{ a: 5, b: 1 }]).flagged).toBe(false)
  })
})

// ─── End-to-end pipeline check ──────────────────────────────────────
// Walk one trait through key → mean → percentile → T, on a controllable
// fixture, and verify the chain matches the spec.
describe('pipeline: keyed mean → percentile → T-score', () => {
  it('produces a coherent end-to-end score on a deterministic case', () => {
    // Five items, mix of positive and reverse, all answered.
    const responses = [
      { response: 5, reverseScore: false }, // → 5
      { response: 4, reverseScore: false }, // → 4
      { response: 3, reverseScore: false }, // → 3
      { response: 2, reverseScore: true  }, // → 4
      { response: 1, reverseScore: true  }, // → 5
    ]
    const mean = traitMean(responses)
    expect(mean).toBeCloseTo(4.2, 6)

    // A uniform 1..5 norm sample (length 5) — 4 of 5 norms are strictly < 4.2 → 80.
    const norms = [1, 2, 3, 4, 5]
    const pct = percentile(mean, norms)
    expect(pct).toBe(80)

    const t = percentileToT(pct)
    expect(t).toBeGreaterThanOrEqual(58)  // ~z=0.84 → T~58
    expect(t).toBeLessThanOrEqual(60)
  })
})
