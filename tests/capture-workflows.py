"""Exercise desktop workflow failures without accessing the real desktop."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
MOCK = '''
import json, os, sys, time
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
root = Path(os.environ["TEST_ROOT"])
with (root / "calls").open("a") as log:
    log.write(json.dumps([name, *args]) + "\\n")
if name == os.environ.get("FAIL_COMMAND"):
    sys.exit(1)
if name == "slurp":
    time.sleep(float(os.environ.get("SELECT_DELAY", "0")))
    print(os.environ.get("SELECTION", "10,20 300x200"))
elif name == "grim":
    print("image")
elif name == "tesseract":
    sys.stdin.read()
    print(os.environ.get("OCR_TEXT", "Error: conexión fallida"))
elif name == "wl-copy":
    (root / "clipboard").write_text(sys.stdin.read())
elif name == "xdg-user-dir":
    print(root / "Videos with spaces")
elif name == "systemctl" and "show" in args:
    print(os.environ.get("UNIT_STATE", "inactive"))
elif name == "wf-recorder":
    Path(args[args.index("-f") + 1]).write_bytes(b"mock video")
'''


class Workflows(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        commands = self.root / "bin"
        commands.mkdir()
        for name in ["bash", "flock", "mkdir", "date", "readlink"]:
            (commands / name).symlink_to(shutil.which(name))
        for name in ["slurp", "grim", "tesseract", "wl-copy", "notify-send",
                     "systemctl", "systemd-run", "wf-recorder", "xdg-user-dir", "voxtype"]:
            path = commands / name
            path.write_text(f"#!{sys.executable}\n" + MOCK)
            path.chmod(0o755)
        self.env = dict(os.environ, PATH=str(commands), TEST_ROOT=str(self.root),
                        XDG_RUNTIME_DIR=str(self.root), XDG_DATA_HOME=str(self.root / "data"))
        self.clipboard = self.root / "clipboard"
        self.clipboard.write_text("original clipboard")

    def run_script(self, name, *args, **env):
        return subprocess.run([str(ROOT / "bin" / name), *args],
                              env=dict(self.env, **env), capture_output=True, text=True, timeout=5)

    def calls(self, name):
        path = self.root / "calls"
        return [x for line in path.read_text().splitlines()
                if (x := json.loads(line))[0] == name] if path.exists() else []

    def test_ocr_copies_bilingual_text(self):
        self.assertEqual(self.run_script("capture-text").returncode, 0)
        self.assertEqual(self.clipboard.read_text(), "Error: conexión fallida")
        self.assertIn("eng+spa", self.calls("tesseract")[0])

    def test_cancel_empty_and_failed_ocr_preserve_clipboard(self):
        for env in [{"FAIL_COMMAND": "slurp"}, {"SELECTION": ""},
                    {"OCR_TEXT": "  \t"}, {"FAIL_COMMAND": "grim"},
                    {"FAIL_COMMAND": "tesseract"}]:
            with self.subTest(env=env):
                self.run_script("capture-text", **env)
                self.assertEqual(self.clipboard.read_text(), "original clipboard")

    def test_missing_dependency_is_actionable(self):
        (self.root / "bin" / "tesseract").unlink()
        result = self.run_script("capture-text")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Missing command: tesseract", result.stderr)
        self.assertFalse(self.calls("slurp"))

    def test_record_cancel_does_not_start_service(self):
        self.assertEqual(self.run_script("capture-record", FAIL_COMMAND="slurp").returncode, 0)
        self.assertFalse(self.calls("systemd-run"))

    def test_record_start_and_stale_unit(self):
        for state in ["inactive", "failed"]:
            with self.subTest(state=state):
                self.assertEqual(self.run_script("capture-record", UNIT_STATE=state).returncode, 0)
                args = self.calls("systemd-run")[-1]
                self.assertIn("--property=KillSignal=SIGINT", args)
                self.assertIn("--unit=desktop-capture-record.service", args)
                self.assertIn("10,20 300x200", args)
                self.assertTrue(args[-1].endswith(".mp4"))

    def test_stop_targets_only_owned_unit(self):
        self.assertEqual(self.run_script("capture-record", UNIT_STATE="active").returncode, 0)
        self.assertIn(["systemctl", "--user", "stop", "desktop-capture-record.service"],
                      self.calls("systemctl"))
        self.assertFalse(self.calls("slurp"))
        self.assertFalse(self.calls("systemd-run"))

    def test_rapid_toggles_do_not_duplicate_selection(self):
        proc = subprocess.Popen([str(ROOT / "bin/capture-record")],
                                env=dict(self.env, SELECT_DELAY="0.5"),
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 3
            while not self.calls("slurp") and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(self.calls("slurp"))
            self.assertEqual(self.run_script("capture-record").returncode, 0)
            proc.communicate(timeout=5)
            self.assertEqual(proc.returncode, 0)
            self.assertEqual(len(self.calls("systemd-run")), 1)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.communicate()

    def test_record_worker_silent_video_and_failure(self):
        output = str(self.root / "video.mp4")
        self.assertEqual(self.run_script("capture-record", "--run", "10,20 300x200", output).returncode, 0)
        args = self.calls("wf-recorder")[0]
        self.assertNotIn("-a", args)
        self.assertIn("libx264", args)
        self.assertIn(["notify-send", "Recording saved", output], self.calls("notify-send"))
        result = self.run_script("capture-record", "--run", "10,20 300x200", output,
                                 FAIL_COMMAND="wf-recorder")
        self.assertEqual(result.returncode, 1)
        self.assertIn("journalctl", result.stderr)

    def test_dictation_missing_model_and_cancel(self):
        result = self.run_script("dictation")
        self.assertIn("make setup-dictation", result.stderr)
        self.assertFalse(self.calls("systemctl"))
        model = self.root / "data/voxtype/models/ggml-base.bin"
        model.parent.mkdir(parents=True)
        model.write_bytes(b"model")
        self.assertEqual(self.run_script("dictation", "cancel").returncode, 0)
        self.assertEqual(self.calls("voxtype"), [["voxtype", "record", "cancel"]])


if __name__ == "__main__":
    unittest.main()
