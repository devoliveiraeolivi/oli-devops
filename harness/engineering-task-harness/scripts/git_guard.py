#!/usr/bin/env python3
"""Block accidental raw Git/worktree cleanup from agent shell tool calls (Codex and Claude Code)."""

from __future__ import annotations

import json
import os
import re
import shlex
import sys
from typing import Any

BYPASS = "ENGINEERING_HARNESS_ALLOW_RAW_GIT_CLEANUP=1"

# Sensível a maiúsculas: o comando é `git`; "Git" em corpo de PR ou mensagem não casa.
RULES: tuple[tuple[re.Pattern[str], str], ...] = (
    (
        re.compile(r"\bgit\b[^\n;&|]*\bworktree\s+(?:remove|prune)\b"),
        "remoção ou prune de worktree",
    ),
    (
        re.compile(
            r"\bgit\b[^\n;&|]*\bpush\b[^\n;&|]*\s(?:--delete\b|-d\b|--prune\b|--mirror\b|\+?:[\w./-]+)"
        ),
        "remoção de branch remota",
    ),
)

# Exclusão forçada de branch local (`-D`, `-d -f`, `--delete --force`). `git branch -d` passa: o
# próprio git só apaga branch já mergeada.
BRANCH = re.compile(r"\bgit\b[^\n;&|]*?\bbranch(\s[^\n;&|]*)")

# `rm` como palavra de comando (não `--rm` do docker); flags recursiva e forçada em qualquer ordem.
RM = re.compile(r"(?<![\w-])rm\b([^\n;&|]*)")
RECURSIVE = re.compile(r"\s(?:-[A-Za-z]*[rR][A-Za-z]*|--recursive)\b")
FORCE = re.compile(r"\s(?:-[A-Za-z]*f[A-Za-z]*|--force)\b")
# A raiz em si e qualquer descendente (não `GitHubBackup`).
PROTECTED_ROOT = re.compile(
    r"/Documents/GitHub(?![\w.-])|/\.codex/worktrees(?![\w.-])|/private/tmp/oli-"
)

# Texto entre aspas e corpo de heredoc contam como comando (conservador: `bash -c`, ssh,
# pipe para shell, interpretador). Exceção só para contextos de dado conhecidos: mensagem ou
# corpo de commit/PR/release, padrão de busca e heredoc que só grava arquivo (cat/tee). Em dado,
# só `$(...)` e crase executam.
DATA_FLAG = re.compile(r"-[A-Za-z]*m|--(?:message|body|title|notes|subject|grep)")
DATA_ASSIGNMENT = re.compile(r"--(?:message|body|title|notes|subject|grep)=")
SEARCH_COMMANDS = {"grep", "egrep", "fgrep", "rg", "ag", "ack"}
WRITER_HEREDOC = re.compile(
    r"((?:^|[;&|(\n])[ \t]*(?:cat|tee)\b(?:[^\n;&|]|[<>]&|&>)*?)"  # `&` só em redirecionamento
    r"<<-?[ \t]*(['\"]?)([A-Za-z_]\w*)\2([^\n]*)\n((?:.*?\n)?)[ \t]*\3[ \t]*(?=\n|$)",
    re.DOTALL,
)
SUBSTITUTION = re.compile(r"\$\([^()]*\)|`[^`]*`")
OPERATORS = {"&&", "||", ";", "|", "&"}
ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=")
# O bypass só vale como atribuição no início do próprio comando, nunca em comentário ou mensagem.
LEADING_BYPASS = re.compile(r"\s*(?:[A-Za-z_]\w*=\S*\s+)*" + re.escape(BYPASS) + r"\s")


def strip_writer_heredoc(match: re.Match[str]) -> str:
    kept = match.group(1) + "<<" + match.group(3) + match.group(4)
    if not match.group(2):  # delimitador sem aspas: o shell executa $(...) e `...` do corpo
        kept += "".join("\n" + found for found in SUBSTITUTION.findall(match.group(5)))
    return kept


def is_data(token: str, words: list[str]) -> bool:
    previous = words[-1] if words else ""
    return bool(
        DATA_FLAG.fullmatch(previous)
        or DATA_ASSIGNMENT.match(token)
        or any(os.path.basename(word) in SEARCH_COMMANDS for word in words)
    )


