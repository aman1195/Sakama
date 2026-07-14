# Code Review Standards

**The checklist is the residue, not the review.** How to actually *find* defects (objective-first reading,
blast-radius order, adversarial input hunting, tool-grounded refutation) is in
[docs/REVIEW.md](docs/REVIEW.md). Read it once, properly. Then use this page as the recall aid.

The AI reviewer that executes that method is [`pr-reviewer`](.claude/agents/pr-reviewer.md). **Its approval is
never a merge gate.**

## Before you read a line

**Name the review objective.** In a randomised trial, reviewers given no instruction found an injected
data-leak bug 3% of the time. Given a one-line "review this from a security perspective", 46% found it. Adding
a checklist on top changed nothing. This is the highest-leverage thing a reviewer does.

Then return the PR unread if: it exceeds ~300 hand-written LOC, mixes a refactor with a behaviour change, has
no *why* in the description, or changes an ADR-gated surface with no ADR (Drift table, RLS policy, sync
topology, new dependency, LLM call path).

## Severity

| Label | Contract |
|---|---|
| `blocking:` | Merge does not happen until it is fixed **in this PR**. Must cite a rule, a fact, or a reproducible failure. |
| `should-fix:` | Must be addressed. A linked issue is acceptable **only** if the PR *exposed* the problem rather than *introduced* it. |
| `nit:` | The author may ignore it. If you would not merge without it, it was never a nit. |

**Unlabelled means blocking.** Label everything that is not.

## The five carve-outs

Everywhere else, the bar is "does this improve code health". On these five it is **correct, not better**, and
LGTM-with-comments is **forbidden** (you cannot un-run a migration on a user's phone):

1. A Drift migration
2. An RLS policy or a new user table (including PowerSync sync rules)
3. Anything that could put a provider key or a BYOK key into the client bundle or a log
4. A new dependency, or copied code
5. OFF/ODbL data crossing into the proprietary food table

## Reviewer checklist

### Correctness
- [ ] Does it do what the PR says? Edge cases (timezones, day boundaries, unit conversion)?
- [ ] Nutrition math correct? Values stored **per 100 g**, servings derived?
- [ ] **Offline path works?** Does the provider chain end at Drift rather than the network?
- [ ] NULL macros treated as **unknown**, not zero? `serving_size == 0` guarded?

### Data & privacy
- [ ] **RLS present** on any new user table (`auth.uid() = user_id`)? Is there a **negative** test proving user
      B cannot see user A's rows? (A positive-only suite passes with RLS switched off.)
- [ ] PowerSync bucket parameters come from a **JWT claim**, never from the client?
- [ ] No health PII in logs, analytics, or crash reports?
- [ ] No API key in the client? BYOK keys encrypted and redacted?

### Mobile (blocking — see [docs/MOBILE.md](docs/MOBILE.md))
- [ ] Drift schema change? Is the **schema snapshot in the diff**? Without it the migration is untested no
      matter how many tests the PR adds.
- [ ] Is there a **data-integrity** migration test with **non-empty rows** asserting counts and values? A
      schema-only test proves the DDL, not the data.
- [ ] Risky change behind a server-side kill switch? **We cannot hotfix.**

### Licence (blocking)
- [ ] New dependency permissive (MIT/Apache/BSD/CC0)? Read `pubspec.lock` for **transitive** adds. **LGPL is
      the one that hides.**
- [ ] No code copied from a copyleft app?
- [ ] Food rows carry `source`, `licence`, `confidence`? OFF data in its **separate** table?
- [ ] Ran [`licence-guard`](.claude/agents/licence-guard.md) if deps or food data changed?

### AI
- [ ] Calls routed client → Edge Function → LiteLLM (never direct from the client)?
- [ ] Cheap model by default? Long system prompts cached? Per-user budget enforced at the proxy?
- [ ] Model output validated **server-side** before persisting, with `source`/`licence`/`confidence`/`user_id`
      set by server literals, never by the model?
- [ ] Any numeric target **clamped server-side**? A system-prompt instruction is not a guardrail.

### Tests
- [ ] Mentally mutate the central changed line. **Does any assertion go red?** If not, the test is decoration.
- [ ] Assertions exact and hand-computed? `expect(x, isNotNull)` survives every unit-conversion bug we can have.
- [ ] Nutrition math and queries run against a **real in-memory sqlite3**, not a mocked DAO.

### Craft
- [ ] Feature-first structure? Logic out of widgets? Disposal of every subscription, controller, timer?
- [ ] Accessibility identifiers on new interactive widgets?
- [ ] Follows [docs/DESIGN.md](docs/DESIGN.md), and adds no "AI chrome"?

## Reviewer conduct

Review the change, not the person. Ask before asserting: the author has spent days in this code and you have
spent twenty minutes. **Never fire an untested suggestion** — proposing a different migration or conflict
policy without having run it means the author carries all the risk of your idea.

If a reviewer misread the code, **the fix goes into the code** (a clearer name, a doc comment, an ADR), not
into a reply. A disagreement about a *decision* rather than a *line* is an ADR, not a comment thread.

**Do not spend the review's attention on the easy thing.** Every nit on a trailing comma is a comment not spent
on the `onUpgrade` block that will silently drop six months of a user's food logs.
