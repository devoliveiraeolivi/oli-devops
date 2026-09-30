#!/usr/bin/env python3
"""Inspect and prepare Git worktrees. Destructive cleanup is intentionally absent."""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

GITHUB_PR_FIELDS = (
    "number,state,isDraft,mergedAt,closedAt,url,headRefName,baseRefName,"
    "headRefOid,baseRefOid,mergeCommit"
)


def run(cmd: list[str], *, timeout: int = 20) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, capture_output=True, text=True, check=False, timeout=timeout)


def git(cwd: Path, *args: str, timeout: int = 20) -> subprocess.CompletedProcess[str]:
    return run(["git", "-C", str(cwd), *args], timeout=timeout)


def git_text(cwd: Path, *args: str) -> str | None:
    result = git(cwd, *args)
    return result.stdout.strip() if result.returncode == 0 else None


def resolve_git_root(path: Path) -> Path:
    value = git_text(path, "rev-parse", "--show-toplevel")
    if not value:
        raise ValueError(f"não é um checkout Git: {path}")
    return Path(value).resolve()


def worktree_kind(root: Path) -> str:
    codex_home = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex"))).resolve()
    if codex_home / "worktrees" in root.parents:
        return "codex-managed"
    if (root / ".git").is_dir():
        return "base-checkout"
    return "linked-worktree"


def status_count(path: Path) -> tuple[int | None, list[str]]:
    result = git(path, "status", "--porcelain=v1")
    if result.returncode != 0:
        return None, []
    lines = [line for line in result.stdout.splitlines() if line]
    return len(lines), lines


def upstream_info(path: Path, branch: str | None) -> dict[str, Any]:
    if not branch:
        return {"upstream": None, "ahead": None, "behind": None}
    upstream = git_text(path, "rev-parse", "--abbrev-ref", "@{upstream}")
    if not upstream:
        return {"upstream": None, "ahead": None, "behind": None}
    counts = git_text(path, "rev-list", "--left-right", "--count", f"{upstream}...HEAD")
    if not counts:
        return {"upstream": upstream, "ahead": None, "behind": None}
    behind_text, ahead_text = counts.split()
    return {"upstream": upstream, "ahead": int(ahead_text), "behind": int(behind_text)}


