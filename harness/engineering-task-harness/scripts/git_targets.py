#!/usr/bin/env python3
"""List the `git push`/`git commit` calls of a PreToolUse event for the harness hooks.

Reads the event JSON on stdin; arguments filter the verbs (default: push commit). Prints one
line per call: `<dir>\t<marker>\t<switched>\t<refs>` (refs last: it may be empty).

- dir: follows earlier `cd X`, `env -C X` and `git -C X`; otherwise the event cwd. A call
  whose directory depends on a variable is not listed (the hooks fail open).
- marker: 1 if `HARNESS_GATE_OK=1` is a leading assignment of that command.
- refs: local refs sent, space-separated. `HEAD` for a commit or a push without refspec; each
  refspec source; `:multi` for --all/--tags/glob/`:`; `:unknown` when it depends on a
  variable; nothing when the push only deletes. A dry run is not listed.
- switched: 1 if an earlier `git checkout`/`git switch` in the same command may change the
  branch before this call runs (the hook sees the repo before the command runs).

The hooks are backstops: when this parse is unsure, they let the command through.
Runs on Python 3.9 (macOS /usr/bin/python3, used by the Codex hooks).
"""

from __future__ import annotations

import json
import os
import re
import shlex
import sys
from collections.abc import Iterator
from typing import NamedTuple

