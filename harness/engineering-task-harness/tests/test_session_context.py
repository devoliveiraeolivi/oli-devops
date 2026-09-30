from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "session_context.py"
SPEC = importlib.util.spec_from_file_location("session_context", SCRIPT)
assert SPEC and SPEC.loader
SESSION = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SESSION)


def command(*args: str) -> None:
    subprocess.run(args, check=True, capture_output=True, text=True)


def run_hook(cwd: Path) -> str:
    payload = json.dumps({"hook_event_name": "SessionStart", "source": "startup", "cwd": str(cwd)})
    result = subprocess.run(
        [sys.executable, str(SCRIPT)], input=payload, capture_output=True, text=True, check=True
    )
    return result.stdout.strip()


class SessionContextTest(unittest.TestCase):
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

    def test_identifies_claude_managed_worktree(self) -> None:
        worktree = self.root / "repo-claude" / ".claude" / "worktrees" / "feature"
        command(
            "git", "-C", str(self.repo), "worktree", "add", "-b", "feature", str(worktree), "main"
        )
        self.assertEqual(SESSION.worktree_kind(worktree.resolve()), "claude-managed")

    def test_worktree_kind_matches_task_harness(self) -> None:
        # Cópia deliberada: o hook roda em /usr/bin/python3 (3.9) e task_harness exige 3.11+.
        spec = importlib.util.spec_from_file_location(
            "task_harness", SCRIPT.parent / "task_harness.py"
        )
        assert spec and spec.loader
        harness = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(harness)
        codex_home = self.root / "codex-home"
        paths = {
            "base": self.repo,
            "claude": self.root / "repo-claude" / ".claude" / "worktrees" / "a",
            "codex": codex_home / "worktrees" / "1a2b" / "repo",
            "linked": self.root / "linked",
        }
        for name, path in paths.items():
            if name != "base":
                command(
                    "git", "-C", str(self.repo), "worktree", "add", "-b", name, str(path), "main"
                )
        with unittest.mock.patch.dict("os.environ", {"CODEX_HOME": str(codex_home)}):
            for name, path in paths.items():
                with self.subTest(name=name):
                    self.assertEqual(
                        SESSION.worktree_kind(path.resolve()),
                        harness.worktree_kind(path.resolve()),
                    )

    def test_emits_context_with_skill_and_premise_gate(self) -> None:
        output = json.loads(run_hook(self.repo))["hookSpecificOutput"]
        self.assertEqual(output["hookEventName"], "SessionStart")
        context = output["additionalContext"]
        self.assertIn("engineering-task-harness", context)
        self.assertIn("tipo=base-checkout", context)
        self.assertIn("arquivo:linha", context)
        # Reinjetado após cada compactação: a decisão registrada não se perde no resumo.
        self.assertIn("fora dela, pare e pergunte", context)

    def test_silent_outside_git(self) -> None:
        outside = self.root / "plain"
        outside.mkdir()
        self.assertEqual(run_hook(outside), "")


if __name__ == "__main__":
    unittest.main()
