"""Exercise the Herdr dev layout without starting agents or Herdr."""
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
elif name == "mise" and args[:1] == ["which"]:
    sys.exit(0 if os.environ.get("MISE_HAS_HUNK") else 1)
'''
REAL = ["bash", "jq", "basename"]
MOCKS = ["herdr", "hunk", "watchexec", "mise"]


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
        for name in ["HERDR_PANE_ID", "HERDR_TAB_ID", "MISE_HAS_HUNK"]:
            self.env.pop(name, None)

    def without(self, *names):
        for name in names:
            (self.commands / name).unlink()

    def run_script(self, name, *args, **env):
        return subprocess.run([str(ROOT / "bin" / name), *args],
                              env=dict(self.env, **env), capture_output=True, text=True,
                              timeout=10, cwd=self.root)

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


if __name__ == "__main__":
    unittest.main()
