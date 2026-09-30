#!/usr/bin/env python3
"""Block accidental raw Git/worktree cleanup from Codex shell tool calls."""

from __future__ import annotations

import json
import re
import sys
from typing import Any

BYPASS = "ENGINEERING_HARNESS_ALLOW_RAW_GIT_CLEANUP=1"

RULES: tuple[tuple[re.Pattern[str], str], ...] = (
    (
        re.compile(r"\bgit\b[^\n;&|]*\bworktree\s+(?:remove|prune)\b", re.IGNORECASE),
        "remoção ou prune de worktree",
    ),
    (
        re.compile(r"\bgit\b[^\n;&|]*\bbranch\s+(?:-[dD]\b|--delete\b)", re.IGNORECASE),
        "remoção de branch local",
    ),
    (
        re.compile(r"\bgit\b[^\n;&|]*\bpush\b[^\n;&|]*\s--delete\b", re.IGNORECASE),
        "remoção de branch remota",
    ),
)

RM_RF = re.compile(r"\brm\s+-(?:[A-Za-z]*r[A-Za-z]*f|[A-Za-z]*f[A-Za-z]*r)\b")
PROTECTED_ROOTS = ("/Documents/GitHub/", "/.codex/worktrees/", "/private/tmp/oli-")


def block_reason(command: str) -> str | None:
    if BYPASS in command:
        return None
    for pattern, label in RULES:
        if pattern.search(command):
            return label
    if RM_RF.search(command) and any(root in command for root in PROTECTED_ROOTS):
        return "rm recursivo em raiz usada por repositórios ou worktrees"
    return None


def command_from(payload: dict[str, Any]) -> str:
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return ""
    value = tool_input.get("command") or tool_input.get("cmd")
    return value if isinstance(value, str) else ""


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        return 0
    reason = block_reason(command_from(payload))
    if not reason:
        return 0
    message = (
        f"Engineering Task Harness bloqueou {reason}. Rode inventory/assess --github, "
        "registre path, branch e HEAD e obtenha aprovação explícita para os alvos exatos. "
        f"Após essa aprovação, repita o comando com {BYPASS} no mesmo invocation."
    )
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "PreToolUse",
                    "permissionDecision": "deny",
                    "permissionDecisionReason": message,
                }
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
