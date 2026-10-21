#!/usr/bin/env python3
"""Apply the managed PCSX2.ini and ReShade.ini settings for Windows PCSX2.

Both files are written by Windows programs with CRLF line endings, and
PCSX2.ini repeats keys for multiple bindings, so they are edited line by line.
Only the managed keys are touched; everything else is kept as it is.

    configure_ini.py pcsx2 PCSX2.ini --bios DIR --games DIR
    configure_ini.py reshade ReShade.ini
    configure_ini.py --check ...   exits 1 if a managed key differs
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
import tempfile

# Values are lists because PCSX2 binds one hotkey with several lines.
Settings = dict[str, dict[str, list[str]]]


def win_path(path: str) -> str:
    """The Wine Z: drive path for a Linux path."""
    return "Z:" + path.replace("/", "\\")


def pcsx2_settings(bios: str, games: str) -> Settings:
    return {
        "UI": {
            "SettingsVersion": ["1"],
            "SetupWizardIncomplete": ["false"],
            "StartFullscreen": ["true"],
        },
        # PCSX2 for Windows updates itself in place; the component pins 2.8.1.
        "AutoUpdater": {"CheckAtStartup": ["false"]},
        "Folders": {"Bios": [win_path(bios)]},
        "GameList": {"RecursivePaths": [win_path(games)]},
        "EmuCore": {
            "EnablePatches": ["true"],
            "EnableGameFixes": ["true"],
            "EnableFastBoot": ["true"],
            "EnableDiscordPresence": ["false"],
            "InhibitScreensaver": ["true"],
        },
        "EmuCore/Speedhacks": {
            "IntcStat": ["true"],
            "WaitLoop": ["true"],
            "vuFlagHack": ["true"],
            "vuThread": ["true"],
            "vu1Instant": ["true"],
        },
        "EmuCore/GS": {
            # Direct3D 12: DLSSNR's standalone path is built for it.
            "Renderer": ["15"],
            # The swapchain must equal the depth buffer (native x 3 =
            # 1920x1344, the largest that fits a 1440-pixel-tall monitor), and
            # the picture must fill it so depth and colour line up.
            "upscale_multiplier": ["3"],
            "AspectRatio": ["Stretch"],
            "FMVAspectRatioSwitch": ["Off"],
            "MaxAnisotropy": ["16"],
            "filter": ["2"],
            "TriFilter": ["-1"],
            "hw_mipmap": ["true"],
            "texture_preloading": ["2"],
            "accurate_blending_unit": ["1"],
            "dithering_ps2": ["2"],
            "VsyncEnable": ["false"],
            "SkipDuplicateFrames": ["true"],
            "fxaa": ["false"],
            "CASMode": ["0"],
        },
        # The PS button reaches PCSX2 as Escape through the PS5 helper, and
        # Share + Options opens the pause menu on whichever SDL slot the pad
        # gets (a connected wheel can take SDL-0).
        "Hotkeys": {
            "OpenPauseMenu": ["Keyboard/Escape"]
            + [f"SDL-{slot}/Back & SDL-{slot}/Start" for slot in range(4)],
        },
    }


RESHADE_SETTINGS: Settings = {
    "GENERAL": {
        "EffectSearchPaths": [".\\reshade-shaders\\Shaders\\**"],
        "TextureSearchPaths": [".\\reshade-shaders\\Textures\\**"],
        "PresetPath": [".\\ReShadePreset.ini"],
        "PerformanceMode": ["0"],
        "SkipLoadingDisabledEffects": ["0"],
    },
    "INPUT": {"KeyOverlay": ["36,0,0,0"]},
    # PCSX2's depth buffer has the PS2's shape, not the screen's.
    "DEPTH": {"UseAspectRatioHeuristics": ["0"]},
    # PCSX2 has no DLSS of its own: always run off the back buffer.
    "ADDON_DLSSNR_LINUX": {"StandaloneMode": ["1"]},
}

# The tuned look, written only when the add-on has no settings yet so later
# changes made in the overlay are kept.
DLSSNR_DEFAULTS = {
    "DirectNeuralRenderingStyle": "2",  # Model C
    "DirectNeuralRenderingPassCount": "1",
    "ModelResolution": "0",  # Full
    "DirectNeuralRenderingIntensity": "1",
    "DirectNeuralRenderingLocalStructureStrength": "1",
    "DirectNeuralRenderingLocalToneStrength": "1",
    "DirectNeuralRenderingAutoMask": "1",
    "DirectNeuralRenderingUiCorrection": "1",
    "ColourStrength": "0",
    "DetailStrength": "1",
}


def configure(text: str, managed: Settings, sep: str) -> str:
    """Return ``text`` with every managed key set, keeping other lines intact.

    A managed key is written where its first binding already is; further
    bindings for it are dropped. Missing keys go at the end of their section,
    and missing sections at the end of the file.
    """
    newline = "\r\n" if "\r\n" in text or not text else "\n"
    output: list[str] = []
    written: set[tuple[str, str]] = set()
    seen_sections: set[str] = set()
    section = None

    def bindings(name, key):
        return [f"{key}{sep}{value}" for value in managed[name][key]]

    def finish(name):
        settings = managed.get(name)
        if not settings:
            return
        missing = [key for key in settings if (name, key) not in written]
        tail = []
        while output and not output[-1].strip():
            tail.append(output.pop())
        for key in missing:
            output.extend(bindings(name, key))
            written.add((name, key))
        output.extend(reversed(tail))

    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            finish(section)
            section = stripped[1:-1]
            seen_sections.add(section)
            output.append(line)
            continue
        if section in managed and "=" in line:
            key = line.split("=", 1)[0].strip()
            if key in managed[section]:
                if (section, key) not in written:
                    output.extend(bindings(section, key))
                    written.add((section, key))
                continue
        output.append(line)
    finish(section)

    for name, settings in managed.items():
        if name in seen_sections:
            continue
        if output and output[-1].strip():
            output.append("")
        output.append(f"[{name}]")
        for key in settings:
            output.extend(bindings(name, key))

    return newline.join(output) + newline


def has_section(text: str, name: str) -> bool:
    return any(line.strip() == f"[{name}]" for line in text.splitlines())


def reshade_settings(text: str) -> Settings:
    managed = {name: dict(keys) for name, keys in RESHADE_SETTINGS.items()}
    if not has_section(text, "ADDON_DLSSNR_LINUX"):
        managed["ADDON_DLSSNR_LINUX"].update({k: [v] for k, v in DLSSNR_DEFAULTS.items()})
    return managed


def write_atomic(path: Path, text: str) -> None:
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    with os.fdopen(fd, "w", encoding="utf-8", newline="") as stream:
        stream.write(text)
    os.replace(temporary, path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=["pcsx2", "reshade"])
    parser.add_argument("ini", type=Path)
    parser.add_argument("--bios")
    parser.add_argument("--games")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    original = args.ini.read_text(encoding="utf-8", newline="") if args.ini.is_file() else ""
    if args.kind == "pcsx2":
        if not (args.bios and args.games):
            parser.error("pcsx2 needs --bios and --games")
        managed, sep = pcsx2_settings(args.bios, args.games), " = "
    else:
        managed, sep = reshade_settings(original), "="
    updated = configure(original, managed, sep)

    if args.check:
        return 0 if updated == original else 1
    if updated != original:
        args.ini.parent.mkdir(parents=True, exist_ok=True)
        write_atomic(args.ini, updated)
        print(f"{args.ini.name}: managed settings applied")
    else:
        print(f"{args.ini.name} is already current.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
