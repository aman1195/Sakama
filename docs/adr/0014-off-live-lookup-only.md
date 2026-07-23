# 0014. Open Food Facts: live lookup + per-scan cache. Do NOT ship an OFF snapshot.

**Status:** Accepted · **Date:** 2026-07-22 ·
**Settles:** the open "live vs. bundled" question left by
[0012](0012-ship-bundled-food-data.md) and `ASSET_CREDITS.md` ·
**Changes:** the previously-leaning "Option B (bundle a filtered Indian OFF snapshot)"

## Context

Open Food Facts is **ODbL**. Its share-alike attaches to a **Derivative Database** that you
*distribute* — not to our app code. Two postures were on the table (ASSET_CREDITS.md):

| Option | ODbL exposure | Cost |
|---|---|---|
| **A. Live lookup only** | **Low.** No derived database is distributed. | A brand-new barcode needs connectivity. |
| **B. Bundle a filtered Indian OFF snapshot** | **Higher.** We ship an OFF-derived database → share-alike likely applies to it; be prepared to publish it as open data. **Requires counsel review before launch.** | Barcode works fully offline. |

B was the standing lean. The argument for it was our offline-first promise (CLAUDE.md rule 1).

## The decision

**Option A: live lookup, with a per-barcode local cache of the user's own scans.**

The offline-first argument for B does not survive contact with how the diary actually works:

- **Logging copies nutrition values into `food_logs`** — our own user data. A meal logged in March
  renders in December, offline, with **no OFF row present**. This was the stated requirement that
  disqualified Edamam/Spoonacular (see base-decision.md), and Option A satisfies it fully.
- OFF data is therefore only needed at **scan time**.
- A **previously scanned** barcode resolves from the local cache, offline.
- The only real loss is scanning a **brand-new** barcode while offline — a narrow, explainable limit.

Against that narrow loss, Option A removes: a distributed derived database, the share-alike question
over it, the pre-launch counsel review B required, and the app-size/downloadable-pack problem
(issue #36 dissolves rather than needing a mechanism).

A cache of individually-requested lookups is a materially weaker claim to a "Derivative Database"
than a shipped bulk export — a distinction ASSET_CREDITS.md itself already drew.

## Consequences

- **ODbL containment is unchanged and still mandatory** (CLAUDE.md rule 5): cached OFF rows live in
  the physically separate `off_foods` table, tagged `source='openfoodfacts'`, `licence='ODbL'`, and
  are never merged into the proprietary `foods` table. A test asserts `foods` stays empty after an
  OFF write; the `odbl-containment` CI gate backs it.
- **Attribution is still required** and is already surfaced (Data sources & licences screen), which
  renders OFF automatically once rows exist.
- We must send OFF an **identifying User-Agent** (anonymous clients are blocked) and respect rate
  limits. Cache-first keeps request volume low.
- **No OFF bulk-dump pipeline** is built. `supabase/seed/` handles USDA only.
- **Option A is a strict subset of B.** If offline scanning of unseen barcodes later proves to be a
  real user need, B remains available — it would add a bundled snapshot on top of this, and would
  then need the counsel review.

## Alternatives rejected

- **Bundle the snapshot now (B)** — takes on distributable-derived-database risk and a counsel
  dependency to buy offline scanning of barcodes the user has never seen. Poor trade pre-launch.
- **No barcode at all** — packaged food is a large share of Indian urban intake; scanning is table
  stakes against HealthifyMe.
