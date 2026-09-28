"""Keep the keys cheatsheet complete and exercise its menu without the desktop."""
import json
import os
from pathlib import Path
import re
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
root = Path(os.environ["TEST_ROOT"])
stdin = sys.stdin.read() if name in ("fuzzel", "wl-copy") else ""
with (root / "calls").open("a") as log:
    log.write(json.dumps([name, *sys.argv[1:], stdin]) + "\\n")
if name == "fuzzel":
    rows = stdin.splitlines()
    print(next(i for i, row in enumerate(rows) if os.environ["PICK"] in row))
'''
REAL = ["bash", "awk", "sed", "xargs", "printf"]
MOCKS = ["fuzzel", "niri", "wl-copy", "notify-send"]
BIND = re.compile(r'^\s*((?:Mod|Super)\+\S+)([^{]*)\{\s*spawn')


class Keys(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        commands = self.root / "bin"
        commands.mkdir()
        for name in REAL:
            (commands / name).symlink_to(shutil.which(name))
        for name in MOCKS:
            path = commands / name
            path.write_text(f"#!{sys.executable}\n" + MOCK)
            path.chmod(0o755)
        self.env = dict(
            os.environ,
            PATH=str(commands),
            TEST_ROOT=str(self.root),
            KEYS_NIRI_CONFIG=str(ROOT / "niri/config.kdl"),
            KEYS_TMUX_CONFIG=str(ROOT / ".tmux.conf"),
            KEYS_HERDR_CONFIG=str(ROOT / "herdr/config.toml"),
            KEYS_EMACS_CONFIG=str(ROOT / ".emacs"),
            KEYS_HELPER_DIRS=str(ROOT / "bin"),
        )

    def keys(self, *args, **env):
        return subprocess.run(
            [str(ROOT / "bin/keys"), *args],
            env={**self.env, **env}, text=True, capture_output=True, check=True,
        ).stdout

    def calls(self):
        path = self.root / "calls"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def test_every_helper_has_a_summary(self):
        for script in sorted((ROOT / "bin").iterdir()):
            head = script.read_text().splitlines()[1:5]
            self.assertTrue(any(line.startswith("# summary: ") for line in head), f"{script.name} lacks '# summary: ' in lines 2-5")

    def test_every_launcher_bind_has_a_title(self):
        for line in (ROOT / "niri/config.kdl").read_text().splitlines():
            match = BIND.match(line)
            if match:
                self.assertIn("hotkey-overlay-title=", match.group(2), f"{match.group(1)} spawns without hotkey-overlay-title")

    def test_lists_every_source(self):
        output = self.keys()
        for expected in [
            "Search All Keys and Helpers",
            "focus-workspace build",
            "Split left/right",
            "ctrl+a c",
            "C-x C-k",
            "Open a git worktree",
        ]:
            self.assertIn(expected, output)

    def test_menu_runs_niri_action_with_arguments(self):
        self.keys("menu", PICK="Mod+Ctrl+T ")
        self.assertIn(["niri", "msg", "action", "spawn", "--", "foot", "-e", "btop", ""], self.calls())

    def test_menu_runs_niri_action_without_arguments(self):
        self.keys("menu", PICK="Mod+Q ")
        self.assertIn(["niri", "msg", "action", "close-window", ""], self.calls())

    def test_menu_copies_helper_name(self):
        self.keys("menu", PICK="transcode-media")
        self.assertIn(["wl-copy", "transcode-media"], self.calls())

    def test_menu_ignores_reference_only_entries(self):
        self.keys("menu", PICK="Split left/right")
        self.assertEqual([call[0] for call in self.calls()], ["fuzzel"])


if __name__ == "__main__":
    unittest.main()
