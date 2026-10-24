import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import shutil
import tempfile
import unittest

import vdf


MODULE_PATH = Path(__file__).parents[1] / "components/emulators/steam_shortcuts.py"
SPEC = importlib.util.spec_from_file_location("steam_shortcuts", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

UNRELATED = {
    "appid": -123, "appname": "Rocket League", "exe": '"/games/RocketLeague.exe"',
    "StartDir": '"/games/"', "LaunchOptions": "%command%", "LastPlayTime": 1700000000,
    "tags": {"0": "favorite"},
}


def fields(exe="/mnt/Emulation/launchers/azahar.sh", name="Azahar"):
    return {"appname": name, "exe": f'"{exe}"', "StartDir": exe.rsplit("/", 1)[0], "icon": ""}


class ReconcileTests(unittest.TestCase):
    def test_adds_shortcut_with_steam_appid_and_keeps_unrelated(self):
        shortcuts = {"shortcuts": {"0": copy.deepcopy(UNRELATED)}}
        changes, state = MODULE.reconcile(shortcuts, {}, {"azahar": fields()}, {"azahar"})
        self.assertEqual(len(changes), 1)
        entries = shortcuts["shortcuts"]
        self.assertEqual(list(entries), ["0", "1"])
        self.assertEqual(entries["0"], UNRELATED)
        appid = MODULE.shortcut_appid('"/mnt/Emulation/launchers/azahar.sh"', "Azahar")
        self.assertEqual(MODULE.unsigned(entries["1"]["appid"]), appid)
        self.assertLess(entries["1"]["appid"], 0)  # binary VDF stores int32
        self.assertEqual(entries["1"]["tags"], {"0": MODULE.COLLECTION_TAG})
        self.assertEqual(state, {"azahar": appid})

    def test_rerun_is_idempotent(self):
        shortcuts = {"shortcuts": {}}
        _, state = MODULE.reconcile(shortcuts, {}, {"azahar": fields()}, {"azahar"})
        before = copy.deepcopy(shortcuts)
        changes, again = MODULE.reconcile(shortcuts, state, {"azahar": fields()}, {"azahar"})
        self.assertEqual(changes, [])
        self.assertEqual(shortcuts, before)
        self.assertEqual(again, state)

    def test_moved_launcher_updates_owned_shortcut_in_place(self):
        shortcuts = {"shortcuts": {}}
        _, state = MODULE.reconcile(shortcuts, {}, {"azahar": fields()}, {"azahar"})
        shortcuts["shortcuts"]["0"]["LastPlayTime"] = 42
        moved = fields("/media/new/Emulation/launchers/azahar.sh")
        changes, new_state = MODULE.reconcile(shortcuts, state, {"azahar": moved}, {"azahar"})
        self.assertEqual(len(shortcuts["shortcuts"]), 1)
        entry = shortcuts["shortcuts"]["0"]
        self.assertEqual(entry["exe"], moved["exe"])
        self.assertEqual(entry["LastPlayTime"], 42)
        self.assertEqual(new_state, state)
        self.assertIn("exe", changes[0])

    def test_adopts_hand_made_shortcut_but_not_game_shortcuts(self):
        wrapper = "/home/u/.local/bin/omarchy-pcsx2"
        game = {"appid": -5, "appname": "God of War", "exe": f'"{wrapper}"',
                "LaunchOptions": '-batch "/roms/gow.iso"', "tags": {}}
        manual = {"appid": -6, "appname": "pcsx2", "exe": f'"{wrapper}"', "LaunchOptions": "",
                  "tags": {"0": "favorite"}, "icon": "/my/icon.png"}
        shortcuts = {"shortcuts": {"0": copy.deepcopy(game), "1": manual}}
        changes, state = MODULE.reconcile(
            shortcuts, {}, {"pcsx2": fields(wrapper, "PCSX2")}, {"pcsx2"})
        self.assertEqual(len(shortcuts["shortcuts"]), 2)
        self.assertEqual(shortcuts["shortcuts"]["0"], game)
        adopted = shortcuts["shortcuts"]["1"]
        self.assertEqual(adopted["appname"], "PCSX2")
        self.assertEqual(adopted["icon"], "/my/icon.png")
        self.assertEqual(adopted["tags"], {"0": "favorite", "1": MODULE.COLLECTION_TAG})
        self.assertEqual(state, {"pcsx2": MODULE.unsigned(-6)})

    def test_record_removed_from_manifest_removes_only_owned_shortcut(self):
        shortcuts = {"shortcuts": {"0": copy.deepcopy(UNRELATED)}}
        _, state = MODULE.reconcile(shortcuts, {}, {"azahar": fields()}, {"azahar"})
        changes, new_state = MODULE.reconcile(shortcuts, state, {}, set())
        self.assertEqual(shortcuts["shortcuts"], {"0": UNRELATED})
        self.assertEqual(new_state, {})
        self.assertIn("Remove", changes[0])

    def test_blocked_record_keeps_its_shortcut(self):
        shortcuts = {"shortcuts": {}}
        _, state = MODULE.reconcile(shortcuts, {}, {"azahar": fields()}, {"azahar"})
        changes, new_state = MODULE.reconcile(shortcuts, state, {}, {"azahar"})
        self.assertEqual(changes, [])
        self.assertEqual(len(shortcuts["shortcuts"]), 1)
        self.assertEqual(new_state, state)

    def test_stale_emulation_root_is_reported(self):
        shortcuts = {"shortcuts": {
            "0": {"appname": "Old", "exe": '"/run/media/u/sdb1/Emulation/tools/retroarch.sh" -L x.so'},
            "1": {"appname": "Live", "exe": '"/run/media/u/GExtended/Emulation/tools/rpcs3.sh"'},
            "2": {"appname": "Game", "exe": '"/w"',
                  "LaunchOptions": '-batch "/run/media/u/GExtended/Emulation/roms/a.iso"'},
        }}
        stale = MODULE.stale_emulation_paths(shortcuts, "/run/media/u/GExtended/Emulation")
        self.assertEqual(stale, [("Old", "exe", "/run/media/u/sdb1/Emulation")])


class CommandTests(unittest.TestCase):
    """Run main() against a temporary Steam tree and fake findmnt."""

    def setUp(self):
        self.root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.root)
        self.mount = self.root / "GExtended"
        launcher = self.mount / "Emulation/launchers/azahar.sh"
        launcher.parent.mkdir(parents=True)
        launcher.write_text("#!/bin/sh\n")
        launcher.chmod(0o755)
        self.findmnt = self.root / "findmnt"
        self.findmnt.write_text(f"#!/bin/sh\necho '{self.mount} rw,relatime'\n")
        self.findmnt.chmod(0o755)
        self.manifest = self.root / "manifest.json"
        self.manifest.write_text(json.dumps({"version": 1, "emulators": [{
            "id": "azahar", "name": "Azahar", "exec": "{emulation}/launchers/azahar.sh",
            "icon": "applications-games", "categories": "Game;Emulator;", "steam": True}]}))
        self.config = self.root / "Steam/userdata/1234/config"
        self.config.mkdir(parents=True)
        self.shortcuts = self.config / "shortcuts.vdf"
        with self.shortcuts.open("wb") as stream:
            vdf.binary_dump({"shortcuts": {"0": UNRELATED}}, stream)

    def main(self, action):
        argv = [action, "--uuid", "x", "--manifest", str(self.manifest),
                "--steam-root", str(self.root / "Steam"), "--findmnt", str(self.findmnt),
                "--state-file", str(self.root / "state.json"),
                "--backup-root", str(self.root / "backups"), "--ignore-running-steam"]
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            code = MODULE.main(argv)
        return code, out.getvalue()

    def load(self):
        with self.shortcuts.open("rb") as stream:
            return vdf.binary_load(stream)

    def test_dry_run_writes_nothing(self):
        before = self.shortcuts.read_bytes()
        code, output = self.main("dry-run")
        self.assertEqual(code, 0)
        self.assertIn("Add Steam shortcut Azahar", output)
        self.assertEqual(self.shortcuts.read_bytes(), before)
        self.assertFalse((self.root / "state.json").exists())

    def test_install_backs_up_then_check_passes_and_rerun_is_noop(self):
        before = self.shortcuts.read_bytes()
        self.assertEqual(self.main("check")[0], 1)
        self.assertEqual(self.main("install")[0], 0)
        backups = list((self.root / "backups").glob("*/shortcuts.vdf"))
        self.assertEqual([path.read_bytes() for path in backups], [before])
        entries = self.load()["shortcuts"]
        self.assertEqual(entries["0"], UNRELATED)
        self.assertEqual(entries["1"]["appname"], "Azahar")
        code, output = self.main("check")
        self.assertEqual(code, 0, output)
        after = self.shortcuts.read_bytes()
        code, output = self.main("install")
        self.assertEqual(code, 0)
        self.assertIn("up to date", output)
        self.assertEqual(self.shortcuts.read_bytes(), after)

    def test_unmounted_drive_skips_without_writing(self):
        self.findmnt.write_text("#!/bin/sh\nexit 1\n")
        before = self.shortcuts.read_bytes()
        code, output = self.main("install")
        self.assertEqual(code, 1)
        self.assertIn("GExtended not mounted", output)
        self.assertEqual(self.shortcuts.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
