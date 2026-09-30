from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "git_targets.py"
SPEC = importlib.util.spec_from_file_location("git_targets", SCRIPT)
assert SPEC and SPEC.loader
TARGETS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TARGETS)

Target = tuple[str, str, bool, list[str], bool]


def targets(command: str, cwd: str = "/work/repo") -> list[Target]:
    return list(TARGETS.targets(command, cwd))


def sources(command: str) -> list[str]:
    [(_, _, _, refs, _)] = targets(command)
    return refs


def directory(command: str) -> str:
    [(_, target, _, _, _)] = targets(command)
    return target


class GitTargetsTest(unittest.TestCase):
    def test_plain_push_sends_head_from_event_cwd(self) -> None:
        self.assertEqual(targets("git push"), [("push", "/work/repo", False, ["HEAD"], False)])

    def test_commit_targets_head(self) -> None:
        self.assertEqual(
            targets("git commit -m x"), [("commit", "/work/repo", False, ["HEAD"], False)]
        )

    def test_directory_follows_cd_git_c_and_env(self) -> None:
        self.assertEqual(directory("cd /work/wt && git push origin feat"), "/work/wt")
        self.assertEqual(directory("cd ../wt && git -C sub commit -m x"), "/work/wt/sub")
        self.assertEqual(directory("git -c a.b=c --no-pager -C /other push"), "/other")
        self.assertEqual(directory("env -C /other git push"), "/other")
        self.assertEqual(directory("env --chdir=/other git push"), "/other")
        self.assertEqual(directory("cd -P /other && git push"), "/other")
        self.assertEqual(directory("(cd /other && git push)"), "/other")

    def test_subshell_scopes_cd(self) -> None:
        self.assertEqual(directory("cd /other && (git push)"), "/other")
        self.assertEqual(directory("(cd /other) && git push"), "/work/repo")
        self.assertEqual(
            [t.directory for t in targets("(cd /other && git push); git push")],
            ["/other", "/work/repo"],
        )
        self.assertEqual(sources("git push origin $(git branch --show-current)"), [":unknown"])

    def test_unresolvable_directory_is_not_a_target(self) -> None:
        self.assertEqual(targets('cd "$REPO" && git push'), [])
        self.assertEqual(targets('for r in /a; do git -C "$r" push; done'), [])

    def test_gate_marker_only_as_leading_assignment(self) -> None:
        self.assertTrue(targets("cd /work/wt && HARNESS_GATE_OK=1 git push")[0][2])
        self.assertTrue(targets("env HARNESS_GATE_OK=1 git push")[0][2])
        self.assertEqual(
            [t[2] for t in targets('git commit -m "HARNESS_GATE_OK=1" && git push')], [False, False]
        )

    def test_wrappers_and_keywords(self) -> None:
        for command in (
            "env FOO=bar git push",
            "command git push",
            "timeout 300 git push",
            "if true; then git push; fi",
            "for r in a b; do git push; done",
        ):
            with self.subTest(command=command):
                self.assertEqual(sources(command), ["HEAD"])

    def test_redirections_and_comments_are_not_refspecs(self) -> None:
        self.assertEqual(sources("git push 2>&1"), ["HEAD"])
        self.assertEqual(sources("git push -u origin HEAD 2>&1 | tail -5"), ["HEAD"])
        self.assertEqual(sources("git push &>/dev/null"), ["HEAD"])
        self.assertEqual(sources("git push origin feat/x > push.log 2>/dev/null"), ["feat/x"])
        self.assertEqual(sources("git push origin feat/x # retry"), ["feat/x"])

    def test_comment_lines_and_heredoc_bodies_are_not_parsed(self) -> None:
        self.assertEqual(sources("# push the branch (it's new)\ngit push -u origin HEAD"), ["HEAD"])
        self.assertEqual(targets("cat > NOTES.md <<'EOF'\ngit push origin v9\nEOF"), [])
        self.assertEqual(sources("cat > N.md <<'EOF'\nIt's done\nEOF\ngit push"), ["HEAD"])

    def test_push_refspec_sources(self) -> None:
        self.assertEqual(sources("git push -u origin feat/x"), ["feat/x"])
        self.assertEqual(
            sources("git push origin HEAD:refs/heads/main +feat/y:feat/y"), ["HEAD", "feat/y"]
        )
        self.assertEqual(sources("git push -o ci.skip origin feat/x --force-with-lease"), ["feat/x"])
        self.assertEqual(sources("git push --recurse-submodules on-demand origin feat/x"), ["feat/x"])
        self.assertEqual(sources("git push origin tag v1"), ["refs/tags/v1"])
        self.assertEqual(sources("git push origin"), ["HEAD"])

    def test_unknown_and_multi_sources(self) -> None:
        self.assertEqual(sources('git push -u origin "$(git branch --show-current)"'), [":unknown"])
        self.assertEqual(sources('git push origin "$BRANCH"'), [":unknown"])
        self.assertEqual(sources("git push --tags origin"), [":multi"])
        self.assertEqual(sources("git push --all"), [":multi"])
        self.assertEqual(sources("git push origin 'refs/heads/*:refs/heads/*'"), [":multi"])
        self.assertEqual(sources("git push origin :"), [":multi"])

    def test_deletions_send_nothing(self) -> None:
        self.assertEqual(sources("git push origin :old"), [])
        self.assertEqual(sources("git push origin --delete old"), [])
        self.assertEqual(sources("git push -d origin old"), [])

    def test_branch_switch_earlier_in_the_command(self) -> None:
        [push] = targets("git checkout -b feat/new && git push -u origin feat/new")
        self.assertTrue(push[4])
        [commit] = targets("git switch -c feat/next main && git commit -m x")
        self.assertTrue(commit[4])
        [after_restore] = targets("git checkout -- a.txt && git commit -m x")
        self.assertFalse(after_restore[4])

    def test_dry_run_is_not_a_push(self) -> None:
        self.assertEqual(targets("git push --dry-run origin feat"), [])
        self.assertEqual(targets("git push -n"), [])

    def test_mentions_are_not_targets(self) -> None:
        self.assertEqual(targets("echo git push"), [])
        self.assertEqual(targets("git commit-tree HEAD"), [])
        self.assertEqual(targets("git pushy"), [])

    def test_env_prefix_is_skipped(self) -> None:
        self.assertEqual(sources("FOO='a b' git push"), ["HEAD"])

    def test_untokenizable_command_has_no_targets(self) -> None:
        self.assertEqual(targets('git push "'), [])


if __name__ == "__main__":
    unittest.main()
