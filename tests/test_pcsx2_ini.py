import importlib.util
from pathlib import Path
import unittest


MODULE_PATH = Path(__file__).parents[1] / "components/pcsx2/configure_pcsx2_ini.py"
SPEC = importlib.util.spec_from_file_location("pcsx2_ini", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

STOCK = """[EmuCore/GS]
Renderer = -1
upscale_multiplier = 6


[Hotkeys]
ShutdownVM = SDL-0/Back & SDL-0/Start
Screenshot = Keyboard/F8
OpenPauseMenu = SDL-0/Back & SDL-0/RightStick
ToggleSoftwareRendering = SDL-0/Start & SDL-0/DPadLeft
ToggleSoftwareRendering = Keyboard/F9


[Pad1]
Start = SDL-0/Start
"""


def values(text, section, key):
    current = None
    found = []
    for line in text.splitlines():
        if line.startswith("["):
            current = line.strip("[]")
        elif current == section and line.split("=", 1)[0].strip() == key:
            found.append(line.split("=", 1)[1].strip())
    return found


class PcsxIniTests(unittest.TestCase):
    def test_sets_renderer_and_hotkeys(self):
        result = MODULE.configure(STOCK)
        self.assertEqual(values(result, "EmuCore/GS", "Renderer"), ["14"])
        self.assertEqual(
            values(result, "Hotkeys", "OpenPauseMenu"),
            ["Keyboard/Escape"] + [f"SDL-{i}/Back & SDL-{i}/Start" for i in range(4)],
        )
        self.assertEqual(
            values(result, "Hotkeys", "ShutdownVM"),
            ["SDL-0/Back & SDL-0/RightStick"],
        )

    def test_keeps_unmanaged_lines_and_repeated_keys(self):
        result = MODULE.configure(STOCK)
        self.assertEqual(
            values(result, "Hotkeys", "ToggleSoftwareRendering"),
            ["SDL-0/Start & SDL-0/DPadLeft", "Keyboard/F9"],
        )
        self.assertEqual(values(result, "Pad1", "Start"), ["SDL-0/Start"])
        self.assertIn("upscale_multiplier = 6", result)

    def test_is_idempotent(self):
        once = MODULE.configure(STOCK)
        self.assertEqual(MODULE.configure(once), once)

    def test_adds_missing_sections(self):
        result = MODULE.configure("[UI]\nTheme = dark\n")
        self.assertEqual(values(result, "EmuCore/GS", "Renderer"), ["14"])
        self.assertEqual(values(result, "Hotkeys", "OpenPauseMenu")[0], "Keyboard/Escape")


class GameSettingsTests(unittest.TestCase):
    def test_new_game_settings_enable_the_patch(self):
        managed = MODULE.GAME_SETTINGS["SLUS-21050_BEBF8793.ini"]
        text = MODULE.configure("", managed)
        self.assertEqual(values(text, "Patches", "Enable"), ["Ultrawide 3440x1440"])

    def test_existing_game_settings_are_kept(self):
        managed = MODULE.GAME_SETTINGS["SLUS-21050_BEBF8793.ini"]
        text = MODULE.configure("[EmuCore/GS]\nLoadTextureReplacements = true\n", managed)
        self.assertEqual(values(text, "EmuCore/GS", "LoadTextureReplacements"), ["true"])
        self.assertEqual(values(text, "Patches", "Enable"), ["Ultrawide 3440x1440"])
        self.assertEqual(MODULE.configure(text, managed), text)

    def test_patch_section_matches_enabled_name(self):
        patch = MODULE_PATH.parent / "patches/SLUS-21050_BEBF8793.pnach"
        self.assertIn("[Ultrawide 3440x1440]", patch.read_text().splitlines())


if __name__ == "__main__":
    unittest.main()