def scan_segments(command: str) -> list[tuple[str, bool]] | None:
    """Cada comando (segmento) sem os trechos só de dado, e se ele começa com o bypass.

    Retorna None quando o comando não é tokenizável.
    """
    command = WRITER_HEREDOC.sub(strip_writer_heredoc, command)
    command = command.replace("\\\n", " ")
    try:
        lexer = shlex.shlex(command.replace("\n", " ; "), posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        lexer.commenters = ""  # comentário também é escaneado (conservador)
        tokens = list(lexer) + [";"]
    except ValueError:
        return None
    segments: list[tuple[str, bool]] = []
    words: list[str] = []
    kept: list[str] = []
    for token in tokens:
        if token in OPERATORS:
            if words:
                leading = []
                for word in words:
                    if not ASSIGNMENT.match(word):
                        break
                    leading.append(word)
                segments.append((" ".join(kept), BYPASS in leading))
            words, kept = [], []
            continue
        # Token com espaço só existe se veio entre aspas (ou escapado).
        if any(char.isspace() for char in token) and is_data(token, words):
            rest = SUBSTITUTION.sub("", token)
            # Substituição que a regex não casa (`(` ou `)` dentro de `$(...)`, inclusive entre
            # aspas ou em `case`; crase escapada; `$(` sem fechar): o token inteiro é analisado.
            nested = "\\`" in token or "`" in rest or "$(" in rest or ("$(" in token and ")" in rest)
            kept.extend([token] if nested else SUBSTITUTION.findall(token))
        else:
            kept.append(token)
        words.append(token)
    return segments


def resolve_operand(operand: str, cwd: str | None) -> str | None:
    if any(char in operand for char in "$`*?["):
        return None  # depende de expansão: fica com a checagem pelo texto
    path = os.path.expanduser(operand)
    if not os.path.isabs(path):
        if cwd is None:
            return None
        path = os.path.join(cwd, path)
    return os.path.normpath(path)  # lexical: `rm` de um symlink não apaga o alvo


def protected(path: str) -> bool:
    """Raiz protegida, ancestral dela, ou raiz de repo/worktree dentro dela."""
    codex_home = os.environ.get("CODEX_HOME", os.path.expanduser("~/.codex"))
    for root in (os.path.expanduser("~/Documents/GitHub"), os.path.join(codex_home, "worktrees")):
        if path == root or root.startswith(path.rstrip("/") + "/"):
            return True
    return bool(PROTECTED_ROOT.search(path)) and os.path.lexists(os.path.join(path, ".git"))


def forced_branch_delete(text: str) -> bool:
    for match in BRANCH.finditer(text):
        flags = [word for word in match.group(1).split() if word.startswith("-")]
        short = "".join(flag[1:] for flag in flags if not flag.startswith("--"))
        delete = "d" in short or "--delete" in flags
        force = "f" in short or "--force" in flags
        if "D" in short or (delete and force):
            return True
    return False


def rule_violation(text: str, command: str, cwd: str | None) -> str | None:
    for pattern, label in RULES:
        if pattern.search(text):
            return label
    if forced_branch_delete(text):
        return "remoção forçada de branch local"
    for match in RM.finditer(text):
        args = match.group(1)
        if not (RECURSIVE.search(args) and FORCE.search(args)):
            continue
        paths = [resolve_operand(arg, cwd) for arg in args.split() if not arg.startswith("-")]
        if PROTECTED_ROOT.search(command) or any(path and protected(path) for path in paths):
            return (
                "rm recursivo em raiz usada por repositórios ou worktrees (se o rm não apaga "
                "repo nem worktree, rode-o num comando separado, sem citar o repo)"
            )
    return None


def block_reason(command: str, cwd: str | None = None) -> str | None:
    segments = scan_segments(command)
    if segments is None:  # não tokenizável: texto cru, como antes
        if LEADING_BYPASS.match(command):
            return None
        segments = [(command, False)]
    for text, bypassed in segments:
        reason = None if bypassed else rule_violation(text, command, cwd)
        if reason:
            return reason
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
    cwd = payload.get("cwd") if isinstance(payload.get("cwd"), str) else os.getcwd()
    reason = block_reason(command_from(payload), cwd)
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
