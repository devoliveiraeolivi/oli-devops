from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "git_guard.py"
SPEC = importlib.util.spec_from_file_location("git_guard", SCRIPT)
assert SPEC and SPEC.loader
GUARD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GUARD)


class GitGuardTest(unittest.TestCase):
    def test_blocks_worktree_remove(self) -> None:
        self.assertIsNotNone(GUARD.block_reason("git -C /repo worktree remove /repo-wt"))

    def test_blocks_branch_delete(self) -> None:
        self.assertIsNotNone(GUARD.block_reason("git branch -D codex/old"))

    def test_blocks_rm_rf_in_repository_root(self) -> None:
        self.assertIsNotNone(GUARD.block_reason("rm -rf /Users/me/Documents/GitHub/repo-wt"))

    def test_allows_read_only_git(self) -> None:
        self.assertIsNone(GUARD.block_reason("git worktree list --porcelain"))

    def test_explicit_bypass_allows_exact_invocation(self) -> None:
        command = "ENGINEERING_HARNESS_ALLOW_RAW_GIT_CLEANUP=1 git worktree remove /repo-wt"
        self.assertIsNone(GUARD.block_reason(command))


if __name__ == "__main__":
    unittest.main()
