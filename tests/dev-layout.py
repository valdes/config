"""Exercise the Herdr dev layout, worktree, and agent notification helpers without Herdr."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MOCK = '''
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
root = Path(os.environ["TEST_ROOT"])
with (root / "calls").open("a") as log:
    log.write(json.dumps([name, *args]) + "\\n")
if name == "herdr" and args[:2] == ["pane", "split"]:
    counter = root / "splits"
    count = int(counter.read_text()) + 1 if counter.exists() else 1
    counter.write_text(str(count))
    print(json.dumps({"result": {"pane": {"pane_id": f"p{count}"}}}))
elif name == "herdr" and args[:2] == ["worktree", "create"]:
    print(json.dumps({"result": {"root_pane": {"pane_id": "w9:p1"}}}))
elif name == "mise" and args[:1] == ["which"]:
    sys.exit(0 if os.environ.get("MISE_HAS_HUNK") else 1)
'''
REAL = ["bash", "jq", "basename", "cat", "git"]
MOCKS = ["herdr", "hunk", "watchexec", "mise", "notify-send"]


class DevLayout(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.commands = self.root / "bin"
        self.commands.mkdir()
        for name in REAL:
            (self.commands / name).symlink_to(shutil.which(name))
        for name in MOCKS:
            path = self.commands / name
            path.write_text(f"#!{sys.executable}\n" + MOCK)
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.commands), TEST_ROOT=str(self.root))
        for name in ["HERDR_PANE_ID", "HERDR_TAB_ID", "HERDR_WORKSPACE_ID", "MISE_HAS_HUNK"]:
            self.env.pop(name, None)

    def without(self, *names):
        for name in names:
            (self.commands / name).unlink()

    def run_script(self, name, *args, stdin="", cwd=None, **env):
        return subprocess.run([str(ROOT / "bin" / name), *args], input=stdin,
                              env=dict(self.env, **env), capture_output=True, text=True,
                              timeout=10, cwd=cwd or self.root)

    def git_repo(self):
        repo = self.root / "repo"
        repo.mkdir()
        git = ["git", "-c", "user.name=t", "-c", "user.email=t@t", "-C", str(repo)]
        subprocess.run([*git, "init", "-q", "-b", "main"], check=True)
        subprocess.run([*git, "commit", "-q", "--allow-empty", "-m", "init"], check=True)
        return repo

    def calls(self, name):
        path = self.root / "calls"
        return [x for line in path.read_text().splitlines()
                if (x := json.loads(line))[0] == name] if path.exists() else []

    def test_dev_layout_requires_herdr(self):
        self.assertEqual(self.run_script("dev-layout").returncode, 1)
        self.assertEqual(self.calls("herdr"), [])

    def test_dev_layout_splits_agent_diff_and_shell(self):
        result = self.run_script("dev-layout", HERDR_PANE_ID="p0", HERDR_TAB_ID="t0")
        self.assertEqual(result.returncode, 0, result.stderr)
        herdr = [call[1:] for call in self.calls("herdr")]
        self.assertEqual(herdr[0], ["tab", "rename", "t0", self.root.name])
        self.assertEqual(herdr[1][:7], ["pane", "split", "p0", "--direction", "right", "--ratio", "0.55"])
        self.assertEqual(herdr[2][:7], ["pane", "split", "p1", "--direction", "down", "--ratio", "0.7"])
        self.assertIn("--no-focus", herdr[1])
        self.assertEqual(herdr[3], ["pane", "run", "p1", "hunk diff --watch"])
        self.assertEqual(herdr[4], ["pane", "run", "p0", "codex"])

    def test_dev_layout_diff_falls_back_to_mise_then_watchexec(self):
        self.without("hunk")
        self.run_script("dev-layout", HERDR_PANE_ID="p0", MISE_HAS_HUNK="1")
        self.assertIn("mise exec aqua:modem-dev/hunk -- hunk diff --watch", self.calls("herdr")[2])
        self.run_script("dev-layout", "claude", HERDR_PANE_ID="p0")
        runs = [call for call in self.calls("herdr") if call[1:3] == ["pane", "run"]]
        self.assertTrue(runs[-2][-1].startswith("watchexec --clear"))
        self.assertEqual(runs[-1][-1], "claude")

    def test_wt_requires_herdr(self):
        self.assertEqual(self.run_script("wt", "feature", cwd=self.git_repo()).returncode, 1)
        self.assertEqual(self.calls("herdr"), [])

    def test_wt_creates_worktree_workspace_and_runs_layout(self):
        repo = self.git_repo()
        result = self.run_script("wt", "feature/x", "claude --model opus", cwd=repo, HERDR_WORKSPACE_ID="w1")
        self.assertEqual(result.returncode, 0, result.stderr)
        herdr = [call[1:] for call in self.calls("herdr")]
        self.assertEqual(herdr[0][:6], ["worktree", "create", "--cwd", str(repo), "--branch", "feature/x"])
        self.assertIn("--focus", herdr[0])
        self.assertEqual(herdr[1], ["pane", "run", "w9:p1", "dev-layout claude\\ --model\\ opus"])

    def test_wt_rm_refuses_primary_checkout(self):
        result = self.run_script("wt", "rm", cwd=self.git_repo(), HERDR_WORKSPACE_ID="w1")
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.calls("herdr"), [])

    def test_agent_notify_reports_stop_and_approval(self):
        repo = self.git_repo()
        stop = json.dumps({"hook_event_name": "Stop", "cwd": str(repo),
                           "last_assistant_message": "All\ntests pass"})
        result = self.run_script("agent-notify", "codex", stdin=stop, HERDR_PANE_ID="w1:p2")
        self.assertEqual((result.returncode, result.stdout), (0, ""))
        approval = json.dumps({"hook_event_name": "PermissionRequest", "cwd": str(repo), "tool_name": "Bash"})
        self.run_script("agent-notify", "claude", stdin=approval)
        self.run_script("agent-notify", "claude", stdin=json.dumps({"hook_event_name": "PreToolUse"}))
        sent = [call[1:] for call in self.calls("notify-send")]
        self.assertEqual(len(sent), 2)
        self.assertIn("--urgency=normal", sent[0])
        self.assertIn("--hint=string:x-canonical-private-synchronous:agent-w1:p2", sent[0])
        self.assertEqual(sent[0][-2:], ["codex · repo (main)", "Done: All tests pass"])
        self.assertIn("--urgency=critical", sent[1])
        self.assertEqual(sent[1][-1], "Needs approval: Bash")


if __name__ == "__main__":
    unittest.main()
