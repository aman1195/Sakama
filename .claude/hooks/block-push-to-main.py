#!/usr/bin/env python3
"""PreToolUse(Bash) guard: block `git push` that targets main/master.

Enforces the repo rule "feature branches merged via squash-and-merge" — main is
protected. Direct pushes to main/master are blocked; push to any feature branch
is allowed. Exit 2 + stderr tells Claude why and what to do instead.

This guard has had two classes of bug. Both are now covered by
test_block_push_to_main.py:

1. FALSE POSITIVE — scanning every token in the command for "main" blocked
   commands that pushed nothing (`gh pr create --base main`, `echo "main"`).
   Fixed by inspecting only the `git push` segment.

2. FALSE NEGATIVE — the guard failing open, which is the worse direction:
   - `git push` with no refspec pushes the CURRENT branch. Standing on main,
     that pushes main. The guard has to ask what branch HEAD is on.
   - The destination is not always spelled "main". `+main` (the `+` is the
     force prefix) and `refs/heads/main` both denote main.
   - `--all` / `--mirror` push every local branch, main included.

Rulesets are plan-gated on a free private repo (see
.github/scripts/apply-branch-protection.sh), so this hook is currently the ONLY
thing protecting main. It must fail closed.
"""
import json
import os
import re
import subprocess
import sys

PROTECTED = {"main", "master"}

MESSAGE = (
    "Blocked: direct push to main/master is not allowed. "
    "Create a feature branch (<prefix>/<desc>) and open a PR — "
    "main is integrated via squash-and-merge only. "
    "If this is intentional and authorized, run the push outside Claude Code."
)


def normalise(token: str) -> str:
    """Reduce a refspec token to the destination branch it denotes.

    feature/x:main   -> main   (src:dst)
    +main            -> main   ('+' is the force prefix)
    refs/heads/main  -> main   (fully-qualified ref)
    """
    dst = token.split(":")[-1].lstrip("+")
    return re.sub(r"^refs/heads/", "", dst)


def current_branch(cwd: str) -> str:
    """The branch HEAD is on. Empty when detached, or not a git repo.

    BLOCK_PUSH_HEAD lets the test suite exercise the no-refspec cases without
    checking out main in a throwaway clone.
    """
    override = os.environ.get("BLOCK_PUSH_HEAD")
    if override is not None:
        return override
    try:
        out = subprocess.run(
            ["git", "symbolic-ref", "--quiet", "--short", "HEAD"],
            cwd=cwd or None,
            capture_output=True,
            text=True,
            timeout=5,
        )
        return out.stdout.strip()
    except Exception:
        return ""


def targets_protected(segment: str, cwd: str) -> bool:
    tokens = segment.replace("'", " ").replace('"', " ").split()
    try:
        after_push = tokens[tokens.index("push") + 1:]
    except ValueError:
        return False

    flags = [t for t in after_push if t.startswith("-")]
    refs = [t for t in after_push if not t.startswith("-")]

    # --all / --mirror push every local branch, main included.
    if "--all" in flags or "--mirror" in flags:
        return True

    # An explicit refspec: `git push origin main`, `git push origin HEAD:main`.
    if any(normalise(t) in PROTECTED for t in refs):
        return True

    # No refspec (`git push`, `git push origin`, `git push -u origin`): git
    # pushes the CURRENT branch. This is the likeliest accidental push to main,
    # and the previous version of this guard allowed it.
    if len(refs) <= 1:
        return current_branch(cwd) in PROTECTED

    return False


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0  # never break the tool call on a parse error

    command = (payload.get("tool_input") or {}).get("command", "") or ""
    if not re.search(r"\bgit\s+push\b", command):
        return 0

    cwd = payload.get("cwd") or os.environ.get("CLAUDE_PROJECT_DIR") or ""

    # Inspect ONLY the `git push` segment. Scanning the whole command string
    # false-positives on anything that merely mentions main — an unrelated
    # `gh pr create --base main`, or even `echo "main"`, in the same line.
    for segment in re.split(r"&&|\|\||;|\n", command):
        if not re.search(r"\bgit\s+push\b", segment):
            continue
        if targets_protected(segment, cwd):
            sys.stderr.write(MESSAGE)
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
