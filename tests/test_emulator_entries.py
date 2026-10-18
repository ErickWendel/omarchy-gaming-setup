import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import tempfile
import unittest


MODULE_PATH = Path(__file__).parents[1] / "components/emulators/emulators.py"
SPEC = importlib.util.spec_from_file_location("emulators", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

LEGACY = (
    "#!/usr/bin/env xdg-open\n"
    "\t[Desktop Entry]\n"
    "\tName=Azahar AppImage\n"
    "\tExec=/old/azahar.sh\n"
    "\tType=Application\n"
)


def record(**overrides):
    base = {"id": "azahar", "name": "Azahar", "exec": "{emulation}/launchers/azahar.sh",
            "icon": "{icons}/Azahar.svg", "categories": "Game;Emulator;",
            "legacy_files": ["Azahar.desktop"]}
    base.update(overrides)
    return base


class ManifestTests(unittest.TestCase):
    def load(self, data):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            json.dump(data, handle)
        self.addCleanup(os.unlink, handle.name)
        return MODULE.load_manifest(handle.name)

    def test_repository_manifest_is_valid(self):
        records = MODULE.load_manifest(MODULE_PATH.with_name("manifest.json"))
        self.assertIn("pcsx2", {item["id"] for item in records})

    def test_rejects_duplicate_ids(self):
        with self.assertRaisesRegex(MODULE.ManifestError, "duplicate"):
            self.load({"version": 1, "emulators": [record(), record()]})

    def test_rejects_missing_fields(self):
        broken = record()
        del broken["exec"]
        with self.assertRaisesRegex(MODULE.ManifestError, "exec"):
            self.load({"version": 1, "emulators": [broken]})


class EscapingTests(unittest.TestCase):
    def test_plain_path_is_unquoted(self):
        self.assertEqual(MODULE.exec_value(["/opt/emu/run.sh"]), "/opt/emu/run.sh")

    def test_reserved_characters_are_quoted_and_escaped(self):
        # Quoted with \" and \$ escaped, then backslashes doubled for the
        # string type; % becomes %%.
        self.assertEqual(MODULE.exec_value(['/a b/"x"$y%.sh']),
                         '"/a b/\\\\"x\\\\"\\\\$y%%.sh"')

    def test_string_escapes(self):
        self.assertEqual(MODULE.escape_string("a\\b\nc"), "a\\\\b\\nc")


class GenerationTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        self.apps = self.root / "applications"
        self.apps.mkdir()
        launcher = self.root / "Emulation/launchers/azahar.sh"
        launcher.parent.mkdir(parents=True)
        launcher.write_text("#!/bin/sh\n")
        launcher.chmod(0o755)
        self.places = {"emulation": str(self.root / "Emulation"), "home": str(self.root),
                       "icons": str(self.root / "icons")}
        self.validator = shutil.which("desktop-file-validate")

    def run_install(self, records, places=None):
        plan = MODULE.Plan(records, self.apps, places or self.places)
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return MODULE.install(plan, self.validator or "true", self.root,
                                  self.root / "backups", "true")

    def test_rendered_entry_is_unindented_and_valid(self):
        item = MODULE.resolve_record(record(), self.places)
        text = MODULE.render(item)
        self.assertTrue(text.startswith("[Desktop Entry]\n"))
        self.assertFalse(MODULE.has_leading_indent(text))
        self.assertIn("Icon=applications-games\n", text)  # icon file missing
        if self.validator:
            path = self.root / "check.desktop"
            path.write_text(text)
            self.assertTrue(MODULE.validate(path, self.validator)[0])

    def test_install_retires_tab_indented_legacy_entry(self):
        legacy = self.apps / "Azahar.desktop"
        legacy.write_text(LEGACY)
        self.assertEqual(self.run_install([record()]), 0)
        self.assertFalse(legacy.exists())
        self.assertEqual((self.root / "backups/applications/Azahar.desktop").read_text(), LEGACY)
        installed = (self.apps / "omarchy-gaming-azahar.desktop").read_text()
        self.assertIn(f"Exec={self.places['emulation']}/launchers/azahar.sh\n", installed)

    def test_install_is_idempotent(self):
        self.assertEqual(self.run_install([record()]), 0)
        first = (self.apps / "omarchy-gaming-azahar.desktop").stat().st_mtime_ns
        self.assertEqual(self.run_install([record()]), 0)
        self.assertEqual((self.apps / "omarchy-gaming-azahar.desktop").stat().st_mtime_ns, first)

    def test_valid_and_unrelated_entries_are_untouched(self):
        valid = self.apps / "Azahar.desktop"
        valid.write_text("[Desktop Entry]\nType=Application\nName=Azahar\nExec=azahar\n")
        other = self.apps / "omarchy-gaming-notes.desktop"
        other.write_text("[Desktop Entry]\nType=Application\nName=Notes\nExec=notes\n")
        self.run_install([record()])
        self.assertTrue(valid.exists())
        self.assertTrue(other.exists())

    def test_listed_duplicate_entry_is_retired(self):
        duplicate = self.apps / "azahar.desktop"
        duplicate.write_text("[Desktop Entry]\nType=Application\nName=Azahar\nExec=azahar\n")
        self.run_install([record(duplicate_files=["azahar.desktop"])])
        self.assertFalse(duplicate.exists())
        self.assertTrue((self.root / "backups/applications/azahar.desktop").exists())

    def test_stale_owned_entry_is_removed(self):
        stale = self.apps / "omarchy-gaming-old.desktop"
        stale.write_text(f"[Desktop Entry]\n{MODULE.OWNER_KEY}=old\n")
        self.run_install([record()])
        self.assertFalse(stale.exists())

    def test_missing_drive_skips_drive_entries(self):
        places = {key: value for key, value in self.places.items() if key != "emulation"}
        self.assertEqual(self.run_install([record()], places), 1)
        self.assertFalse((self.apps / "omarchy-gaming-azahar.desktop").exists())


if __name__ == "__main__":
    unittest.main()
