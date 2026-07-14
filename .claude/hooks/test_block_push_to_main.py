#!/usr/bin/env python3
"""Tests for block-push-to-main.py.

Regression cover for the false-positive that bit us twice: the guard used to scan
EVERY token in the command for "main", so an unrelated `gh pr create --base main`
(or even `echo main`) in the same line tripped it.

Run: python3 .claude/hooks/test_block_push_to_main.py
"""
import json
import subprocess
import sys
from pathlib import Path

HOOK = Path(__file__).parent / "block-push-to-main.py"

BLOCK = [
    "git push origin main",
    "git push --force origin main",
    "git push origin HEAD:main",
    "git push origin master",
    "git push -f origin feature/x:main",
    "git fetch origin && git push origin main",
]

ALLOW = [
    # feature branches
    "git push origin feature/SAK-02-thing",
    "git push -u origin chore/SAK-01-governance",
    "git push --force origin fix/some-branch",
    # the false-positives that used to break us
    "git push origin my-branch && gh pr create --base main",
    'echo "remote main: x"; git push origin feature/x',
    "git push origin fix/maintenance-window",  # 'main' as a substring, not a ref
    # not a push at all
    "git log --oneline main",
    "gh pr merge 1 --squash",
]


def blocked(cmd: str) -> bool:
    p = subprocess.run(
        [sys.executable, str(HOOK)],
        input=json.dumps({"tool_input": {"command": cmd}}),
        capture_output=True,
        text=True,
    )
    return p.returncode == 2


def main() -> int:
    fails = 0
    for cmd in BLOCK:
        if not blocked(cmd):
            print(f"FAIL (should BLOCK): {cmd}")
            fails += 1
    for cmd in ALLOW:
        if blocked(cmd):
            print(f"FAIL (should ALLOW): {cmd}")
            fails += 1
    total = len(BLOCK) + len(ALLOW)
    if fails:
        print(f"\n{fails}/{total} failed")
        return 1
    print(f"✅ {total}/{total} passed ({len(BLOCK)} blocked, {len(ALLOW)} allowed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
