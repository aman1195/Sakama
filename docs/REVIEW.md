# Code Review: the method

The enumerable checklist lives in [CODE_REVIEW.md](../CODE_REVIEW.md) and the PR template. **This document is
the part a checklist cannot give you**: how to sequence a review, how to find the defects that reading
harder will never surface, and what to do about the fact that human review is a *partial* filter.

Read [MOBILE.md](MOBILE.md) first. Everything here is shaped by two facts: **you cannot hotfix**, and **a bad
on-device migration destroys user data irrecoverably**.

## Evidence tiers

Used inline throughout. Do not let a `[J]` rule be argued as though it were `[E]`.

| Tag | Meaning |
|---|---|
| `[E]` | **Evidenced.** Replicated empirical finding, or a primary vendor document quoted verbatim. |
| `[C]` | **Consensus.** Google eng-practices, Chromium, Conventional Comments. Widely adopted, not measured. |
| `[J]` | **Sakama judgement.** Derived from our constraints. Defensible, but cite no outside authority for it. |

---

## 1. Severity

Three levels. The label is a contract about the merge gate, not decoration.

**`blocking:`** Merge does not happen until this is resolved **in this PR**. Reserved for:

- Irrecoverable on-device data loss (a Drift migration, a destroyed upload queue)
- Cross-user data exposure (an RLS gap, a permissive policy, a leaky PowerSync bucket)
- A secret reaching a client binary or a log line
- Copyleft (GPL/AGPL/LGPL/SSPL) or ODbL contamination
- A wrong number shown to a user in a health context
- Medically unsafe LLM output with no server-side clamp
- An uncapped LLM spend path
- Anything that bricks cold start

**`should-fix:`** Must be addressed. A linked, assigned issue is acceptable **only** if the PR *exposed* the
problem rather than *introduced* it. Anything this PR introduces is fixed in this PR. This asymmetry is the
documented mechanism of codebase decay: "unless the developer does the clean up immediately after the present
CL, it never happens" ([Google, pushback](https://google.github.io/eng-practices/review/reviewer/pushback.html)) `[C]`.

**`nit:`** Non-blocking. The author may ignore it. If you would not merge without it, it was never a nit, and
writing `nit:` while withholding approval destroys the signal permanently `[C]`.

Two hard conventions:

1. **Unlabelled means blocking** `[J]`. We invert the usual convention because an unlabelled comment (and
   especially an AI-generated one) reads as an order and costs the author a cycle.
2. **A blocking comment must cite a rule, a verifiable fact, or a reproducible failure.** "I would have
   written it differently" never blocks. Google: "Technical facts and data overrule opinions and personal
   preferences" `[C]`.

A style point is blockable only if it is *written down* (Effective Dart, `analysis_options.yaml`, an ADR).
If it exists only in the reviewer's head, it is a nit.

## 2. The approval bar

Google's standard, verbatim: *"reviewers should favor approving a CL once it is in a state where it definitely
improves the overall code health of the system being worked on, even if the CL isn't perfect"* `[C]`.

Sakama layers **five carve-outs** where the bar is **correct**, not **better than before**, because these are
irreversible rather than aesthetic `[J]`:

1. A Drift migration
2. An RLS policy or a new user table (including PowerSync sync rules)
3. Anything that could put a provider key or a BYOK key into the client bundle or a log
4. A new dependency, or copied code (licence)
5. OFF/ODbL data crossing into the proprietary food table

**LGTM-with-comments** is the default for UI and state PRs `[C]`. It is **forbidden** on all five carve-outs:
"I trust you will fix it" is unrecoverable once a migration has run on a user's phone.

---

## 3. The method

### Pass 0. Gate before you read

Return the PR unread if any of these hold:

- **No ADR on an ADR-gated surface** `[J]`: a Drift table, an RLS policy or user table, sync topology, a new
  dependency, or the LLM call path. This makes "your design is wrong" a cheap conversation instead of a
  week-destroying one.
