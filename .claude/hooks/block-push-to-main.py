#!/usr/bin/env python3
"""PreToolUse(Bash) guard: block `git push` that targets main/master.

DESIGN: FAIL CLOSED. A false positive costs one command run outside Claude Code.
A false negative silently rewrites main. Rulesets are plan-gated on this repo
(GitHub Pro required — see .github/scripts/apply-branch-protection.sh), so this
hook is currently the ONLY thing protecting main.

This guard has had two classes of bug, both now covered by
test_block_push_to_main.py:

1. FALSE POSITIVE — scanning every token for "main" blocked commands that pushed
   nothing (`gh pr create --base main`, `echo "main"`).

2. FALSE NEGATIVE — the worse direction. The guard reasoned about the command
   STRING; the shell does not. It failed open everywhere bash and a regex
   disagree:

     git -C /repo push origin main       global option between `git` and `push`
     git -c gc.auto=0 push origin main   ditto
     git "push" origin main              quoted verb
     $(git push origin main)             command substitution
     git push origin main&               operator glued to the ref

   Fixed at the root: extract command substitutions, split on REAL shell
   operators, tokenise each segment with shlex, skip git's global options
   properly, then reason about the actual refspec.

Destination spellings that all mean main: `main`, `+main` (force prefix),
`refs/heads/main`, `HEAD` while standing on main. `--all` / `--mirror` push every
branch, main included. A bare `git push` pushes the CURRENT branch.
"""
import json
import os
import re
import shlex
import subprocess
import sys

PROTECTED = {"main", "master"}

# git GLOBAL options that consume the next token. `-C` and `-c` are what the
# old regex-based guard tripped over.
GLOBAL_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}

# `git push` options that consume the next token (so it is NOT a refspec).
PUSH_OPTS_WITH_VALUE = {"--repo", "-o", "--push-option", "--receive-pack", "--exec"}

# Push every branch we cannot enumerate — main can be among them.
PUSH_ALL_FLAGS = {"--all", "--mirror"}


def current_branch() -> str | None:
    """Current branch name, or None if undeterminable (caller must fail closed).

    BLOCK_PUSH_HEAD is the test seam — it lets the suite exercise the "standing on
    main" cases without checking out main. It is a deliberate trade-off: it is
    technically a bypass (BLOCK_PUSH_HEAD=x while on main defeats the no-refspec
    check), but it only affects HEAD resolution, never an explicit `origin main`,
    and a hook cannot defend against an agent that is actively trying to evade it.
    Testability of the fail-closed paths is worth more than closing this.
    """
    override = os.environ.get("BLOCK_PUSH_HEAD")
    if override:
        return override
    try:
        r = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=5,
        )
        if r.returncode != 0:
            return None
        return r.stdout.strip() or None
    except Exception:
        return None


def segments(command: str) -> list[str]:
    """Every runnable fragment: command-substitution bodies + operator-split pieces."""
    out: list[str] = []

    text = command
    for pat in (r"\$\(([^()]*)\)", r"`([^`]*)`"):
        while True:
            m = re.search(pat, text)
            if not m:
                break
            out.extend(segments(m.group(1)))          # recurse into $( ... )
            text = text[: m.start()] + " " + text[m.end():]

    # Real shell separators. Single `&` matters: `... main&` glues to the ref.
    out.extend(re.split(r"&&|\|\||;|\||&|\n", text))
    return out


def _is_git(tok: str) -> bool:
    return tok == "git" or tok.endswith("/git")


def _normalise_dst(spec: str) -> str:
    """Destination of a refspec: strip force prefix, src:, and refs/heads/."""
    dst = spec.split(":")[-1]           # src:dst -> dst ; bare ref -> itself
    dst = dst.lstrip("+")               # +main (force) -> main
    if dst.startswith("refs/heads/"):
        dst = dst[len("refs/heads/"):]
    return dst


def _push_hits_protected(args_after_push: list[str], foreign_repo: bool = False) -> bool:
    """foreign_repo: the invocation carried -C / --git-dir / --work-tree, so it acts on
    a repo that is NOT our cwd. We cannot resolve THAT repo's HEAD, so any push whose
    destination depends on HEAD must fail closed."""
    positional: list[str] = []
    i = 0
    while i < len(args_after_push):
        t = args_after_push[i]
        if t in PUSH_ALL_FLAGS:
            return True                                  # --all / --mirror carry main
        head = t.split("=")[0]
        if head in PUSH_OPTS_WITH_VALUE:
            i += 1 if "=" in t else 2
            continue
        if t.startswith("-"):
            i += 1
            continue
        positional.append(t)
        i += 1

    def head_branch() -> str | None:
        if foreign_repo:
            return None                                  # unknowable -> caller fails closed
        return current_branch()

    # positional = [remote?, refspec...]. No refspec => git pushes the CURRENT branch.
    refspecs = positional[1:] if len(positional) > 1 else []
    if not refspecs:
        branch = head_branch()
        if branch is None:
            return True                                  # undeterminable -> fail closed
        return branch in PROTECTED

    for spec in refspecs:
        dst = _normalise_dst(spec)
        if dst == "HEAD":
            branch = head_branch()
            if branch is None or branch in PROTECTED:
                return True
            continue
        if dst in PROTECTED:
            return True
    return False


def blocks(command: str) -> bool:
    for seg in segments(command):
        if "git" not in seg or "push" not in seg:
            continue
        try:
            tokens = shlex.split(seg)                    # git "push" -> [git, push]
        except ValueError:
            return True                                  # unparseable + mentions push -> fail closed

        i = 0
        while i < len(tokens):
            if not _is_git(tokens[i]):
                i += 1
                continue
            j = i + 1
            foreign_repo = False
            while j < len(tokens):                       # skip git's GLOBAL options
                t = tokens[j]
                opt = t.split("=")[0]
                if opt in GLOBAL_OPTS_WITH_VALUE:
                    # -C / --git-dir / --work-tree retarget git at ANOTHER repo, whose
                    # HEAD we cannot resolve from here.
                    if opt in {"-C", "--git-dir", "--work-tree"}:
                        foreign_repo = True
                    j += 1 if "=" in t else 2
                    continue
                if t.startswith("-"):
                    j += 1
                    continue
                break
            if j < len(tokens) and tokens[j] == "push":
                if _push_hits_protected(tokens[j + 1:], foreign_repo=foreign_repo):
                    return True
            i = j + 1
    return False


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 2                                         # cannot read the call -> fail closed

    command = (payload.get("tool_input") or {}).get("command", "") or ""
    try:
        hit = blocks(command)
    except Exception:
        hit = True                                       # any failure -> fail closed

    if hit:
        sys.stderr.write(
            "Blocked: direct push to main/master is not allowed. "
            "Create a feature branch (<prefix>/<desc>) and open a PR — "
            "main is integrated via squash-and-merge only. "
            "If this is intentional and authorized, run the push outside Claude Code."
        )
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
