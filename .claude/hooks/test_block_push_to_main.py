#!/usr/bin/env python3
"""Tests for block-push-to-main.py.

Two regression suites, for the two ways this guard has been wrong:

FALSE POSITIVES — the guard used to scan EVERY token for "main", so an unrelated
`gh pr create --base main` (or even `echo main`) in the same line tripped it.

FALSE NEGATIVES — the guard used to look only at explicit refspecs, so it failed
open on the likeliest accidental push of all: standing on main and typing
`git push`. It also missed `+main` (force prefix), `refs/heads/main`, and
`--all`. Rulesets are plan-gated on this repo, so the hook is the ONLY thing
protecting main. A false negative is a direct hit; a false positive is an
annoyance. Both are bugs, but they are not equally bad.

The ON_MAIN cases set BLOCK_PUSH_HEAD, which is the seam block-push-to-main.py
exposes so we can test "what branch am I on" without checking out main.

Run: python3 .claude/hooks/test_block_push_to_main.py
"""
import json
import os
import subprocess
import sys
from pathlib import Path

HOOK = Path(__file__).parent / "block-push-to-main.py"

# Explicit refspec naming a protected branch. Must block regardless of HEAD.
BLOCK = [
    "git push origin main",
    "git push --force origin main",
    "git push origin HEAD:main",
    "git push origin master",
    "git push -f origin feature/x:main",
    "git fetch origin && git push origin main",
    # destination is main, spelled differently
    "git push origin HEAD:refs/heads/main",   # fully-qualified ref
    "git push origin +main",                  # '+' is the force prefix
    "git push origin refs/heads/master",
    # pushes every local branch, main included
    "git push --all origin",
    "git push --mirror origin",
    # ── Bypasses found by adversarial review of PR #4. The guard used to reason
    #    about the command STRING; the shell does not. Every one of these was a
    #    LIVE hole while this hook was the only thing protecting main.
    "git -C /repo push origin main",          # B1: global -C between git and push
    "git -c gc.auto=0 push origin main",      # B1: global -c
    "git --git-dir=/r/.git push origin main",  # B1: --git-dir
    'git "push" origin main',                 # B2: quoted verb
    "$(git push origin main)",                # B3: command substitution
    "`git push origin main`",                 # B3: backtick substitution
    "git push origin main&",                  # B4: operator glued to the ref
    "git push origin main & echo done",       # B4: backgrounded
    # ── Foreign repo: -C/--git-dir/--work-tree retarget git at ANOTHER repo whose
    #    HEAD we cannot resolve. Any HEAD-dependent push there must fail CLOSED.
    "git -C /other push",
    "git -C /other push origin",
    "git -C /other push origin HEAD",
    "git --git-dir=/o/.git push",
]

# No refspec: git pushes the CURRENT branch. Must block only when HEAD is main.
BLOCK_WHEN_ON_MAIN = [
    "git push",
    "git push origin",
    "git push -u origin",
    "git push --force",
]

# Must never block. These are the false positives that bit us.
ALLOW = [
    # feature branches
    "git push origin feature/SAK-02-thing",
    "git push -u origin chore/SAK-01-governance",
    "git push --force origin bugfix/some-branch",
    # the false positives that used to break us
    "git push origin my-branch && gh pr create --base main",
    'echo "remote main: x"; git push origin feature/x',
    "git push origin fix/maintenance-window",  # 'main' as a substring, not a ref
    "git push origin main-fixes",              # ditto
    # not a push at all
    "git log --oneline main",
    "gh pr merge 1 --squash",
    # an explicit, safe refspec is fine even on a foreign repo — the destination
    # is named and it is not main, so HEAD never enters into it
    "git -C /other push origin feature/x",
    "git -c gc.auto=0 push origin feature/x",
]


def blocked(cmd: str, head: str = "feature/x") -> bool:
    env = dict(os.environ, BLOCK_PUSH_HEAD=head)
    p = subprocess.run(
        [sys.executable, str(HOOK)],
        input=json.dumps({"tool_input": {"command": cmd}}),
        capture_output=True,
        text=True,
        env=env,
    )
    return p.returncode == 2


def main() -> int:
    fails = 0
    total = 0

    for cmd in BLOCK:
        total += 1
        if not blocked(cmd):
            print(f"FAIL (should BLOCK): {cmd}")
            fails += 1

    for cmd in BLOCK_WHEN_ON_MAIN:
        total += 2
        if not blocked(cmd, head="main"):
            print(f"FAIL (should BLOCK while on main): {cmd}")
            fails += 1
        # ...and the same command from a feature branch is perfectly fine
        if blocked(cmd, head="feature/x"):
            print(f"FAIL (should ALLOW while on feature/x): {cmd}")
            fails += 1

    for cmd in ALLOW:
        total += 1
        if blocked(cmd):
            print(f"FAIL (should ALLOW): {cmd}")
            fails += 1

    if fails:
        print(f"\n{fails}/{total} failed")
        return 1
    print(f"{total}/{total} passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
