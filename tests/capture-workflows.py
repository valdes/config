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
elif name == "wl-paste":
    print(os.environ.get("CLIP_CONTENT", "Shared note"), end="")
elif name == "zbarimg":
    sys.stdin.read()
    print(os.environ.get("QR_VALUE", "otpauth://example"))
elif name == "file":
    print(os.environ.get("MIME_TYPE", "image/png"))
elif name in ("magick", "ffmpeg"):
    Path(args[-1]).write_bytes(b"converted")
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
        for name in ["bash", "flock", "mkdir", "date", "readlink", "mktemp", "rm", "dirname", "basename", "sed"]:
            (commands / name).symlink_to(shutil.which(name))
        for name in ["slurp", "grim", "tesseract", "wl-copy", "wl-paste", "zbarimg",
                     "notify-send", "systemctl", "systemd-run", "wf-recorder",
                     "xdg-user-dir", "voxtype", "localsend", "magick", "ffmpeg", "file"]:
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

    def test_qr_capture_is_sensitive_and_preserves_clipboard_on_failure(self):
        self.assertEqual(self.run_script("capture-qr").returncode, 0)
        self.assertEqual(self.clipboard.read_text(), "otpauth://example")
        self.assertIn("--sensitive", self.calls("wl-copy")[0])
        self.clipboard.write_text("original clipboard")
        for env in [{"FAIL_COMMAND": "slurp"}, {"SELECTION": ""},
                    {"FAIL_COMMAND": "zbarimg"}, {"QR_VALUE": ""}]:
            with self.subTest(env=env):
                self.run_script("capture-qr", **env)
                self.assertEqual(self.clipboard.read_text(), "original clipboard")

    def test_nearby_sharing_uses_explicit_paths_and_runtime_clipboard_file(self):
        document = self.root / "document.txt"
        document.write_text("Hello")
        self.assertEqual(self.run_script("share-nearby", "file", str(document)).returncode, 0)
        self.assertEqual(self.calls("localsend")[-1], ["localsend", "--headless", "send", str(document)])
        self.assertEqual(self.run_script("share-nearby", "clipboard").returncode, 0)
        shared_file = Path(self.calls("localsend")[-1][-1])
        self.assertEqual(shared_file.read_text(), "Shared note")
        self.assertEqual(self.run_script("share-nearby", "file", str(self.root / "missing")).returncode, 1)
        self.assertEqual(len(self.calls("localsend")), 2)

    def test_reminders_use_owned_timers(self):
        result = self.run_script("remind", "15", "Check", "build")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--on-active=15m", self.calls("systemd-run")[0])
        self.assertTrue(any(part.startswith("--unit=desktop-remind-") for part in self.calls("systemd-run")[0]))
        shown = self.run_script("remind", "show")
        self.assertIn("Check build", shown.stdout)
        self.assertEqual(self.run_script("remind", "clear").returncode, 0)
        self.assertTrue(any(".timer" in " ".join(call) for call in self.calls("systemctl")))
        self.assertEqual(self.run_script("remind", "0", "invalid").returncode, 2)
        self.assertEqual(self.run_script("remind", "08", "invalid").returncode, 2)
        self.assertEqual(self.run_script("remind", "10081", "invalid").returncode, 2)

    def test_transcode_refuses_overwrite_and_selects_format(self):
        image = self.root / "photo.png"
        image.write_bytes(b"image")
        result = self.run_script("transcode-media", str(image), "jpg", "medium")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / "photo-medium.jpg").exists())
        self.assertIn("2160x>", self.calls("magick")[0])
        self.assertEqual(self.run_script("transcode-media", str(image), "jpg", "medium").returncode, 1)
        video = self.root / "demo.mkv"
        video.write_bytes(b"video")
        result = self.run_script("transcode-media", str(video), "mp4", "720p", MIME_TYPE="video/x-matroska")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / "demo-720p.mp4").exists())
        self.assertIn("-n", self.calls("ffmpeg")[0])

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
