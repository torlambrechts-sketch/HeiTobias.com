import { describe, it, expect } from 'vitest'
import { decideTraitRangeRender, bandToPercent, directionPillLabel } from './traitRangeGeometry.js'
import type { TraitTarget } from '../types/roleProfile.js'

describe('decideTraitRangeRender', () => {
  it('renders optimum_band when centre+lower+upper are present', () => {
    const r = decideTraitRangeRender({ trait: 'c', direction: 'optimum', centre: 0.7, lower: 0.55, upper: 0.85 })
    expect(r.kind).toBe('optimum_band')
    if (r.kind === 'optimum_band') {
      expect(r.centre).toBe(0.7)
      expect(r.lower).toBe(0.55)
      expect(r.upper).toBe(0.85)
    }
  })

  it('refuses bare-maximum optimum (no band) with an error state', () => {
    const r = decideTraitRangeRender({ trait: 'openness', direction: 'optimum', centre: 0.5 })
    expect(r.kind).toBe('error')
    if (r.kind === 'error') {
      expect(r.reason).toMatch(/bare-maximum optimum target/)
    }
  })

  it('refuses zero-width band (lower >= upper)', () => {
    const r = decideTraitRangeRender({ trait: 'x', direction: 'optimum', centre: 0.5, lower: 0.6, upper: 0.5 })
    expect(r.kind).toBe('error')
  })

  it('renders minimum_threshold when lower is present', () => {
    const r = decideTraitRangeRender({ trait: 'a', direction: 'minimum_threshold', lower: 0.5, centre: 0.6 })
    expect(r.kind).toBe('minimum_threshold')
  })

  it('errors on minimum_threshold without lower', () => {
    const r = decideTraitRangeRender({ trait: 'a', direction: 'minimum_threshold' })
    expect(r.kind).toBe('error')
  })

  it('renders maximum_threshold when upper is present', () => {
    const r = decideTraitRangeRender({ trait: 'a', direction: 'maximum_threshold', upper: 0.8 })
    expect(r.kind).toBe('maximum_threshold')
  })

  it('renders linear with no band requirements', () => {
    const r = decideTraitRangeRender({ trait: 'e', direction: 'linear' })
    expect(r.kind).toBe('linear')
  })

  it('back-compat: legacy {trait,min,max} renders as optimum band', () => {
    const r = decideTraitRangeRender({ trait: 'old', min: 0.4, max: 0.8 } as TraitTarget)
    expect(r.kind).toBe('optimum_band')
    if (r.kind === 'optimum_band') {
      expect(r.lower).toBeCloseTo(0.4, 6)
      expect(r.upper).toBeCloseTo(0.8, 6)
      expect(r.centre).toBeCloseTo(0.6, 6)
    }
  })

  it('rejects an unknown direction with an error', () => {
    const r = decideTraitRangeRender({ trait: 'x', direction: 'nonsense' as unknown as TraitTarget['direction'] })
    expect(r.kind).toBe('error')
  })
})

describe('bandToPercent', () => {
  it('clamps 0.55..0.85 to ~55..85% band', () => {
    const r = bandToPercent({ lower: 0.55, upper: 0.85 })
    expect(r.leftPct).toBeCloseTo(55, 4)
    expect(r.widthPct).toBeCloseTo(30, 4)
  })

  it('clamps out-of-range values into 0..100', () => {
    const r = bandToPercent({ lower: -0.5, upper: 1.5 })
    expect(r.leftPct).toBe(0)
    expect(r.widthPct).toBe(100)
  })

  it('zero-width band returns widthPct 0', () => {
    const r = bandToPercent({ lower: 0.5, upper: 0.5 })
    expect(r.widthPct).toBe(0)
  })
})

describe('directionPillLabel', () => {
  it('returns role-blue tone for optimum', () => {
    expect(directionPillLabel('optimum')).toEqual({ label: 'optimum band', tone: 'role' })
  })
  it('returns amber tone for thresholds', () => {
    expect(directionPillLabel('minimum_threshold').tone).toBe('amber')
    expect(directionPillLabel('maximum_threshold').tone).toBe('amber')
  })
  it('returns muted for linear', () => {
    expect(directionPillLabel('linear').tone).toBe('muted')
  })
})

// Compile-time check: the component must never accept a person score.
// If someone tries to add a person_score field to TraitTarget, this
// breaks. (See traitRangeGeometry.ts header comment.)
describe('TraitTarget contract', () => {
  it('TraitTarget has no person_score field (compile-time)', () => {
    // @ts-expect-error person_score must not exist on TraitTarget
    const _t: TraitTarget = { trait: 'x', direction: 'linear', person_score: 0.5 }
    expect(_t).toBeDefined()
  })
})
