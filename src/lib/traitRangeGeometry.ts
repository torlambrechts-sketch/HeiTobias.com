import type { TraitTarget, TraitDirection } from '../types/roleProfile.js'

// Pure decision logic for TraitRangeControl. Kept separate so vitest
// (node env) can unit-test the rules without needing a DOM.

export type TraitRangeRenderable =
  | { kind: 'optimum_band'; centre: number; lower: number; upper: number; direction: TraitDirection }
  | { kind: 'minimum_threshold'; centre: number; lower: number; direction: TraitDirection }
  | { kind: 'maximum_threshold'; centre: number; upper: number; direction: TraitDirection }
  | { kind: 'linear'; direction: TraitDirection }
  | { kind: 'error'; reason: string; offendingTarget: TraitTarget }

export function decideTraitRangeRender(t: TraitTarget): TraitRangeRenderable {
  // The DB CHECK + trigger should keep us out of these branches, but the
  // UI is the second line of defence per CLAUDE.md §5. Any violation
  // surfaces as an error state with a clear reason.

  // Legacy {trait,min,max} shape: treat as optimum band with auto-converted band.
  if (!t.direction && typeof t.min === 'number' && typeof t.max === 'number') {
    const lower = t.min, upper = t.max
    const centre = (lower + upper) / 2
    return { kind: 'optimum_band', centre, lower, upper, direction: 'optimum' }
  }

  if (t.direction === 'optimum') {
    const haveBand = typeof t.centre === 'number' && typeof t.lower === 'number' && typeof t.upper === 'number'
    if (!haveBand) {
      return {
        kind: 'error',
        reason: 'Schema violation — bare-maximum optimum target. direction=optimum requires centre + lower + upper. Contact the Role Library admin.',
        offendingTarget: t,
      }
    }
    if (t.lower! >= t.upper!) {
      return {
        kind: 'error',
        reason: `Schema violation — band has no width (lower=${t.lower}, upper=${t.upper}).`,
        offendingTarget: t,
      }
    }
    return { kind: 'optimum_band', centre: t.centre!, lower: t.lower!, upper: t.upper!, direction: 'optimum' }
  }

  if (t.direction === 'minimum_threshold') {
    if (typeof t.lower !== 'number') {
      return {
        kind: 'error',
        reason: 'Schema violation — minimum_threshold requires lower.',
        offendingTarget: t,
      }
    }
    return { kind: 'minimum_threshold', centre: typeof t.centre === 'number' ? t.centre : t.lower, lower: t.lower, direction: 'minimum_threshold' }
  }

  if (t.direction === 'maximum_threshold') {
    if (typeof t.upper !== 'number') {
      return {
        kind: 'error',
        reason: 'Schema violation — maximum_threshold requires upper.',
        offendingTarget: t,
      }
    }
    return { kind: 'maximum_threshold', centre: typeof t.centre === 'number' ? t.centre : t.upper, upper: t.upper, direction: 'maximum_threshold' }
  }

  if (t.direction === 'linear') {
    return { kind: 'linear', direction: 'linear' }
  }

  return { kind: 'error', reason: `Unknown direction "${String(t.direction)}"`, offendingTarget: t }
}

// Returns a CSS-percentage band {leftPct, widthPct} for the optimum band.
// All values are clamped 0..100 even if the seed is out of range; that
// itself is data-quality not UI-quality.
export function bandToPercent(
  band: { lower: number; upper: number },
): { leftPct: number; widthPct: number } {
  const clamp01 = (v: number) => Math.max(0, Math.min(1, v))
  const lower = clamp01(band.lower)
  const upper = clamp01(band.upper)
  return { leftPct: lower * 100, widthPct: Math.max(0, (upper - lower) * 100) }
}

// "Direction pill" label + tone per DESIGN.md.
export function directionPillLabel(direction: TraitDirection): { label: string; tone: 'role' | 'amber' | 'muted' } {
  switch (direction) {
    case 'optimum':           return { label: 'optimum band', tone: 'role' }
    case 'minimum_threshold': return { label: 'minimum threshold', tone: 'amber' }
    case 'maximum_threshold': return { label: 'maximum threshold', tone: 'amber' }
    case 'linear':            return { label: 'linear', tone: 'muted' }
  }
}
