# Restraint & Verification (MANDATORY)

These rules apply to EVERY change, in EVERY module — when planning, generating code, or making design choices. They exist to stop the two most common AI failure modes: overbuilding, and asserting things that aren't true.

- **Simplicity first.** Write the minimum code that solves the *stated* problem. No speculative features, no abstractions nobody asked for, no "framework" for a one-off. If a senior engineer would call it overcomplicated, simplify.
- **Surgical changes.** Touch only what the task requires. No drive-by refactors, no renaming/reformatting/reordering unrelated code, no "while I'm here" edits. Match the style of the file you're editing. Clean up only your own mess.
- **Verify before you assert.** Never claim a file, function, symbol, flag, table, column, or env var exists — or that a test/build passes — without checking it THIS session (grep/read/run). Retrieve, don't recall. If you cannot verify, say "unverified" rather than stating it as fact.
- **State assumptions, then proceed.** If the request is ambiguous, state the assumption in one line and continue — don't silently guess, and don't stall on questions you can answer by reading the code.
