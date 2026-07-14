#!/usr/bin/env python3
"""PreToolUse(Bash) guard: block `git push` that targets main/master.

Enforces the repo rule "feature branches merged via squash-and-merge" — main is
protected. Direct pushes to main/master are blocked; push to any feature branch
is allowed. Exit 2 + stderr tells Claude why and what to do instead.
"""
import json
import re
import sys


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0  # never break the tool call on a parse error

    command = (payload.get("tool_input") or {}).get("command", "") or ""
    if not re.search(r"\bgit\s+push\b", command):
        return 0

    tokens = command.replace("'", " ").replace('"', " ").split()
    protected = {"main", "master"}
    for tok in tokens:
        # exact ref, or src:dst forms (HEAD:main, main:main)
        dst = tok.split(":")[-1]
        if tok in protected or dst in protected:
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
