#!/usr/bin/env python3
"""Emit concise Git/worktree context for a Codex SessionStart hook."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


def git(cwd: Path, *args: str) -> str | None:
    result = subprocess.run(
        ["git", "-C", str(cwd), *args],
        capture_output=True,
        text=True,
        check=False,
        timeout=5,
    )
    return result.stdout.strip() if result.returncode == 0 else None


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError):
        payload = {}

    cwd = Path(payload.get("cwd") or os.getcwd()).expanduser().resolve()
    root_text = git(cwd, "rev-parse", "--show-toplevel")
    if not root_text:
        return 0

    root = Path(root_text).resolve()
    branch = git(root, "branch", "--show-current") or "DETACHED"
    head = git(root, "rev-parse", "--short=12", "HEAD") or "unknown"
    status = git(root, "status", "--porcelain=v1")
    dirty = len(status.splitlines()) if status else 0
    common_text = git(root, "rev-parse", "--git-common-dir") or ".git"
    common = Path(common_text)
    if not common.is_absolute():
        common = (root / common).resolve()

    codex_root = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))).resolve()
    if codex_root / "worktrees" in root.parents:
        kind = "codex-managed"
    elif (root / ".git").is_dir():
        kind = "base-checkout"
    else:
        kind = "linked-worktree"

    context = (
        "Engineering task harness ativo. Antes de qualquer escrita, classifique a task como "
        "review, spec, feature ou debug e aplique a política da skill engineering-task-harness. "
        f"Contexto Git atual: root={root}; tipo={kind}; branch={branch}; HEAD={head}; "
        f"itens_sujos={dirty}; git_common_dir={common}. "
        "Review deve começar somente leitura. Feature e persistência de spec usam ambiente dedicado; "
        "debug pode reproduzir no ambiente existente, mas a correção não deve misturar mudanças alheias. "
        "Nunca remova/prune worktree ou branch com base apenas em status clean, detached ou upstream gone; "
        "audite linhagem, PR/equivalência e obtenha autorização explícita para a lista exata."
    )
    print(
        json.dumps(
            {"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": context}},
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
