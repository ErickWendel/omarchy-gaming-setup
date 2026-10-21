import importlib.util
from pathlib import Path
import unittest


MODULE_PATH = Path(__file__).parents[1] / "components/pcsx2-dlss5/configure_ini.py"
SPEC = importlib.util.spec_from_file_location("pcsx2_dlss5_ini", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

# As PCSX2 for Windows writes it: CRLF, repeated hotkey bindings.
STOCK = (
    "[UI]\r\nSettingsVersion = 1\r\nMainWindowGeometry = abc\r\n\r\n"
    "[EmuCore/GS]\r\nRenderer = 3\r\nupscale_multiplier = 6\r\nOsdShowFPS = true\r\n\r\n"
    "[Hotkeys]\r\nOpenPauseMenu = SDL-0/Back & SDL-0/RightStick\r\n"
    "OpenPauseMenu = Keyboard/F1\r\nScreenshot = Keyboard/F8\r\n\r\n"
)


def values(text, section, key):
    current = None
    found = []
    for line in text.splitlines():
        if line.startswith("["):
            current = line.strip("[]")
        elif current == section and line.split("=", 1)[0].strip() == key:
            found.append(line.split("=", 1)[1].strip())
    return found


class Pcsx2Dlss5IniTests(unittest.TestCase):
    def setUp(self):
        self.managed = MODULE.pcsx2_settings("/run/media/u/G/bios", "/run/media/u/G/roms/ps2")

    def test_keeps_crlf_and_unmanaged_lines(self):
        result = MODULE.configure(STOCK, self.managed, " = ")
        self.assertNotIn("\n", result.replace("\r\n", ""))
        self.assertIn("MainWindowGeometry = abc\r\n", result)
        self.assertIn("OsdShowFPS = true\r\n", result)
        self.assertEqual(values(result, "Hotkeys", "Screenshot"), ["Keyboard/F8"])

    def test_sets_renderer_resolution_and_replaces_bindings(self):
        result = MODULE.configure(STOCK, self.managed, " = ")
        self.assertEqual(values(result, "EmuCore/GS", "Renderer"), ["15"])
        self.assertEqual(values(result, "EmuCore/GS", "upscale_multiplier"), ["3"])
        pause = values(result, "Hotkeys", "OpenPauseMenu")
        self.assertEqual(pause[0], "Keyboard/Escape")
        self.assertIn("SDL-2/Back & SDL-2/Start", pause)
        self.assertNotIn("Keyboard/F1", pause)

    def test_adds_missing_sections_with_wine_paths(self):
        result = MODULE.configure(STOCK, self.managed, " = ")
        self.assertEqual(values(result, "Folders", "Bios"), ["Z:\\run\\media\\u\\G\\bios"])
        self.assertEqual(values(result, "AutoUpdater", "CheckAtStartup"), ["false"])

    def test_is_idempotent(self):
        once = MODULE.configure(STOCK, self.managed, " = ")
        self.assertEqual(MODULE.configure(once, self.managed, " = "), once)

    def test_reshade_tuned_look_only_on_first_install(self):
        fresh = MODULE.configure("", MODULE.reshade_settings(""), "=")
        self.assertEqual(values(fresh, "ADDON_DLSSNR_LINUX", "DirectNeuralRenderingPassCount"), ["1"])
        self.assertEqual(values(fresh, "DEPTH", "UseAspectRatioHeuristics"), ["0"])
        tuned = fresh.replace("DirectNeuralRenderingPassCount=1", "DirectNeuralRenderingPassCount=3")
        again = MODULE.configure(tuned, MODULE.reshade_settings(tuned), "=")
        self.assertEqual(values(again, "ADDON_DLSSNR_LINUX", "DirectNeuralRenderingPassCount"), ["3"])
        self.assertEqual(values(again, "ADDON_DLSSNR_LINUX", "StandaloneMode"), ["1"])


if __name__ == "__main__":
    unittest.main()
