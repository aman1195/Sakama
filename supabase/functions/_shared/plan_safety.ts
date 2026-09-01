// Does a generated plan ask anyone to eat less than is safe?
//
// WHY THIS EXISTS: the plan generator's system prompt already says "No extreme
// calorie floors (never below ~1200 kcal/day for adults)". That is a REQUEST.
// Nothing checked whether the model honoured it, on either side of the wire —
// the server passed the model's JSON straight through, and the client took a
// plan day's calories verbatim as the number it scored the user against.
//
// A prompt is not a constraint. Models drift, are steered by an unusual
// profile, and can be pushed by a user who WANTS a starvation target. In a
// nutrition app the person most motivated to defeat this rule is the person it
// protects, and the only reliable place to enforce it is code that does not
// negotiate.
//
// This is one of two independent defences and neither is redundant:
//   - here, so an unsafe plan is never HANDED OUT;
//   - on the client, so an unsafe plan is never HONOURED — which also covers
//     plans already stored on a device and plans synced from another one,
//     neither of which passes through generation again.

/// The absolute minimum this function will hand out, matching the number the
/// system prompt states.
///
/// The CLIENT applies a stricter, sex-aware floor (1500 for men). Keeping this
/// one looser is a deliberate split, not an oversight, and the reason is NOT
/// that the profile is opaque — `sex` is in the projection the client sends.
/// It is that the profile is CLIENT-SUPPLIED: a floor keyed on a field the
/// caller controls is a floor the caller can lower by changing one string. An
/// absolute minimum cannot be argued down by the shape of the input. The
/// stricter rule belongs where the profile is trusted, which is on the device.
export const AbsoluteCalorieFloor = 1200;

/// Read a number the way the CLIENT reads it (`_asInt` in plan.dart), including
/// a numeric string.
///
/// Requiring a real JSON number here would have let `"calories": "600"` through
/// as "states no target", while the client parsed the same document as 600 kcal
/// — the server believing a plan is silent about something the client reads a
/// starvation number from.
function asNumber(v: unknown): number | null {
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  if (typeof v === "string") {
    const n = Number(v.trim());
    return v.trim() !== "" && Number.isFinite(n) ? n : null;
  }
  return null;
}

function calorieAt(node: unknown): number | null {
  if (node === null || typeof node !== "object") return null;
  return asNumber((node as Record<string, unknown>).calories);
}

/// Every calorie target this plan will actually impose on a user.
///
/// MIRRORS THE CLIENT PARSER, deliberately, and reads only the two positions it
/// reads: `targets_default.calories` and `day_types.<key>.targets.calories`
/// (plan.dart:169, :327, :348).
///
/// The first version of this walked the entire document on the theory that a
/// model might hide a number somewhere unexpected. That had the threat model
/// backwards. The hazard is not a small number existing in the JSON, it is a
/// small number becoming the target the user is scored against — and a field
/// the client never reads can never do that. Walking everything instead
/// rejected safe plans: a `sample_meals` entry of `{name: "idli", calories:
/// 350}` or a rule effect of `{calories: -200}` failed the check, and the plan
/// engine's parsing is documented as TOLERANT precisely so plans can carry
/// richer structure than this client understands (plan.dart:5-11). Each false
/// positive costs the user one of two daily generations, unrefunded.
///
/// `day_types` is only read when it is a Map, because the client only reads it
/// when it is a Map. A list there is ignored by both.
export function calorieTargetsIn(plan: unknown): number[] {
  if (plan === null || typeof plan !== "object") return [];
  const doc = plan as Record<string, unknown>;
  const found: number[] = [];

  const fromDefault = calorieAt(doc.targets_default);
  if (fromDefault !== null) found.push(fromDefault);

  const dayTypes = doc.day_types;
  if (dayTypes !== null && typeof dayTypes === "object" && !Array.isArray(dayTypes)) {
    for (const dayType of Object.values(dayTypes as Record<string, unknown>)) {
      if (dayType === null || typeof dayType !== "object") continue;
      const fromDay = calorieAt((dayType as Record<string, unknown>).targets);
      if (fromDay !== null) found.push(fromDay);
    }
  }
  return found;
}

export interface PlanSafetyVerdict {
  safe: boolean;
  /// The offending value, for the log line. Absent when the plan is safe.
  lowest?: number;
}

/// Reject a plan that would impose any calorie target below [floor].
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