- **The description is "Fix bug" / "Phase 1" / "WIP".** The body must state the *why* that is not visible in
  the diff `[C]`.
- **More than ~300 hand-written LOC** (excluding `.g.dart` / `.freezed.dart`), or a refactor mixed with a
  behaviour change.
- **The author has not self-reviewed.**

Cisco/SmartBear (2,500 reviews, 3.2M LOC): defect density collapses above 250 LOC, and reviewers going faster
than 450 LOC/hour were below-average at finding defects in 87% of cases `[E]`.

Returning a PR costs the author twenty minutes. Reviewing it costs you an hour at degraded accuracy.

### Pass 1. State the review objective out loud, before reading

**This is the single highest-leverage finding in the literature.** Braz et al. (ICSE 2022, randomised, n=150):
with no instruction, **1 of 33 reviewers (3%)** found an injected bug that leaked sensitive data into a log
line. Given a one-line instruction to "review this from a security perspective", **19 of 41 (46%)** found it.
An OWASP checklist on top added **nothing** measurable `[E]`.

The bug they measured was a *log leak*. That is exactly the class Sakama cannot afford: health PII or a BYOK
key in an Edge Function log.

So: **name the objective before you read.**

| PR touches | Objective |
|---|---|
| `supabase/migrations/**` | data isolation, irreversible migration risk |
| Drift schema / `onUpgrade` | irrecoverable on-device data loss |
| Edge Function / LiteLLM | key leakage, PII redaction, cost ceiling |
| PowerSync sync rules | cross-user download leak, conflict semantics |
| Food / nutrition domain | unit correctness, provenance |
| `pubspec.yaml` | licence contamination, supply chain |
| Flutter UI | jank, offline-first, accessibility |

### Pass 2. Reconstruct the invariant before opening a file

Write two sentences first:

1. What is this change supposed to make true?
2. What was true before that must **still** be true after?

If you cannot write them, you cannot review the PR. Ask.

Bacchelli & Bird (Microsoft, 873 developers): finding defects demanded the *highest* level of code
understanding of any review outcome, and 82% said a reviewer already familiar with the files gives
substantively different feedback `[E]`. One senior developer, verbatim: *"I've seen quite a few code reviews
where someone commented on formatting while missing the fact that there were security issues or data model
issues."*

Sakama's invariants are explicit, which makes this cheap. Which does this PR touch?

- Nutrition is canonically **per 100 g**; per-serving is derived at read time.
- Every food row carries `source`, `licence`, `confidence`.
- **ODbL (OFF) rows never touch the proprietary Indian food table.**
- The UI reads Drift, never the network.
- `auth.uid() = user_id` gates every user table.
- Every synced row has a **client-generated UUID** primary key.
- "Today" is a stored `local_date`, not a re-derived UTC truncation.

A PR touching none of these is a low-attention PR. A PR touching one gets the full method.

### Pass 3. Read in blast-radius order, and send objections immediately

Not file order `[J]`:

```
1. supabase/migrations        (schema, GRANT, RLS policy)
2. PowerSync sync rules
3. Drift schema, onUpgrade, schema snapshots
4. Edge Function / LiteLLM call path
5. pubspec.yaml + pubspec.lock
6. Domain models -> DAO/repository -> Riverpod providers
7. Widgets
8. Tests (alongside the layer they cover)
```

Google's rule applies directly: *"If you see some major design problems with this part of the CL, you should
send those comments immediately, even if you don't have time to review the rest of the CL right now. In fact,
reviewing the rest of the CL might be a waste of time"* `[C]`.

Concretely: **if the PR adds a table with no RLS policy, comment and stop.** Do not spend an hour on providers
that are about to be rewritten.

### Pass 4. Adversarial stance: what input makes this wrong?

"Does this look right" is a recognition task and passes almost everything. Replace it with generate-and-attack.
Standing list, in the order that pays:

