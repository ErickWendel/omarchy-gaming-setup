import importlib.machinery
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).parents[1] / "components/steam"
LOADER = importlib.machinery.SourceFileLoader("match_resolution", str(ROOT / "match-resolution"))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
MATCH = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MATCH
LOADER.exec_module(MATCH)

sys.modules.setdefault("vdf", mock.Mock())
OPTIONS_SPEC = importlib.util.spec_from_file_location(
    "launch_options", ROOT / "configure_launch_options.py"
)
OPTIONS = importlib.util.module_from_spec(OPTIONS_SPEC)
OPTIONS_SPEC.loader.exec_module(OPTIONS)

FORZA = MATCH.GAMES["1551360"]
FORZA_XML = (
    '<UserConfigSelections>\r\n'
    '<ResolutionWidth value="2560"/>\r\n'
    '<ResolutionHeight value="1440"/>\r\n'
    '<Fullscreen value="1"/>\r\n'
    '</UserConfigSelections>\r\n'
)


class MonitorTests(unittest.TestCase):
    def test_uses_focused_monitor(self):
        monitors = [
            {"width": 3440, "height": 1440, "focused": False},
            {"width": 3840, "height": 2160, "focused": True},
        ]
        self.assertEqual(MATCH.focused_monitor_size(monitors), (3840, 2160))

    def test_rotated_monitor_swaps_dimensions(self):
        monitors = [{"width": 2560, "height": 1440, "focused": True, "transform": 1}]
        self.assertEqual(MATCH.focused_monitor_size(monitors), (1440, 2560))


class ForzaConfigTests(unittest.TestCase):
    def test_rewrites_resolution_and_keeps_crlf(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root, "UserConfigSelections")
            path.write_bytes(FORZA_XML.encode())
            self.assertTrue(MATCH.update_config(path, FORZA, 3840, 2160))
            data = path.read_bytes().decode()
        self.assertIn('<ResolutionWidth value="3840"/>\r\n', data)
        self.assertIn('<ResolutionHeight value="2160"/>\r\n', data)
        self.assertIn('<Fullscreen value="1"/>', data)

    def test_unchanged_resolution_is_not_rewritten(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root, "UserConfigSelections")
            path.write_bytes(FORZA_XML.encode())
            self.assertFalse(MATCH.update_config(path, FORZA, 2560, 1440))

    def test_missing_setting_is_an_error(self):
        with self.assertRaises(ValueError):
            MATCH.apply_resolution("<Other/>", FORZA, 3840, 2160)

    def test_sync_uses_steam_environment(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root, "pfx", FORZA.prefix_path)
            path.parent.mkdir(parents=True)
            path.write_bytes(FORZA_XML.encode())
            env = {"SteamAppId": "1551360", "STEAM_COMPAT_DATA_PATH": root}
            with mock.patch.object(
                MATCH, "read_monitors",
                return_value=[{"width": 3840, "height": 2160, "focused": True}],
            ), mock.patch.object(MATCH, "log"):
                MATCH.sync(env)
            self.assertIn('value="3840"', path.read_text())

    def test_launch_continues_when_sync_fails(self):
        with mock.patch.object(MATCH, "sync", side_effect=RuntimeError("boom")), \
             mock.patch.object(MATCH, "log"), \
             mock.patch.object(MATCH.os, "execvp") as execvp:
            MATCH.main(["game", "--flag"])
        execvp.assert_called_once_with("game", ["game", "--flag"])


class LaunchOptionTests(unittest.TestCase):
    wrapper = "/home/u/.local/bin/omarchy-match-resolution"

    def test_empty_options(self):
        self.assertEqual(OPTIONS.with_wrapper("", self.wrapper), f"{self.wrapper} %command%")

    def test_existing_command_options_are_kept(self):
        self.assertEqual(
            OPTIONS.with_wrapper("PROTON_LOG=1 %command% -dx12", self.wrapper),
            f"PROTON_LOG=1 {self.wrapper} %command% -dx12",
        )

    def test_game_arguments_without_command(self):
        self.assertEqual(
            OPTIONS.with_wrapper("-skipintro", self.wrapper),
            f"{self.wrapper} %command% -skipintro",
        )

    def test_is_idempotent(self):
        once = OPTIONS.with_wrapper("", self.wrapper)
        self.assertEqual(OPTIONS.with_wrapper(once, self.wrapper), once)

    def test_configure_only_managed_apps(self):
        local = {}
        changed = OPTIONS.configure(local, self.wrapper, ["1551360"])
        apps = local["UserLocalConfigStore"]["Software"]["Valve"]["Steam"]["apps"]
        self.assertEqual(changed, ["1551360"])
        self.assertEqual(list(apps), ["1551360"])


if __name__ == "__main__":
    unittest.main()