OPERATORS = {"&&", "||", ";", "|", "&", "|&", ";;"}
REDIRECTION = re.compile(r"[<>&]*[<>][<>&]*")
ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=")
KEYWORDS = {"if", "then", "else", "elif", "while", "until", "do", "!", "{"}
PUNCTUATION = re.compile(r"[();<>|&]+")
GATE_MARKER = "HARNESS_GATE_OK=1"
HEREDOC = re.compile(
    r"<<-?[ \t]*(['\"]?)([A-Za-z_]\w*)\1([^\n]*)\n(?:.*?\n)?[ \t]*\2[ \t]*(?=\n|$)", re.DOTALL
)
COMMENT_LINE = re.compile(r"^[ \t]*#[^\n]*$", re.MULTILINE)
TRAILING_COMMENT = re.compile(r"(^|[ \t])#[^\n]*", re.MULTILINE)
WRAPPER_OPTIONS_WITH_VALUE = {
    "env": {"-u", "--unset", "-S", "--split-string"},
    "timeout": {"-k", "--kill-after", "-s", "--signal"},
}
GIT_OPTIONS_WITH_VALUE = {"-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
PUSH_OPTIONS_WITH_VALUE = {
    "-o", "--push-option", "--repo", "--receive-pack", "--exec", "--recurse-submodules",
}
MULTI, UNKNOWN = ":multi", ":unknown"  # ':' nunca aparece em nome de ref


class Target(NamedTuple):
    verb: str
    directory: str
    marker: bool
    refs: list[str]
    switched: bool


def is_dynamic(word: str) -> bool:
    return "$" in word or "`" in word


def tokenize(command: str) -> list[str]:
    command = HEREDOC.sub(lambda m: "<<" + m.group(2) + m.group(3), command)
    command = COMMENT_LINE.sub("", command).replace("\\\n", " ")
    try:
        return split(command)
    except ValueError:  # aspas soltas num comentário no fim da linha
        return split(TRAILING_COMMENT.sub(r"\1", command))


def split(command: str) -> list[str]:
    lexer = shlex.shlex(command.replace("\n", " ; "), posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    lexer.commenters = ""
    tokens: list[str] = []
    for token in lexer:  # `)&&` → `)` `&&`: parênteses sempre isolados
        if PUNCTUATION.fullmatch(token) and token.strip("()"):
            tokens.extend(part for part in re.split(r"([()])", token) if part)
        else:
            tokens.append(token)
    return tokens


def commands(tokens: list[str]) -> Iterator[list[str]]:
    """Palavras de cada comando simples, sem redirecionamentos e comentários.

    Parênteses (subshell, `$(...)`) saem como segmentos próprios para o chamador escopar `cd`.
    """
    words: list[str] = []
    skip_next = in_comment = False
    for token in tokens + [";"]:
        if token in OPERATORS:
            if words:
                yield words
            words, skip_next, in_comment = [], False, False
        elif in_comment:
            continue
        elif skip_next:
            skip_next = False
        elif token.startswith("#"):
            in_comment = True
        elif REDIRECTION.fullmatch(token):
            if words and words[-1].isdigit():
                words.pop()  # descritor: o `2` de `2>&1`
            skip_next = True  # alvo do redirecionamento
        elif not token.strip("()"):
            if words:
                yield words
            words, skip_next = [], False
            yield [token]
        else:
            words.append(token)


def resolve(base: str | None, path: str) -> str | None:
    if base is None or is_dynamic(path) or path == "-":
        return None
    return os.path.normpath(os.path.join(base, os.path.expanduser(path)))


def push_sources(args: list[str]) -> list[str] | None:
    """Local refs a `git push` sends; None for a dry run, [] when it only deletes."""
    positional: list[str] = []
    multi = delete = False
    index = 0
    while index < len(args):
        arg = args[index]
        if arg in ("-n", "--dry-run"):
            return None
        if arg in ("--all", "--branches", "--mirror", "--tags"):
            multi = True
        elif arg in ("-d", "--delete"):
            delete = True
        elif arg in PUSH_OPTIONS_WITH_VALUE:
            index += 1
        elif not arg.startswith("-"):
            positional.append(arg)
        index += 1
    if delete:
        return []
    refs = []
    refspecs = positional[1:]
    while refspecs:
        refspec = refspecs.pop(0)
        if refspec == "tag" and refspecs:
            refs.append("refs/tags/" + refspecs.pop(0))
            continue
        source = refspec.lstrip("+").split(":", 1)[0]
        if refspec.lstrip("+") == ":" or "*" in source:
            refs.append(MULTI)  # `:` = matching branches
        elif is_dynamic(source):
            refs.append(UNKNOWN)
        elif source:  # vazio = deleção (`:branch`)
            refs.append(source)
    if multi:
        refs.append(MULTI)
    elif not positional[1:]:
        refs.append("HEAD")
    return list(dict.fromkeys(refs))


def targets(command: str, cwd: str) -> Iterator[Target]:
    """One Target per git push/commit; nothing if the command is not tokenizable."""
    try:
        parsed = list(commands(tokenize(command)))
    except ValueError:
        return
    directory: str | None = cwd
    switched = False
    scopes: list[tuple[str | None, bool]] = []
    for words in parsed:
        if not words[0].strip("()"):  # subshell: `cd` e troca de branch não vazam
            for char in words[0]:
                if char == "(":
                    scopes.append((directory, switched))
                elif scopes:
                    directory, switched = scopes.pop()
            continue
        assignments: list[str] = []
        target = directory
        index = 0
        while index < len(words):
            word = words[index]
            if ASSIGNMENT.match(word):
                assignments.append(word)
                index += 1
            elif word in KEYWORDS or word == "time":
                index += 1
            elif word in ("env", "command", "nohup", "exec", "timeout"):
                index, target = skip_wrapper(words, index, target)
            else:
                break
        if index >= len(words):
            continue
        if words[index] == "cd":
            args = [w for w in words[index + 1 :] if not w.startswith("-") or w == "-"]
            directory = resolve(directory, args[0] if args else "~")
            continue
        if words[index] != "git":
            continue
        index += 1
        while index < len(words) and words[index].startswith("-"):
            if words[index] == "-C" and index + 1 < len(words):
                target = resolve(target, words[index + 1])
                index += 2
            elif words[index] in GIT_OPTIONS_WITH_VALUE and index + 1 < len(words):
                index += 2
            else:
                index += 1
        if index >= len(words):
            continue
        subcommand, args = words[index], words[index + 1 :]
        if subcommand in ("checkout", "switch") and "--" not in args:
            switched = True
        if target is None:
            continue
        marker = GATE_MARKER in assignments
        if subcommand == "commit":
            yield Target("commit", target, marker, ["HEAD"], switched)
        elif subcommand == "push":
            refs = push_sources(args)
            if refs is not None:
                yield Target("push", target, marker, refs, switched)


def skip_wrapper(words: list[str], index: int, target: str | None) -> tuple[int, str | None]:
    """Skip `env`/`command`/`nohup`/`exec`/`timeout` and their options; env -C moves target."""
    wrapper = words[index]
    index += 1
    with_value = WRAPPER_OPTIONS_WITH_VALUE.get(wrapper, set())
    while index < len(words) and words[index].startswith("-"):
        option = words[index]
        if wrapper == "env" and option in ("-C", "--chdir") and index + 1 < len(words):
            target = resolve(target, words[index + 1])
            index += 2
        elif wrapper == "env" and option.startswith("--chdir="):
            target = resolve(target, option.split("=", 1)[1])
            index += 1
        elif option in with_value:
            index += 2
        else:
            index += 1
    if wrapper == "timeout" and index < len(words):
        index += 1  # a duração
    return index, target


def main() -> int:
    verbs = set(sys.argv[1:]) or {"push", "commit"}
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0
    tool_input = event.get("tool_input") if isinstance(event, dict) else None
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    if not isinstance(command, str):
        return 0
    cwd = event.get("cwd") or os.getcwd()
    for target in targets(command, cwd):
        if target.verb in verbs:
            print(
                f"{target.directory}\t{int(target.marker)}\t{int(target.switched)}"
                f"\t{' '.join(target.refs)}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
