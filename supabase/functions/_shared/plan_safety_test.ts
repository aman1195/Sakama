import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  AbsoluteCalorieFloor,
  calorieTargetsIn,
  checkPlanSafety,
} from "./plan_safety.ts";

// The prompt asked the model not to prescribe starvation. These pin the part
// that does not depend on the model agreeing.

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

Deno.test("a calorie target in an UNDOCUMENTED position is still caught", () => {
  // The whole reason this walks the object instead of reading two known paths.
  // A checker that only looked where the schema says to look would hand this
  // straight to the user.
  const plan = {
    targets_default: { calories: 1800 },
    notes: { week_four: { targets: { calories: 500 } } },
  };
  assertEquals(checkPlanSafety(plan).safe, false);
});

Deno.test("arrays are walked, not skipped", () => {
  // day_types is an object in the schema, but a model that emits a LIST is a
  // realistic deviation and must not become a way past the check.
  const plan = {
    day_types: [{ targets: { calories: 1800 } }, { targets: { calories: 700 } }],
  };
  assertEquals(checkPlanSafety(plan).safe, false);
});

Deno.test("a non-numeric calories field does not crash or pass silently", () => {
  // "calories": "600" is not a number, so it is not a target this can judge.
  // It must not throw, and it must not be read as 600 either.
  const plan = { targets_default: { calories: "600" } };
  assert(checkPlanSafety(plan).safe);
  assertEquals(calorieTargetsIn(plan), []);
});

Deno.test("NaN and Infinity are not treated as targets", () => {
  assertEquals(calorieTargetsIn({ targets: { calories: NaN } }), []);
  assertEquals(calorieTargetsIn({ targets: { calories: Infinity } }), []);
});

Deno.test("null and junk inputs are safe rather than fatal", () => {
  for (const junk of [null, undefined, 42, "plan", []]) {
    assert(checkPlanSafety(junk).safe, `${junk} should not throw`);
  }
});

Deno.test("a deeply nested document terminates", () => {
  // A cyclic or adversarially nested object must not hang the function; the
  // bound is depth, so this returns rather than recursing forever.
  // deno-lint-ignore no-explicit-any
  const cyclic: any = { targets_default: { calories: 1800 } };
  cyclic.self = cyclic;
  const verdict = checkPlanSafety(cyclic);
  assert(verdict.safe);
});

Deno.test("the floor is the number the system prompt states", () => {
  // If someone loosens one, this fails and they have to look at the other.
  assertEquals(AbsoluteCalorieFloor, 1200);
});
