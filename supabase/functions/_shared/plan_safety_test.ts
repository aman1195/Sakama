import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  AbsoluteCalorieFloor,
  calorieTargetsIn,
  checkPlanSafety,
} from "./plan_safety.ts";

// The prompt asked the model not to prescribe starvation. These pin the part
// that does not depend on the model agreeing.
//
// The rule under test is "what target will this plan actually IMPOSE", not
// "what small numbers appear in this JSON". The difference is the whole file:
// the first version asked the second question and rejected safe plans for it.

Deno.test("an ordinary plan passes", () => {
  const plan = {
    name: "4-Week Reset",
    targets_default: { calories: 1800, macros: { protein_g: 120 } },
    day_types: {
      light: { targets: { calories: 1500, macros: { protein_g: 110 } } },
      normal: { targets: { calories: 1900, macros: { protein_g: 120 } } },
    },
  };
  assert(checkPlanSafety(plan).safe);
});

Deno.test("a starvation day is rejected even when the default is fine", () => {
  // The realistic failure: the headline number looks responsible and one day
  // type inside it does not.
  const plan = {
    targets_default: { calories: 1800 },
    day_types: {
      normal: { targets: { calories: 1800 } },
      fast: { targets: { calories: 600 } },
    },
  };
  const verdict = checkPlanSafety(plan);
  assertEquals(verdict.safe, false);
  assertEquals(verdict.lowest, 600);
});

Deno.test("a starvation default is rejected", () => {
  assertEquals(checkPlanSafety({ targets_default: { calories: 800 } }).safe, false);
});

Deno.test("the boundary is inclusive — exactly the floor is allowed", () => {
  assert(checkPlanSafety({ targets_default: { calories: 1200 } }).safe);
  assertEquals(
    checkPlanSafety({ targets_default: { calories: 1199 } }).safe,
    false,
  );
});

Deno.test("a plan that states no calories at all is safe", () => {
  // Every field a plan leaves silent falls back to the client's computed
  // target, which is already floored. Rejecting this would kill the legitimate
  // plan that only sets an eating window.
  const plan = {
    name: "16:8",
    day_types: {
      normal: { fasting_window: { eat_start: "12:00", eat_end: "20:00" } },
    },
  };
  assert(checkPlanSafety(plan).safe);
});

// THE FALSE POSITIVES THE FIRST VERSION HAD. Each of these is a SAFE plan that
// a whole-document walk rejected, and each rejection costs the user one of two
// daily generations, unrefunded and without a retry.
Deno.test("a named dish with its own calories does not fail the plan", () => {
  // The generator prompt actively pushes the model toward naming real dishes,
  // so this is the neighbourhood a `calories` field turns up in. The client
  // ignores `sample_meals` entirely (tolerant parsing, plan.dart:5-11).
  const plan = {
    targets_default: { calories: 1800 },
    day_types: {
      normal: {
        label: "Regular day",
        sample_meals: [{ name: "idli + sambar", calories: 350 }],
      },
    },
  };
  assert(checkPlanSafety(plan).safe, "350 kcal is a dosa, not a daily target");
});

Deno.test("a rule that ADJUSTS calories is not read as a target", () => {
  // A negative number here fails a naive minimum outright.
  const plan = {
    targets_default: { calories: 2000 },
    rules: [{ id: "r1", effect: { calories: -200 }, message: "lighter today" }],
  };
  assert(checkPlanSafety(plan).safe);
});

Deno.test("only the two positions the CLIENT parses are read", () => {
  const plan = {
    targets_default: { calories: 1800 },
    day_types: { normal: { targets: { calories: 1700 } } },
    notes: { week_four: { targets: { calories: 500 } } },
  };
  // 500 sits somewhere the client never looks, so it can never become anyone's
  // target. Reading it would reject a safe plan.
  assertEquals(calorieTargetsIn(plan), [1800, 1700]);
  assert(checkPlanSafety(plan).safe);
});

Deno.test("day_types as a LIST is ignored, exactly as the client ignores it", () => {
  // plan.dart:327 reads day_types only when it is a Map. A list is invisible to
  // both sides, so nothing in it can be imposed on a user.
  const plan = {
    targets_default: { calories: 1800 },
    day_types: [{ targets: { calories: 700 } }],
  };
  assertEquals(calorieTargetsIn(plan), [1800]);
  assert(checkPlanSafety(plan).safe);
});

// THE SERVER AND THE CLIENT MUST AGREE ON WHAT A NUMBER IS. The client's
// `_asInt` (plan.dart:21-26) accepts a numeric string; a server that required a
// real JSON number would call this plan silent while the client read 600 kcal
// out of it.
Deno.test("a quoted number is a target, because the client parses it as one", () => {
  assertEquals(calorieTargetsIn({ targets_default: { calories: "600" } }), [600]);
  assertEquals(checkPlanSafety({ targets_default: { calories: "600" } }).safe, false);
});

Deno.test("a float is a target, rounded the way the client rounds it", () => {
  assertEquals(checkPlanSafety({ targets_default: { calories: 1199.6 } }).safe, false);
  assert(checkPlanSafety({ targets_default: { calories: 1800.4 } }).safe);
});

Deno.test("a non-numeric string is not a target", () => {
  assertEquals(calorieTargetsIn({ targets_default: { calories: "low" } }), []);
  assertEquals(calorieTargetsIn({ targets_default: { calories: "" } }), []);
  assert(checkPlanSafety({ targets_default: { calories: "low" } }).safe);
});

Deno.test("NaN and Infinity are not treated as targets", () => {
  assertEquals(calorieTargetsIn({ targets_default: { calories: NaN } }), []);
  assertEquals(calorieTargetsIn({ targets_default: { calories: Infinity } }), []);
});

Deno.test("null and junk inputs are safe rather than fatal", () => {
  for (const junk of [null, undefined, 42, "plan", []]) {
    assert(checkPlanSafety(junk).safe, `${junk} should not throw`);
  }
  assert(checkPlanSafety({ targets_default: null, day_types: null }).safe);
  assert(checkPlanSafety({ day_types: { normal: null } }).safe);
});

Deno.test("a cyclic document terminates", () => {
  // deno-lint-ignore no-explicit-any
  const cyclic: any = { targets_default: { calories: 1800 } };
  cyclic.self = cyclic;
  assert(checkPlanSafety(cyclic).safe);
});

Deno.test("the floor is the number the system prompt states", () => {
  // If someone loosens one, this fails and they have to look at the other.
  assertEquals(AbsoluteCalorieFloor, 1200);
});
