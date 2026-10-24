import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest


MODULE_PATH = Path(__file__).parents[1] / "components/pcsx2/configure_steam_shortcuts.py"
SPEC = importlib.util.spec_from_file_location("pcsx2_steam", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class SteamConfigTests(unittest.TestCase):
    def test_only_pcsx2_entries_change(self):
        shortcuts = {
            "shortcuts": {
                "0": {"appid": -1, "appname": "PS2 game", "exe": '"/old/pcsx2-qt.sh"', "StartDir": "/old"},
                "1": {"appid": -2, "appname": "Other", "exe": '"/other.sh"', "StartDir": "/other"},
            }
        }
        local = {"UserLocalConfigStore": {"apps": {}}}
        other = copy.deepcopy(shortcuts["shortcuts"]["1"])

        changed = MODULE.configure(shortcuts, local, Path("/home/test/.local/bin/omarchy-pcsx2"))

        self.assertEqual(changed, [(0xFFFFFFFF, "PS2 game")])
        self.assertEqual(shortcuts["shortcuts"]["1"], other)
        self.assertEqual(
            local["UserLocalConfigStore"]["apps"][str(0xFFFFFFFF)]["UseSteamControllerConfig"],
            "0",
        )

    def test_configuration_is_idempotent(self):
        shortcuts = {"shortcuts": {"0": {"appid": 42, "appname": "PS2", "exe": "pcsx2"}}}
        local = {}
        wrapper = Path("/home/test/.local/bin/omarchy-pcsx2")
        MODULE.configure(shortcuts, local, wrapper)
        first = (copy.deepcopy(shortcuts), copy.deepcopy(local))
        MODULE.configure(shortcuts, local, wrapper)
        self.assertEqual((shortcuts, local), first)

    def test_check_reports_steam_input_and_wrapper(self):
        wrapper = Path("/home/test/.local/bin/omarchy-pcsx2")
        shortcuts = {"shortcuts": {
            "0": {"appid": 7, "appname": "Old", "exe": '"/old/pcsx2-qt.sh"'},
            "1": {"appid": 8, "appname": "Good", "exe": f'"{wrapper}"'},
        }}
        local = {"UserLocalConfigStore": {"apps": {"8": {"UseSteamControllerConfig": "0"}}}}
        found = MODULE.problems(shortcuts, local, wrapper)
        self.assertEqual(len(found), 2)
        self.assertTrue(all(line.startswith("Old: ") for line in found))
        MODULE.configure(shortcuts, local, wrapper)
        self.assertEqual(MODULE.problems(shortcuts, local, wrapper), [])


if __name__ == "__main__":
    unittest.main()

