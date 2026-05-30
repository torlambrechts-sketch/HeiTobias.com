/**
 * Reference scoring implementation for the personality module.
 * Pure functions, no dependencies. Mirror in your engine (Supabase Edge / Vercel fn).
 *
 * Pipeline:  raw responses -> reverse-key -> trait mean -> percentile (vs norms)
 *            -> T-score -> role match (weighted band-deviation) -> flags.
 */

// 1) Reverse-key a single 1..5 response when the item is reverse-scored.
export function applyKey(response, reverseScore, points = 5) {
  return reverseScore ? (points + 1) - response : response;
}

// 2) Trait raw score = mean of keyed item responses (mean tolerates missing items).
export function traitMean(responses /* [{response, reverseScore}] */, points = 5) {
  const vals = responses
    .filter(r => r.response != null)
    .map(r => applyKey(r.response, r.reverseScore, points));
  if (!vals.length) return null;
  return vals.reduce((a, b) => a + b, 0) / vals.length;
}

// 3) Percentile vs a normative reference distribution for that trait.
//    norms = sorted array of trait means from the reference sample.
export function percentile(rawMean, norms) {
  if (rawMean == null || !norms || !norms.length) return null;
  let below = 0;
  for (const n of norms) if (n < rawMean) below++;
  return Math.max(0, Math.min(99, Math.round((below / norms.length) * 100)));
}

// 4) Convert percentile to a T-score (M=50, SD=10) via the normal inverse-CDF.
export function percentileToT(p) {
  if (p == null) return null;
  const z = invNormCdf(Math.min(0.999, Math.max(0.001, (p + 0.5) / 100)));
  return Math.round(50 + 10 * z);
}

// 5) Role match: weighted band-deviation. Returns 0..100 plus flags.
//    target trait entry: { trait, band:[lo,hi]|null, direction, weight, review_flag, flag_threshold }
//    candidate: { [trait]: percentile }
export function roleMatch(candidate, roleTraits, REF = 40) {
  let penalty = 0;
  const contributions = [];
  const flags = [];

  for (const t of roleTraits) {
    const x = candidate[t.trait];

    // Human-review flags (never affect the numeric score).
    if (t.review_flag && t.flag_threshold != null && x != null && x >= t.flag_threshold) {
      flags.push({ trait: t.trait, percentile: x, threshold: t.flag_threshold });
    }
    if (!t.weight || x == null || !t.band) continue;

    const [lo, hi] = t.band;
    let dist = 0;
    if (t.direction === "higher_better")      dist = x < lo ? (lo - x) : 0;
    else if (t.direction === "lower_better")  dist = x > hi ? (x - hi) : 0;
    else /* target_band */                    dist = x < lo ? (lo - x) : (x > hi ? (x - hi) : 0);

    const severity = Math.min(1, dist / REF);   // REF points outside band = full penalty
    const p = t.weight * severity;
    penalty += p;
    contributions.push({ trait: t.trait, percentile: x, band: t.band,
                         direction: t.direction, weight: t.weight,
                         severity: +severity.toFixed(3), penalty: +p.toFixed(3) });
  }

  const match = Math.max(0, Math.min(100, Math.round(100 * (1 - penalty))));
  contributions.sort((a, b) => b.penalty - a.penalty);
  return { match, flags, contributions };
}

// --- helper: rational approximation of the inverse normal CDF (Acklam) ---
function invNormCdf(p) {
  const a=[-3.969683028665376e+01,2.209460984245205e+02,-2.759285104469687e+02,1.383577518672690e+02,-3.066479806614716e+01,2.506628277459239e+00];
  const b=[-5.447609879822406e+01,1.615858368580409e+02,-1.556989798598866e+02,6.680131188771972e+01,-1.328068155288572e+01];
  const c=[-7.784894002430293e-03,-3.223964580411365e-01,-2.400758277161838e+00,-2.549732539343734e+00,4.374664141464968e+00,2.938163982698783e+00];
  const d=[7.784695709041462e-03,3.224671290700398e-01,2.445134137142996e+00,3.754408661907416e+00];
  const plow=0.02425, phigh=1-plow; let q,r;
  if (p<plow){q=Math.sqrt(-2*Math.log(p));return (((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5])/((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1);}
  if (p<=phigh){q=p-0.5;r=q*q;return (((((a[0]*r+a[1])*r+a[2])*r+a[3])*r+a[4])*r+a[5])*q/(((((b[0]*r+b[1])*r+b[2])*r+b[3])*r+b[4])*r+1);}
  q=Math.sqrt(-2*Math.log(1-p));return -(((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5])/((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1);
}

// --- validity / quality checks (run on raw response set) ---
export function infrequencyFlag(infreqResponses, threshold = 2) {
  // infreqResponses: responses to bogus low-base-rate items keyed so that
  // an "expected" answer is low. Count how many were endorsed strongly.
  const hits = infreqResponses.filter(r => r >= 4).length;
  return { hits, flagged: hits >= threshold };
}
export function inconsistencyFlag(pairs, threshold = 2) {
  // pairs: [{a, b}] of near-synonym responses (after keying). Large gaps = careless/inconsistent.
  const big = pairs.filter(p => Math.abs(p.a - p.b) >= 3).length;
  return { big, flagged: big >= threshold };
}
