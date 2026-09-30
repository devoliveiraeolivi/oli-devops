from __future__ import annotations

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "task_harness.py"
SPEC = importlib.util.spec_from_file_location("task_harness", SCRIPT)
assert SPEC and SPEC.loader
HARNESS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HARNESS)


def command(*args: str) -> None:
    subprocess.run(args, check=True, capture_output=True, text=True)


class TaskHarnessTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        command("git", "init", "-b", "main", str(self.repo))
        command("git", "-C", str(self.repo), "config", "user.name", "Harness Test")
        command("git", "-C", str(self.repo), "config", "user.email", "harness@example.invalid")
        (self.repo / "README.md").write_text("base\n", encoding="utf-8")
        command("git", "-C", str(self.repo), "add", "README.md")
        command("git", "-C", str(self.repo), "commit", "-m", "base")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_context_identifies_base_checkout(self) -> None:
        result = HARNESS.context(self.repo)
        self.assertEqual(result["kind"], "base-checkout")
        self.assertEqual(result["dirty_count"], 0)
        self.assertEqual(result["branch"], "main")

    def test_dirty_linked_worktree_is_preserved(self) -> None:
        worktree = self.root / "feature"
        command(
            "git", "-C", str(self.repo), "worktree", "add", "-b", "feature", str(worktree), "main"
        )
        (worktree / "local.txt").write_text("untracked\n", encoding="utf-8")
        inventory = HARNESS.repo_inventory(self.repo, "main")
        item = next(
            item for item in inventory["worktrees"] if item["path"] == str(worktree.resolve())
        )
        self.assertEqual(item["classification"], "PRESERVAR_DIRTY")
        self.assertEqual(item["dirty_count"], 1)

    def test_merged_clean_worktree_is_only_a_candidate(self) -> None:
        worktree = self.root / "feature"
        command(
            "git", "-C", str(self.repo), "worktree", "add", "-b", "feature", str(worktree), "main"
        )
        (worktree / "feature.txt").write_text("feature\n", encoding="utf-8")
        command("git", "-C", str(worktree), "add", "feature.txt")
        command("git", "-C", str(worktree), "commit", "-m", "feature")
        command("git", "-C", str(self.repo), "merge", "--ff-only", "feature")
        inventory = HARNESS.repo_inventory(self.repo, "main")
        item = next(
            item for item in inventory["worktrees"] if item["path"] == str(worktree.resolve())
        )
        self.assertEqual(item["classification"], "CANDIDATA_MERGEADA")
        self.assertTrue(item["head_merged_in_base"])

    def test_open_pr_preserves_worktree_even_if_locally_merged(self) -> None:
        classification = HARNESS.classify_with_github(
            "CANDIDATA_MERGEADA",
            [{"number": 10, "state": "OPEN", "mergedAt": None}],
        )
        self.assertEqual(classification, "PRESERVAR_PR_ABERTO")

    def test_merged_pr_without_ancestry_requires_equivalence_review(self) -> None:
        classification = HARNESS.classify_with_github(
            "REVISAR_NAO_MERGEADO",
            [{"number": 11, "state": "MERGED", "mergedAt": "2026-08-25T00:00:00Z"}],
        )
        self.assertEqual(classification, "REVISAR_MERGE_GITHUB_NAO_ANCESTRAL")


if __name__ == "__main__":
    unittest.main()
