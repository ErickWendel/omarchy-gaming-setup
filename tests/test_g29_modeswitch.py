import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HELPER = Path(__file__).resolve().parent.parent / "components/g29/g29-ps4-modeswitch"


class ModeSwitchTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.sysfs = root / "sys"
        self.dev = root / "dev"
        self.dev.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def add_hidraw(self, name, hid_id):
        device = self.sysfs / "class/hidraw" / name / "device"
        device.mkdir(parents=True)
        (device / "uevent").write_text(f"DRIVER=hid-generic\nHID_ID={hid_id}\nHID_NAME=test\n")
        (self.dev / name).write_bytes(b"")

    def run_helper(self, *args):
        env = dict(os.environ, G29_SYSFS_ROOT=str(self.sysfs), G29_DEV_ROOT=str(self.dev))
        return subprocess.run([sys.executable, "-I", str(HELPER), *args], env=env,
                              capture_output=True, text=True)

    def test_switches_ps4_mode_g29(self):
        self.add_hidraw("hidraw4", "0003:0000046D:0000C260")
        result = self.run_helper("hidraw4")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.dev / "hidraw4").read_bytes().hex(),
                         "30f80a0000000000" "30f8090501010000")

    def test_refuses_other_devices(self):
        for name, hid_id in (("hidraw1", "0003:0000046D:0000C24F"),
                             ("hidraw2", "0003:0000054C:000009CC"),
                             ("hidraw3", "0005:0000046D:0000C260")):
            self.add_hidraw(name, hid_id)
            result = self.run_helper(name)
            self.assertEqual(result.returncode, 3, result.stderr)
            self.assertEqual((self.dev / name).read_bytes(), b"")

    def test_dry_run_writes_nothing(self):
        self.add_hidraw("hidraw4", "0003:0000046D:0000C260")
        result = self.run_helper("--dry-run", "hidraw4")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("30f8090501010000", result.stderr)
        self.assertEqual((self.dev / "hidraw4").read_bytes(), b"")

    def test_rejects_bad_arguments(self):
        for args in ((), ("../hidraw4",), ("event7",), ("hidraw1", "hidraw2")):
            self.assertEqual(self.run_helper(*args).returncode, 2, args)

    def test_missing_device_fails(self):
        self.assertEqual(self.run_helper("hidraw9").returncode, 1)


if __name__ == "__main__":
    unittest.main()