- empty collection; single-element collection
- **null versus zero** (different bugs; in nutrition the difference is a lie to the user)
- negative and zero quantities (a 0 g serving size is a division by zero in the per-serving derivation, and
  OFF rows genuinely contain them)
- duplicate entries; retried entries
- a unit that is not the unit assumed (kcal vs kJ, g vs ml)
- a clock that moved backwards, or a device that changed timezone mid-day
- a second concurrent invocation (double-tap, second device, retry-while-in-flight)

Of the 78 defect comments Bacchelli & Bird catalogued, **65 were logical issues**, and they name the kind:
*"uncomplicated logical errors, e.g., corner cases"* `[E]`. When review catches a defect, it is overwhelmingly
a corner case.

### Pass 5. Read the code that did NOT change

A diff shows what the author thought about. Bugs live in what they did not.

For every changed signature, default, nullability, enum case, or column: **grep every caller and ask whether
the old assumption still holds.**

- A new enum case falls silently into every existing `default:`. In Dart, exhaustiveness is a compiler
  guarantee only when the class is `sealed` **and** the switch has no `default:` arm.
- A new NOT NULL column either aborts the migration or **silently backfills a meaningless value into every
  pre-existing row**. The second is the dangerous one: a defaulted `confidence` then ranks as though it were
  verified data.
- Tightening a validator rejects every already-persisted record that predates it.
- **Changing a Drift table means changing every existing user's on-device database, which you cannot see and
  cannot fix.**

Three Sakama couplings that do **not** fail at compile time `[J]`:

- A Drift table change silently invalidates generated DAOs until `build_runner` reruns.
- The per-100 g canonical unit is dereferenced at every per-serving read site.
- A new column in a synced table must be added in **three files**: the Drift schema, the PowerSync sync rules,
  and the Supabase migration.

### Pass 6. Read the deletions, and the absences

Every red line claims something is no longer needed, and it is the least-scrutinised part of a PR because it
reads as tidy-up. A deleted test. A removed null check or validator. A removed `mounted` guard. A removed kill
switch. A removed RLS policy or GRANT. **A modified schema snapshot for an already-shipped version**, which
makes every migration test from that version onward a fiction about what is actually on users' phones.

**And the absences.** Every catastrophic risk in Sakama is an *absence*: a missing RLS policy, an untested
migration, an ODbL row in the wrong table, a missing kill switch, a GPL transitive dependency. **Absences do
not appear in a diff.** They are caught by a mechanical omission check or a CI assertion, never by reading
harder. This is why §5 exists.

### Pass 7. Refute every candidate finding against a tool, not against yourself

