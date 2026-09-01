// Does a generated plan ask anyone to eat less than is safe?
//
// WHY THIS EXISTS: the plan generator's system prompt already says "No extreme
// calorie floors (never below ~1200 kcal/day for adults)". That is a REQUEST.
// Nothing checked whether the model honoured it, on either side of the wire —
// the server passed the model's JSON straight through, and the client took a
// plan day's calories verbatim as the number it scored the user against.
//
// A prompt is not a constraint. Models drift, are steered by an unusual profile,
// and can be pushed by a user who WANTS a starvation target. In a nutrition app
// the person most motivated to defeat this rule is the person it protects, and
// the only reliable place to enforce it is in code that does not negotiate.
//
// This is one of two independent defences and neither is redundant:
//   - here, so an unsafe plan is never HANDED OUT;
//   - on the client, so an unsafe plan is never HONOURED — which also covers
//     plans already stored on a device and plans synced from another one,
//     neither of which passes through generation again.

/// The absolute minimum this function will hand out, matching the number the
/// system prompt states.
///
/// The CLIENT applies a stricter, sex-aware floor (1500 for men). This one is
/// deliberately the looser of the two: the profile arrives here as an opaque
/// client-supplied object, so a floor derived from a field it may omit — or
/// misreport — would be a floor that silently stops applying. An absolute
/// minimum cannot be argued out of by the shape of the input.
export const AbsoluteCalorieFloor = 1200;

/// Every calorie target a plan states, wherever it sits in the document.
///
/// Walks the whole object rather than reading the two documented positions
/// (`targets_default.calories` and `day_types.<key>.targets.calories`). A model
/// that invents a third place to put a number would otherwise slip a starvation
/// day past a check that only looked where the schema said to look — and the
/// failure mode of that miss is the one thing this file exists to prevent.
export function calorieTargetsIn(node: unknown, depth = 0): number[] {
  // Deep enough for the documented shape several times over; bounded so a
  // cyclic or adversarially nested object cannot hang the function.
  if (depth > 12 || node === null || typeof node !== "object") return [];
  const found: number[] = [];
  for (const [key, value] of Object.entries(node as Record<string, unknown>)) {
    if (key === "calories" && typeof value === "number" && Number.isFinite(value)) {
      found.push(value);
    } else if (typeof value === "object") {
      found.push(...calorieTargetsIn(value, depth + 1));
    }
  }
  return found;
}

export interface PlanSafetyVerdict {
  safe: boolean;
  /// The offending value, for the log line. Absent when the plan is safe.
  lowest?: number;
}

/// Reject a plan that states any calorie target below [floor].
///
/// A plan stating NO calorie target anywhere is safe by this rule: every field
/// a plan leaves silent falls back to the client's computed target, which is
/// already floored. Failing that case closed would reject the legitimate plan
/// that only sets an eating window or a food rule.
export function checkPlanSafety(
  plan: unknown,
  floor: number = AbsoluteCalorieFloor,
): PlanSafetyVerdict {
  const targets = calorieTargetsIn(plan);
  if (targets.length === 0) return { safe: true };
  const lowest = Math.min(...targets);
  return lowest < floor ? { safe: false, lowest } : { safe: true };
}
