/**
 * H-1c cross-engine fixture test (TS side).
 *
 * Asserts that the TypeScript implementation `computeTraitBandFitV1`
 * matches the ground-truth fixture generated from the PG function
 * `public.compute_trait_band_fit_v1`. The fixture is the contract
 * between the two engines.
 *
 * If this test fails, EITHER:
 *   - the TS implementation drifted (most common)
 *   - the PG function was changed without regenerating the fixture
 *   - a new direction was added in PG without mirroring in TS
 *
 * The PG-side equivalent assertion lives in
 * supabase/tests/h1c_band_fit_cross_engine.sql.
 */

import { describe, expect, test } from 'vitest'
import fixture from '../__fixtures__/bandFitV1.json'
import { computeTraitBandFitV1, type BandFitV1Inputs } from '../scoring'

interface FixtureCase {
  id: number
  inputs: BandFitV1Inputs
  expected: number
}

const TOLERANCE = (fixture._meta?.expected_tolerance as number | undefined) ?? 1e-9

describe('H-1c — computeTraitBandFitV1 (TS engine ↔ PG fixture)', () => {
  const cases = fixture.cases as FixtureCase[]

  test('fixture is non-empty', () => {
    expect(cases.length).toBeGreaterThan(20)
  })

  for (const c of cases) {
    test(`case ${c.id} (${c.inputs.direction}, score=${c.inputs.score}) → ${c.expected}`, () => {
      const got = computeTraitBandFitV1(c.inputs)
      expect(got).not.toBeNull()
      // Allow tiny floating-point drift from PG numeric rounding
      expect(Math.abs((got as number) - c.expected)).toBeLessThanOrEqual(TOLERANCE)
    })
  }

  test('null score returns null', () => {
    expect(
      computeTraitBandFitV1({ score: null, direction: 'higher_better', bandLow: 50, bandHigh: null })
    ).toBeNull()
  })

  test('out-of-range score throws', () => {
    expect(() =>
      computeTraitBandFitV1({ score: -1, direction: 'higher_better', bandLow: 50, bandHigh: null })
    ).toThrow(/out of/)
    expect(() =>
      computeTraitBandFitV1({ score: 100, direction: 'higher_better', bandLow: 50, bandHigh: null })
    ).toThrow(/out of/)
  })

  test('inverted_u without inflectionPoint throws', () => {
    expect(() =>
      computeTraitBandFitV1({ score: 50, direction: 'inverted_u', bandLow: null, bandHigh: null })
    ).toThrow(/inflectionPoint/)
  })

  test('target_band without bandLow/bandHigh throws', () => {
    expect(() =>
      computeTraitBandFitV1({ score: 50, direction: 'target_band', bandLow: null, bandHigh: null })
    ).toThrow(/bandLow/)
  })
})
