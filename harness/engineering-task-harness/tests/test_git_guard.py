from __future__ import annotations

import importlib.util
import tempfile
import unittest
import unittest.mock
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

    def test_allows_pattern_inside_quoted_commit_message(self) -> None:
        command = 'git commit -m "docs: nunca use git branch -D sem auditar"'
        self.assertIsNone(GUARD.block_reason(command))

    def test_allows_pattern_inside_quoted_search(self) -> None:
        self.assertIsNone(GUARD.block_reason('grep -n "git worktree remove" SKILL.md'))

    def test_allows_pattern_inside_heredoc_body(self) -> None:
        command = "cat > notas.md <<'EOF'\nNunca rode git worktree remove sem auditar.\nEOF"
        self.assertIsNone(GUARD.block_reason(command))

    def test_blocks_rm_with_separate_flags(self) -> None:
        self.assertIsNotNone(GUARD.block_reason("rm -r -f /Users/me/Documents/GitHub/repo-wt"))

    def test_blocks_short_remote_delete(self) -> None:
        self.assertIsNotNone(GUARD.block_reason("git push -d origin codex/old"))

    def test_blocks_command_after_quoted_argument(self) -> None:
        command = 'git commit -m "wip" && git branch -D codex/old'
        self.assertIsNotNone(GUARD.block_reason(command))

    def test_blocks_through_xargs(self) -> None:
        self.assertIsNotNone(GUARD.block_reason("git branch --merged | xargs git branch -D"))

    def test_blocks_inside_shell_payload(self) -> None:
        self.assertIsNotNone(GUARD.block_reason('bash -lc "git worktree remove /repo-wt"'))

    def test_blocks_on_next_line(self) -> None:
        self.assertIsNotNone(GUARD.block_reason("cd /repo\ngit worktree prune"))

    def test_unbalanced_quotes_fall_back_to_raw_text(self) -> None:
        self.assertIsNotNone(GUARD.block_reason('git branch -D codex/old "'))

    def test_blocks_heredoc_fed_to_shell(self) -> None:
        self.assertIsNotNone(GUARD.block_reason("bash <<'EOF'\ngit worktree prune\nEOF"))

    def test_blocks_quoted_command_sent_over_ssh(self) -> None:
        self.assertIsNotNone(GUARD.block_reason('ssh host "git branch -D codex/old"'))

    def test_blocks_text_piped_into_shell(self) -> None:
        self.assertIsNotNone(GUARD.block_reason('echo "git worktree prune" | sh'))

    def test_blocks_interpreter_payload(self) -> None:
        command = "python3 -c \"import os; os.system('git branch -D codex/old')\""
        self.assertIsNotNone(GUARD.block_reason(command))

    def test_blocks_line_continuation(self) -> None:
        self.assertIsNotNone(GUARD.block_reason("git worktree \\\nremove /repo-wt"))

    def test_blocks_remote_delete_by_empty_refspec(self) -> None:
        self.assertIsNotNone(GUARD.block_reason("git push origin :codex/old"))

    def test_allows_push_with_refspec(self) -> None:
        self.assertIsNone(GUARD.block_reason("git push origin HEAD:main"))

    def test_allows_pattern_in_commit_all_message(self) -> None:
        self.assertIsNone(GUARD.block_reason('git commit -am "nunca git branch -D"'))

    def test_allows_pattern_in_pr_body(self) -> None:
        command = 'gh pr create --title "x" --body "rode git worktree remove depois"'
        self.assertIsNone(GUARD.block_reason(command))

    def test_allows_pattern_in_commit_message_heredoc(self) -> None:
        command = "git commit -m \"$(cat <<'EOF'\nnunca git branch -D\nEOF\n)\""
        self.assertIsNone(GUARD.block_reason(command))

    def test_bypass_in_comment_does_not_apply(self) -> None:
        command = "git branch -D codex/old # ENGINEERING_HARNESS_ALLOW_RAW_GIT_CLEANUP=1"
        self.assertIsNotNone(GUARD.block_reason(command))

    def test_bypass_in_quoted_message_does_not_apply(self) -> None:
        command = (
            'git commit -m "ENGINEERING_HARNESS_ALLOW_RAW_GIT_CLEANUP=1" && git branch -D codex/old'
        )
        self.assertIsNotNone(GUARD.block_reason(command))

    def test_bypass_applies_only_to_its_own_command(self) -> None:
        command = "ENGINEERING_HARNESS_ALLOW_RAW_GIT_CLEANUP=1 true && git branch -D codex/old"
        self.assertIsNotNone(GUARD.block_reason(command))

    def test_bypass_after_cd_applies_to_its_command(self) -> None:
        command = (
            "cd /repo && ENGINEERING_HARNESS_ALLOW_RAW_GIT_CLEANUP=1 git worktree remove /repo-wt"
        )
        self.assertIsNone(GUARD.block_reason(command))

    def test_blocks_forced_empty_refspec_delete(self) -> None:
        self.assertIsNotNone(GUARD.block_reason("git push origin +:codex/old"))

    def test_blocks_rm_of_protected_root_itself(self) -> None:
        self.assertIsNotNone(GUARD.block_reason("rm -rf /Users/me/Documents/GitHub"))
        self.assertIsNotNone(GUARD.block_reason("rm -rf ~/.codex/worktrees"))

    def test_allows_rm_of_similarly_named_dir(self) -> None:
        self.assertIsNone(GUARD.block_reason("rm -rf /Users/me/Documents/GitHubBackup"))

    def test_blocks_substitution_inside_data_argument(self) -> None:
        self.assertIsNotNone(GUARD.block_reason('git commit -m "$(git branch -D codex/old)"'))
        self.assertIsNotNone(GUARD.block_reason('grep -n "`git worktree prune`" notas.md'))

    def test_blocks_prune_and_mirror_push(self) -> None:
        self.assertIsNotNone(GUARD.block_reason("git push --prune origin 'refs/heads/*:refs/heads/*'"))
        self.assertIsNotNone(GUARD.block_reason("git push --mirror backup"))

    def test_blocks_forced_branch_delete_after_other_options(self) -> None:
        self.assertIsNotNone(GUARD.block_reason("git branch --merged main -D old"))
        self.assertIsNone(GUARD.block_reason("git branch --merged main"))

    def test_allows_safe_branch_delete(self) -> None:
        # `-d` só apaga branch já mergeada: o próprio git recusa o resto.
        for command in (
            "git branch -d feat/x",
            "git branch --merged main -d old",
            "git branch --merged | xargs git branch -d",
            "git -C /repo branch --delete feat/x",
        ):
            with self.subTest(command=command):
                self.assertIsNone(GUARD.block_reason(command))

    def test_blocks_every_forced_branch_delete_form(self) -> None:
        for command in (
            "git branch -D feat/x",
            "git branch -d -f feat/x",
            "git branch -df feat/x",
            "git branch --delete --force feat/x",
            "git branch -qD feat/x",
        ):
            with self.subTest(command=command):
                self.assertIsNotNone(GUARD.block_reason(command))

    def test_unquoted_heredoc_substitution_executes(self) -> None:
        self.assertIsNotNone(GUARD.block_reason("cat > n.md <<EOF\n$(git branch -D old)\nEOF"))
        self.assertIsNone(GUARD.block_reason("cat > n.md <<EOF\nnunca git branch -D\nEOF"))

    def test_removal_resolved_against_cwd(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp).resolve() / "Documents" / "GitHub"
            repo, sibling = base / "repo", base / "repo-wt"
            (repo / ".git").mkdir(parents=True)
            (repo / "build").mkdir()
            sibling.mkdir()
            (sibling / ".git").write_text("gitdir: x\n", encoding="utf-8")
            self.assertIsNotNone(GUARD.block_reason("rm -rf ../repo-wt", str(repo)))
            self.assertIsNotNone(GUARD.block_reason("rm -rf .", str(repo)))
            self.assertIsNone(GUARD.block_reason("rm -rf build", str(repo)))
            with unittest.mock.patch.dict("os.environ", {"HOME": temp}):
                self.assertIsNotNone(GUARD.block_reason("rm -rf ~/Documents", temp))
            outside = Path(temp).resolve() / "scratch-repo"
            (outside / ".git").mkdir(parents=True)
            self.assertIsNone(GUARD.block_reason(f"rm -rf {outside}", temp))

    def test_allows_docker_rm_flag(self) -> None:
        command = "docker run --rm -v /Users/me/Documents/GitHub/repo:/w img"
        self.assertIsNone(GUARD.block_reason(command))

    # "Git" em texto livre não casa; em dado, só a substituição de comando é analisada.
    def test_allows_git_words_in_pr_body_and_commit_message(self) -> None:
        for command in (
            "gh pr create --title t --body 'O `git_guard` bloqueava Git push --delete e "
            "git worktree remove'",
            "git commit -m 'docs: o `git_guard` cita git branch -D'",
            "gh pr create --title t --body 'Corrige o guard (falso positivo): `git_guard` e "
            "git push --delete'",
            "gh pr create --title t --body-file - <<'EOF'\n"
            "Git: rode Git worktree remove e Git push origin --delete x depois\nEOF",
            "git commit -F - <<'EOF'\nfix: Git branch -D bloqueado\nEOF",
        ):
            with self.subTest(command=command):
                self.assertIsNone(GUARD.block_reason(command))

    def test_allows_git_words_in_printed_text(self) -> None:
        for command in (
            'echo "Git push --delete feito"',
            "printf '%s\\n' 'Git worktree prune roda depois'",
            "echo 'Git push --delete feito",  # aspas desbalanceadas: texto cru
        ):
            with self.subTest(command=command):
                self.assertIsNone(GUARD.block_reason(command))

    def test_blocks_git_invocation_in_any_position(self) -> None:
        for command in (
            "git -C /repo worktree remove /repo-wt",
            "/usr/bin/git branch -D codex/old",
            "find . -name x -exec git branch -D {} \\;",
            "timeout 5 git push origin --delete codex/old",
            "echo `git worktree prune`",
        ):
            with self.subTest(command=command):
                self.assertIsNotNone(GUARD.block_reason(command))

    def test_blocks_nested_substitution_inside_data_argument(self) -> None:
        for command in (
            'git commit -m "$(git branch -D x; (true))"',
            'git commit -m "texto $(git worktree prune && echo $(date))"',
            'git commit -m "$(git push origin --delete $(git branch --show-current))"',
            "git commit -F - <<EOF\n$(git branch -D \"$(echo old)\")\nEOF",
            "git push origin :topic=old",
            # `)` entre aspas ou em `case` fecha a regex cedo; crase escapada aninha.
            "git commit -m \"$(echo ')' ; git branch -D x)\"",
            'git commit -m "$(echo \\"a)b\\"; git worktree prune)"',
            "git commit -m \"$(true) $(echo ')'; git push origin --delete x)\"",
            'git commit -m "$(case x in x) git branch -D x;; esac)"',
            'git commit -m "`echo \\`git branch -D old\\``"',
            'git commit -m "$(git worktree prune"',
        ):
            with self.subTest(command=command):
                self.assertIsNotNone(GUARD.block_reason(command))

    def test_blocks_git_command_held_in_value(self) -> None:
        for command in (
            'X="git worktree prune"; $X',
            'git rebase --exec="git branch -D x" main',
            "git -c alias.limpa='worktree prune' limpa",
            "git -c alias.limpa='!git branch -D old' limpa",
        ):
            with self.subTest(command=command):
                self.assertIsNotNone(GUARD.block_reason(command))

    def test_blocks_heredoc_executed_by_gh_or_git(self) -> None:
        for command in (
            "git -c alias.roda='!sh' roda <<'EOF'\ngit worktree prune\nEOF",
            "gh codespace ssh -c cs <<'EOF'\ngit worktree prune\nEOF",
        ):
            with self.subTest(command=command):
                self.assertIsNotNone(GUARD.block_reason(command))

    def test_allows_redirection_in_data_heredoc(self) -> None:
        for command in (
            "cat > n.md 2>&1 <<'EOF'\nnunca git branch -D\nEOF",
            "cat >&2 <<'EOF'\nnunca git worktree prune\nEOF",
        ):
            with self.subTest(command=command):
                self.assertIsNone(GUARD.block_reason(command))

    def test_blocks_shell_heredoc_after_data_heredoc_command(self) -> None:
        for command in (
            "cat x; bash <<'EOF'\ngit worktree prune\nEOF",
            "git status && bash <<'EOF'\ngit worktree prune\nEOF",
            "cat x & bash <<'EOF'\ngit worktree prune\nEOF",
            "git-shell <<'EOF'\ngit worktree prune\nEOF",
        ):
            with self.subTest(command=command):
                self.assertIsNotNone(GUARD.block_reason(command))


if __name__ == "__main__":
    unittest.main()
