#!/usr/bin/env python3
"""Emit concise Git/worktree context for a SessionStart hook (Codex and Claude Code)."""

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


def worktree_kind(root: Path) -> str:
    codex_root = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))).resolve()
    if codex_root / "worktrees" in root.parents:
        return "codex-managed"
    if root.parent.name == "worktrees" and root.parent.parent.name == ".claude":
        return "claude-managed"
    if (root / ".git").is_dir():
        return "base-checkout"
    return "linked-worktree"


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

    context = (
        "Engineering task harness ativo: use a skill engineering-task-harness; ela prevalece "
        "sobre fluxos genéricos de skills. "
        f"Contexto Git: root={root}; tipo={worktree_kind(root)}; branch={branch}; HEAD={head}; "
        f"itens_sujos={dirty}; git_common_dir={common}. "
        "Antes de escrever, classifique a task (review, spec, feature ou debug); review começa "
        "somente leitura; feature e correção vão para worktree dedicada. "
        "Siga a decisão registrada na spec (Gate 0); fora dela, pare e pergunte. "
        "Antes do código: premissas sobre o estado atual com arquivo:linha, conferidas por agente "
        "em contexto novo; invariantes viram testes que falham primeiro. "
        "Nunca remova worktree ou branch só por estar clean, detached ou upstream gone: audite "
        "linhagem e PR e peça autorização para a lista exata."
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