Do **not** run a second round of thinking and call it verification. LLMs *"struggle to self-correct their
responses without external feedback, and at times, their performance even degrades after self-correction"*
([Huang et al., ICLR 2024](https://arxiv.org/abs/2310.01798)) `[E]`. An introspective verify pass launders the
original error into a more confident one.

Refutation means **executing something that could return disconfirming evidence**:

| Finding class | Refutation |
|---|---|
| RLS gap | Open the migration SQL. Confirm no policy exists and no GRANT compensates. |
| Offline-first violation | Grep the provider chain from widget to Drift DAO. |
| Migration data loss | Open `onUpgrade` and the schema snapshot. Confirm the test fixture. |
| API does not exist | Read `pubspec.lock` and the pinned package source. |
| Cross-file break | Open the unchanged caller. |

Then, **for any runtime finding, state a concrete failure trace**: specific input or state, the exact line
reached, the wrong output, with file:line for each step. If you cannot construct the trace by reading the
code, discard the finding rather than softening it to a nit.

But **specificity is not correctness**. The largest false-positive bucket in AI review is 48% "lack of
contextual understanding": confidently specific findings built on a misread of surrounding code `[E]`.
Requiring a trace filters *vague* findings. Only checking the trace against the real file filters *wrong* ones.

Non-runtime classes are **exempt** from the trace requirement because they cannot produce one: a licence
violation, a secret in the client, a missing RLS policy, a missing migration test. For these, the evidence
*is* the citation: the file, the line, and the rule it breaks.

### Pass 8. Review tests by mental mutation

Do not check that tests exist. Check that they can **fail**.

Take the central changed line and mutate it mentally: flip `<` to `<=`, negate a boolean, return an empty list,
swap two same-typed arguments. Does any assertion go red? If not, the test is decoration. Google's guide asks
exactly this: *"Will the tests actually fail when the code is broken?"* `[C]`

Three pathologies:

1. **Weak assertions.** `expect(totals.calories, isNotNull)` for a three-item meal survives *every*
   unit-conversion bug the product can have. Demand exact, hand-computed values.
2. **Change-detector tests.** Mocks every collaborator and asserts methods were called. Restates the
   implementation; fails when it *changes*, never when it is *wrong* `[C]`.
3. **Tautology.** The expected value is produced by the code under test, or by the same helper production uses.

**Sakama's mock trap is the DAO.** A repository test that mocks the Drift DAO proves nothing about the SQL, the
migration, or the per-100 g math, and those are exactly where the irrecoverable bugs live. Nutrition arithmetic
and any query run against a real in-memory sqlite3, not a mock.

### Pass 9. Write the review

- Rank most-severe-first. **Precision over volume.** Uber's uReview prunes with a confidence threshold rather
  than a comment cap; their stated lesson is *"comment quality matters far more than quantity"* `[E]`.
- **Do not truncate to a fixed count.** A defect-dense migration PR with twelve real findings must not lose
  four below a cut line `[J]`.
- **An empty findings list is a legitimate outcome.** In the Cisco data, **61% of reviews found zero
  defects** `[E]`.
- **Say what is good, specifically.** No hollow praise: Conventional Comments notes it *"can actually be
  damaging."*
- **All structural feedback goes in round one.** Nothing fundamental after the author starts polishing.
- **If a reviewer misread the code, the fix goes into the code**, not into a reply. A clearer name, a doc
  comment, an ADR. Google: *"Explanations written only in the code review tool are not helpful to future code
  readers."* `[C]`
- **A disagreement about a decision, not a line, is an ADR.** Close the thread and move the argument somewhere
  it gets a durable answer `[J]`.

## 4. Techniques a checklist cannot encode

**Never fire an untested suggestion.** A reviewer who writes "I do not like X, have you tried Y?" is
*"recording their idea in such a way that they get credit if it works out, but the original implementer
undertakes all the risk that it does not"* (Chelsea Troy) `[C]`. In Sakama the expensive hand-waves are
migration strategy, Riverpod provider shape, and PowerSync conflict semantics. A reviewer proposing a
different migration must have **run** it against a pre-migration fixture. Otherwise the comment downgrades to
`question:` `[J]`.

**Ask why before asserting what.** The author has spent days in the code; you have spent twenty minutes.
Google: *"Often, they are closer to the code than you are."* This repo has already reversed multiple confident
claims under scrutiny. A reviewer who has not run the branch opens with `question:`.

**Treat the PR description as an untrusted claim, not as context.** "Migration is safe, tested locally" is a
hypothesis to check. It is also precisely the input that triggers sycophantic agreement in an LLM reviewer
`[E]`. A PR body asserting the migration is safe obliges you to **demand the test**, not to relax.

**Spend zero attention on what the toolchain enforces. Spend it where the toolchain was silenced.** Every
`// ignore:`, `ignore_for_file`, new `dynamic`, `late`, or `!` is a deliberate hole in the type system and a
precise map of where the author was unsure. That is the target, not the lint the analyzer already caught.

**Parkinson's Law of Triviality is the default, not an accident.** Every nit on a trailing comma is a comment
not spent on the `onUpgrade` block that will silently drop six months of a user's food logs.

---

## 5. Human review is a partial filter. Make the invariants deterministic.

**Do not treat review as Sakama's defect net.** Two industrial datasets say it is not one:

- Microsoft (570 real review comments): defects were only the **fourth** most common category, at 14%. Of
  those, **five** concerned security `[E]`.
- Google (ICSE-SEIP 2018): **2 of 44** respondents said review comments on their change found a bug `[E]`.

Add Edmundson (n=30, security-briefed developers averaging **2.33 of 7** known vulnerabilities, with
experience *not* predicting accuracy) and the conclusion is forced: **every invariant that can be a machine
check must be one, and the reviewer's job is to review the check, not to replace it.**

Required CI gates. These are the real reviewer:

| Gate | Catches |
|---|---|
| Migrate into a throwaway Postgres; classify every `public` table against a reviewed allowlist; fail on any table with no RLS, any policy-without-RLS, any write grant to `anon` | The RLS **absence**, which has no diff line to comment on |
| pgTAP negative-isolation test per user table (user B sees zero of A's rows) | Positive-only suites pass with RLS switched off |
| Fail if any `public` view lacks `security_invoker` | A full RLS bypass via a convenience view |
| `drift_dev make-migrations` produces no diff in `drift_schemas/` | An untested migration with green CI |
| Drift all-pairs migration test + data-integrity test with non-empty rows | Data loss behind a valid schema |
| gitleaks on PR and pre-commit | A secret in the repo |
| Release-artifact `strings` scan | A key shipped inside a binary |
| Licence checker over `pubspec.lock` (transitive, not direct) | Copyleft contamination |
| Analytics property-key allowlist test | Health PII in crash reports |
| Golden nutrition basket | A wrong number wearing a cosmetic disguise |
| Red-team eval on any prompt or model diff | Medically harmful coaching output |

**A deterministic assertion has 100% recall on the property it checks. Review demonstrably does not.**

---

## 6. Recipes

Short executable sequences. Each is the method applied to one change class.

### A Drift migration

1. Objective: *irrecoverable on-device data loss*.
2. No ADR? Stop.
3. Is `drift_schemas/drift_schema_vN.json` in the diff, and is N registered? **If not, the migration is
   untested no matter how many tests the PR adds. Stop.**
4. Read `onUpgrade`. One transaction? Is there an `if (from > to)` branch?
5. Does it touch an **existing** column shape? Then find the data-integrity test with **non-empty rows
   asserting counts and values**. A schema-only test proves the DDL, not the data.
6. New constraint? Construct the violating row in your head, then find it in the fixture. If it is absent,
   that is the finding.
7. `TableMigration(` is a `DROP TABLE` with a copy in front. Second reviewer.
8. Does the fixture include the Sakama edge rows: an OFF food, an INDB food, an AI estimate with `confidence`,
   a null-macro row, a 0 g serving, a Devanagari name? **Assert `source` / `licence` / `confidence` survive.**
   Losing them is a licence incident, not a bug.

### An RLS policy

1. Objective: *cross-user health-data exposure*.
2. Read the migration SQL, not the ORM.
3. `enable row level security` naming the **exact** table? Narrow GRANTs, nothing to `anon`?
4. Build the four-command matrix. A missing INSERT policy means the user cannot log a meal. An UPDATE policy
   with no SELECT policy matches zero rows.
5. Read every `WITH CHECK`. Reject `(true)`. **Then list every *other* permissive policy on that table**: they
   OR together, and a broad one defeats a narrow one.
6. A new view needs `security_invoker = true` or it is a full bypass.
7. A new `SECURITY DEFINER` function needs `set search_path = ''` and must re-derive `auth.uid()`.
8. **Find the negative test** impersonating user B. Positive-only tests pass with RLS off.
9. **Then read the PowerSync sync rules.** RLS does not govern downloads. A perfect policy plus a leaky bucket
   is still a leak.

### An LLM call path

1. Objective: *key leakage, PII redaction, cost ceiling, output safety*.
2. Confirm the egress: client to Edge Function to LiteLLM. Any Dart HTTP call to a provider host is blocking.
3. Is the acting user taken from the verified JWT? A `user_id` read from the request body and passed to a
   service-role query is a cross-user read.
4. Is PHI redacted **in the Edge Function**, before the gateway?
5. Does any provider `build()` call the gateway? Riverpod 3 auto-retries with backoff, and **every retry is
   billed**.
6. Is untrusted text (OFF product names, OCR output) fenced and length-capped before entering the prompt?
7. Is model output that reaches a row validated **server-side**, with `source` / `licence` / `confidence` /
   `user_id` set by server literals, never by the model?
8. Is any numeric target **clamped server-side**? A system-prompt instruction is not a guardrail.

### A sync / conflict change

1. Objective: *cross-user download leak, silent data loss*.
2. Trace every bucket parameter to a **JWT claim**. A client-supplied parameter is a leak.
3. Confirm every bucket's data query repeats the ownership predicate. Bucket selection is not row filtering.
4. State the conflict policy for every writable table. The default is last-write-wins.
5. Is any user-visible total a mutable incrementable column? Two devices, 250 ml each, LWW gives 250. Blocking.
6. Is the primary key **client-generated**? A server default turns a retried upload into a duplicate meal.
7. What happens when Postgres rejects the write? If the transaction is discarded, **the user's meal vanishes
   with a log line**. State the strategy.
8. Two-account manual test before merge.

### A new dependency

1. Objective: *licence contamination, supply chain*.
2. Read `pubspec.lock`, not `pubspec.yaml`. Enumerate every **transitive** addition.
3. Open each new LICENSE. MIT / Apache-2.0 / BSD / CC0 only. **LGPL is the one that hides.**
4. Does it ship native code, build hooks, or new manifest permissions? Those run on CI and on user devices.
5. Does it collect data? Then it is a Play Data Safety change and an iOS privacy-manifest change.
6. Did the CI licence gate actually run on it, or silently skip?

### A nutrition-math change

1. Objective: *unit correctness, provenance*.
2. Every write: is the column per-100 g, and is the value per-100 g?
3. Every read: is the per-serving derivation guarded against `serving_size == 0` or null?
4. Every sum: are NULL macros treated as **unknown**, not zero? Is the total marked incomplete?
5. Units in the name or the type. A bare numeric parameter with no unit is a finding.
6. Round once, at display.
7. An AI estimate must never display as verified data.
8. Assertions are exact and hand-computed. `isNotNull` survives every bug in this list.

### A UI change

1. Objective: *offline-first, jank, accessibility*.
2. Follow the provider chain from the widget to its source. **Does it end at Drift?** If it touches Supabase or
   an HTTP client, that is blocking.
3. `ref.read` of state in `build()` gives a stale total. `ref.watch` in `onPressed` is not the subscription the
   author thinks it is.
4. Disposal: every subscription, controller, timer.
5. Expensive work in `build()`: date formatting, sorting, chart mapping, day-total summation. Memoise it.
6. **No screenshot from a real device means do not approve.** A Flutter diff tells you nothing about jank, safe
   areas, or a keyboard covering the log button.
7. Hardcoded strings; missing Devanagari fallback; a golden at max text scale.
8. `Semantics` on charts and icon-only controls.

---

## 7. AI review: what it can do, and what a human must still own

Sakama uses an AI reviewer ([.claude/agents/pr-reviewer.md](../.claude/agents/pr-reviewer.md)). Its limits are
measured, not rhetorical:

- **SWR-Bench** (1,000 verified PRs, full repository snapshots): best F1 **19.4%**; most configurations scored
  **precision below 10%**. Aggregating *independent* passes lifted F1 by 43.7% relative, so a single pass is
  **unstable**, not merely weak `[E]`.
- **Vulnerability detection** on de-duplicated real-world data drops to near chance `[E]`.
- **19.7%** of LLM code samples referenced a **non-existent package**, and 43% of hallucinated names recurred
  identically across repeated prompts. Hallucinated identifiers are *stable*, which is exactly why they read as
  authoritative `[E]`.
- **METR RCT**: experienced developers were **19% slower** with AI while believing they were **20% faster**
  `[E]`. Felt helpfulness is not evidence of helpfulness.

Operating rules:

1. **AI approval is never a merge gate.** "No issues found" is not evidence of correctness.
2. **An effective false positive is any finding the developer took no action on**, even a technically-true one.
   This kills the reviewer's favourite excuse ("but I was technically right").
3. **Tool-grounded refutation before reporting.** No introspective "are you sure?" round (Pass 7).
4. **Every named package, class, method, or config key must have been read from the repo or the lockfile this
   session.** The Riverpod case is worse than random: a model will confidently "correct" valid Riverpod 3 code
   back to Riverpod 2 idioms it has far more training data on.
5. **Web performance vocabulary is a hallucination smell.** TTFB, LCP, bundle size, hydration: any of these in
   a comment on a Flutter app means the model pattern-matched the wrong domain. **Discard the whole comment.**

**The reviewer is an attack surface.** CVE-2025-59145 (CamoLeak, CVSS 9.6) executed instructions hidden in
**invisible Markdown comments** inside PRs, in the reviewer's own context, and exfiltrated data through image
URLs. Every attacker-writable field is model input: the PR title, body, commit messages, code comments, test
fixtures, and **HTML comments that a human reviewer cannot see in rendered Markdown**. The reviewer job must
never hold `SUPABASE_SERVICE_ROLE_KEY` or signing secrets, must trigger on `pull_request` and never
`pull_request_target`, and must **report** injection-shaped text as a finding rather than act on it.

**What a human must still own:**

1. **Should this exist at all.** No model has access to product intent, or accountability for a health app
   showing a user a wrong number.
2. **The go/no-go on an irreversible surface.** A migration, an RLS policy, a licence call, an ODbL boundary.
   An AI finding may *inform* that decision. It may not *be* it.
3. **Product safety.** Whether a coaching response is medically acceptable; whether a calorie floor is
   clinically defensible.
4. **The architecture argument.** That belongs in an ADR, decided by a human, before the implementation PR
   opens.

---

## 8. Refuted claims. Do not re-introduce these.

Each circulates widely. Each was checked against primary sources and found wrong.

1. **"200-400 LOC over 60-90 minutes yields 70-90% defect discovery."** The 70-90% figure **is not in the Cisco
   study**. It appears only on marketing material, attributed to a study that does not contain it. Cite the
   real numbers instead: 32 defects/kLOC average, **61% of reviews found zero defects**, density collapses
   above 250 LOC and above 450 LOC/hour.
2. **"Small PRs merge faster."** Fails to replicate (Kudrjavets, MSR 2022, 845k PRs: no relationship between
   PR size and time-to-merge). Justify small PRs on **defect detection**, not on speed.
3. **"Two reviewers is the ceiling."** The opposite of what the sources say. Google's median is **one**, and
   more reviewers produced **more** comments. "Diffusion of responsibility" is unsupported.
4. **"Omitting `WITH CHECK` on an UPDATE policy lets a user steal a row."** **False for the simple case.**
   Postgres explicitly reuses the `USING` expression as the `WITH CHECK` expression when none is given. Review
   for the *real* shapes: an explicit `WITH CHECK (true)`, asymmetric predicates, and *another* permissive
   policy with a broader `WITH CHECK`.
5. **"Lax participation predicts post-release defects."** Did not replicate (Krutauz et al., EMSE 2020). And
   banning self-approval on a one-human repo blocks every merge and gets admin-bypassed.

---

## Sources

The full research synthesis, its 136 primary sources, and the adversarial verification record are in
[research/pr-review-synthesis.md](research/pr-review-synthesis.md).