def commit_age_days(path: Path, head: str) -> int | None:
    value = git_text(path, "show", "-s", "--format=%ct", head)
    if not value:
        return None
    return max(0, int((datetime.now(UTC).timestamp() - int(value)) // 86400))


def is_ancestor(path: Path, head: str, base: str) -> bool | None:
    if git(path, "rev-parse", "--verify", base).returncode != 0:
        return None
    result = git(path, "merge-base", "--is-ancestor", head, base)
    if result.returncode == 0:
        return True
    if result.returncode == 1:
        return False
    return None


def parse_worktrees(repo: Path) -> list[dict[str, Any]]:
    result = git(repo, "worktree", "list", "--porcelain")
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "falha ao listar worktrees")
    entries: list[dict[str, Any]] = []
    current: dict[str, Any] = {}
    for line in result.stdout.splitlines() + [""]:
        if not line:
            if current:
                entries.append(current)
                current = {}
            continue
        key, _, value = line.partition(" ")
        if key in {"detached", "bare"}:
            current[key] = True
        else:
            current[key] = value
    return entries


def github_repo_slug(repo: Path) -> str | None:
    remote = git_text(repo, "remote", "get-url", "origin")
    if not remote:
        return None
    match = re.search(r"github\.com[/:]([^/]+)/([^/]+?)(?:\.git)?$", remote)
    return f"{match.group(1)}/{match.group(2)}" if match else None


def fetch_github_prs(
    repo: Path,
    head: str | None = None,
) -> tuple[dict[str, list[dict[str, Any]]], str | None]:
    slug = github_repo_slug(repo)
    if not slug:
        return {}, "origin não aponta para github.com"
    if not shutil.which("gh"):
        return {}, "GitHub CLI (gh) não encontrado"
    command = [
        "gh",
        "pr",
        "list",
        "--repo",
        slug,
        "--state",
        "all",
        "--limit",
        "20" if head else "500",
        "--json",
        GITHUB_PR_FIELDS,
    ]
    if head:
        command.extend(["--head", head])
    result = run(command, timeout=20 if head else 45)
    if result.returncode != 0:
        return {}, result.stderr.strip() or "falha ao consultar PRs no GitHub"
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        return {}, f"resposta inválida do gh: {exc}"
    by_branch: dict[str, list[dict[str, Any]]] = {}
    for pr in payload:
        branch = pr.get("headRefName")
        if branch:
            by_branch.setdefault(branch, []).append(pr)
    return by_branch, None


def classify_with_github(
    classification: str,
    prs: list[dict[str, Any]],
) -> str:
    if any(pr.get("state") == "OPEN" for pr in prs):
        return "PRESERVAR_PR_ABERTO"
    if any(pr.get("state") == "MERGED" or pr.get("mergedAt") for pr in prs):
        if classification == "REVISAR_NAO_MERGEADO":
            return "REVISAR_MERGE_GITHUB_NAO_ANCESTRAL"
        return classification
    if prs and classification == "REVISAR_NAO_MERGEADO":
        return "REVISAR_PR_FECHADO_NAO_MERGEADO"
    return classification


def base_checkout(repo: Path) -> Path:
    common_text = git_text(repo, "rev-parse", "--git-common-dir")
    if not common_text:
        return resolve_git_root(repo)
    common = Path(common_text)
    if not common.is_absolute():
        common = (resolve_git_root(repo) / common).resolve()
    return common.parent if common.name == ".git" else resolve_git_root(repo)


def assess_entry(
    repo: Path,
    entry: dict[str, Any],
    base: str,
    github_by_branch: dict[str, list[dict[str, Any]]] | None = None,
    github_error: str | None = None,
) -> dict[str, Any]:
    path = Path(entry["worktree"]).resolve()
    exists = path.exists()
    branch_ref = entry.get("branch")
    branch = branch_ref.removeprefix("refs/heads/") if branch_ref else None
    head = entry.get("HEAD") or "unknown"
    dirty_count, changes = status_count(path) if exists else (None, [])
    merged = is_ancestor(repo, head, base) if head != "unknown" else None
    upstream = (
        upstream_info(path, branch) if exists else {"upstream": None, "ahead": None, "behind": None}
    )

    if path == base_checkout(repo):
        classification = "PRESERVAR_CLONE_BASE"
    elif not exists or entry.get("prunable"):
        classification = "METADADO_PODAVEL_REQUER_AUDITORIA"
    elif dirty_count:
        classification = "PRESERVAR_DIRTY"
    elif entry.get("locked"):
        classification = "PRESERVAR_LOCKED"
    elif not branch:
        classification = "REVISAR_DETACHED"
    elif merged is True:
        classification = "CANDIDATA_MERGEADA"
    elif merged is False:
        classification = "REVISAR_NAO_MERGEADO"
    else:
        classification = "REVISAR_BASE_DESCONHECIDA"

    github_prs = github_by_branch.get(branch, []) if github_by_branch is not None and branch else []
    if github_by_branch is not None:
        classification = classify_with_github(classification, github_prs)

    return {
        "path": str(path),
        "exists": exists,
        "kind": worktree_kind(path) if exists else "missing",
        "branch": branch,
        "detached": not bool(branch),
        "head": head,
        "head_age_days": commit_age_days(repo, head) if head != "unknown" else None,
        "dirty_count": dirty_count,
        "changes_sample": changes[:10],
        "base": base,
        "head_merged_in_base": merged,
        "locked": entry.get("locked"),
        "prunable": entry.get("prunable"),
        "classification": classification,
        "github_prs": github_prs,
        "github_error": github_error,
        **upstream,
    }


def repo_inventory(repo: Path, base: str, github: bool = False) -> dict[str, Any]:
    root = base_checkout(repo)
    github_by_branch, github_error = fetch_github_prs(root) if github else (None, None)
    return {
        "repo": root.name,
        "base_checkout": str(root),
        "target_base": base,
        "github_checked": github,
        "github_error": github_error,
        "worktrees": [
            assess_entry(root, entry, base, github_by_branch, github_error)
            for entry in parse_worktrees(root)
        ],
    }


def discover_base_repos(scan_root: Path) -> list[Path]:
    if not scan_root.is_dir():
        raise ValueError(f"diretório inexistente: {scan_root}")
    return [
        child.resolve()
        for child in sorted(scan_root.iterdir())
        if child.is_dir() and (child / ".git").is_dir()
    ]


def context(path: Path) -> dict[str, Any]:
    root = resolve_git_root(path)
    branch = git_text(root, "branch", "--show-current") or None
    dirty_count, changes = status_count(root)
    common_text = git_text(root, "rev-parse", "--git-common-dir") or ".git"
    common = Path(common_text)
    if not common.is_absolute():
        common = (root / common).resolve()
    return {
        "root": str(root),
        "base_checkout": str(base_checkout(root)),
        "kind": worktree_kind(root),
        "branch": branch,
        "detached": branch is None,
        "head": git_text(root, "rev-parse", "HEAD"),
        "dirty_count": dirty_count,
        "changes_sample": changes[:10],
        "git_common_dir": str(common),
    }


def render_markdown(inventories: list[dict[str, Any]]) -> str:
    lines = [
        "| Repo | Worktree | Branch | Dirty | No base | PR | Classificação |",
        "|---|---|---|---:|---|---|---|",
    ]
    for inventory in inventories:
        for item in inventory["worktrees"]:
            lines.append(
                "| {repo} | `{path}` | `{branch}` | {dirty} | {merged} | {prs} | {classification} |".format(
                    repo=inventory["repo"],
                    path=item["path"],
                    branch=item["branch"] or "DETACHED",
                    dirty=item["dirty_count"] if item["dirty_count"] is not None else "?",
                    merged=item["head_merged_in_base"],
                    prs=",".join(f"#{pr['number']}:{pr['state']}" for pr in item["github_prs"])
                    or "-",
                    classification=item["classification"],
                )
            )
    return "\n".join(lines)


def command_context(args: argparse.Namespace) -> int:
    print(json.dumps(context(Path(args.cwd)), ensure_ascii=False, indent=2))
    return 0


def command_inventory(args: argparse.Namespace) -> int:
    repos = (
        [Path(args.repo).resolve()]
        if args.repo
        else discover_base_repos(Path(args.root).expanduser().resolve())
    )
    inventories: list[dict[str, Any]] = []
    errors = []
    for repo in repos:
        try:
            inventories.append(repo_inventory(repo, args.base, args.github))
        except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
            errors.append({"repo": str(repo), "error": str(exc)})
    if args.format == "markdown":
        print(render_markdown(inventories))
        if errors:
            print("\nErros:")
            for error in errors:
                print(f"- `{error['repo']}`: {error['error']}")
    else:
        print(
            json.dumps({"inventories": inventories, "errors": errors}, ensure_ascii=False, indent=2)
        )
    return 1 if errors else 0


def command_assess(args: argparse.Namespace) -> int:
    repo = base_checkout(Path(args.repo).expanduser().resolve())
    target = Path(args.worktree).expanduser().resolve()
    match = next(
        (entry for entry in parse_worktrees(repo) if Path(entry["worktree"]).resolve() == target),
        None,
    )
    if not match:
        raise ValueError(f"worktree não registrada em {repo}: {target}")
    branch_ref = match.get("branch")
    branch = branch_ref.removeprefix("refs/heads/") if branch_ref else None
    github_by_branch, github_error = (
        fetch_github_prs(repo, branch) if args.github and branch else (None, None)
    )
    print(
        json.dumps(
            assess_entry(repo, match, args.base, github_by_branch, github_error),
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


def command_create(args: argparse.Namespace) -> int:
    repo = base_checkout(Path(args.repo).expanduser().resolve())
    if not re.fullmatch(r"[a-z0-9][a-z0-9._-]*", args.slug):
        raise ValueError("slug inválido; use minúsculas, números, ponto, hífen ou underscore")
    if git(repo, "rev-parse", "--verify", args.base).returncode != 0:
        raise ValueError(f"base não encontrada localmente: {args.base}")
    branch = args.branch or f"codex/{args.slug}"
    target = Path(args.root).expanduser().resolve() / repo.name / args.slug
    command = ["git", "-C", str(repo), "worktree", "add", "-b", branch, str(target), args.base]
    print(
        json.dumps(
            {
                "execute": args.execute,
                "repo": str(repo),
                "base": args.base,
                "branch": branch,
                "target": str(target),
                "command": command,
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    if not args.execute:
        return 0
    if target.exists():
        raise ValueError(f"destino já existe: {target}")
    if git(repo, "show-ref", "--verify", f"refs/heads/{branch}").returncode == 0:
        raise ValueError(f"branch local já existe: {branch}")
    target.parent.mkdir(parents=True, exist_ok=True)
    result = run(command, timeout=60)
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        return result.returncode
    sys.stdout.write(result.stdout)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    context_parser = sub.add_parser("context", help="mostra o contexto do checkout atual")
    context_parser.add_argument("--cwd", default=os.getcwd())
    context_parser.set_defaults(func=command_context)

    inventory_parser = sub.add_parser("inventory", help="audita worktrees sem modificar Git")
    source = inventory_parser.add_mutually_exclusive_group()
    source.add_argument("--root", default=str(Path.home() / "Documents" / "GitHub"))
    source.add_argument("--repo")
    inventory_parser.add_argument("--base", default="origin/main")
    inventory_parser.add_argument("--format", choices=("json", "markdown"), default="markdown")
    inventory_parser.add_argument(
        "--github", action="store_true", help="consulta PRs via gh; sem mutações"
    )
    inventory_parser.set_defaults(func=command_inventory)

    assess_parser = sub.add_parser("assess", help="avalia uma worktree registrada")
    assess_parser.add_argument("--repo", required=True)
    assess_parser.add_argument("--worktree", required=True)
    assess_parser.add_argument("--base", default="origin/main")
    assess_parser.add_argument(
        "--github", action="store_true", help="reconcilia branch com PRs via gh"
    )
    assess_parser.set_defaults(func=command_assess)

    create_parser = sub.add_parser("create", help="planeja ou cria uma worktree manual")
    create_parser.add_argument("--repo", required=True)
    create_parser.add_argument("--slug", required=True)
    create_parser.add_argument("--base", default="origin/main")
    create_parser.add_argument("--branch")
    create_parser.add_argument(
        "--root", default=str(Path.home() / ".codex" / "worktrees" / "manual")
    )
    create_parser.add_argument("--execute", action="store_true")
    create_parser.set_defaults(func=command_create)
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.func(args)
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
        parser.error(str(exc))
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
