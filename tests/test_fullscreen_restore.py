import importlib.machinery
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest import mock


ROOT = Path(__file__).parents[1] / "components/hypr"
LOADER = importlib.machinery.SourceFileLoader("fullscreen_restore", str(ROOT / "fullscreen-restore"))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
FSR = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = FSR
LOADER.exec_module(FSR)


def client(addr, cls, title="", fullscreen=0, ws=1):
    return {"address": addr, "class": cls, "title": title, "fullscreen": fullscreen, "workspace": {"id": ws}}


def snapshot(*cs):
    return {c["address"]: c for c in cs}


class FullscreenRestoreTests(unittest.TestCase):
    def setUp(self):
        FSR.stacks.clear()
        FSR.known.clear()
        timer = mock.patch.object(FSR.threading, "Timer")
        self.timer = timer.start()
        self.addCleanup(timer.stop)

    def launch_game(self):
        """Launcher goes fullscreen, then a game takes fullscreen over it."""
        FSR.refresh(snapshot(client("0xl", "launcher", "Launcher", 2)))
        FSR.refresh(snapshot(client("0xl", "launcher", "Launcher"), client("0xg", "game", "Game", 2)))

    def test_handoff_stacks_windows_in_order(self):
        self.launch_game()
        self.assertEqual([e["addr"] for e in FSR.stacks[1]], ["0xl", "0xg"])
        self.timer.assert_called_once_with(FSR.HANDOFF_SETTLE, FSR.check_handoff, ("0xl",))

    def test_restores_previous_window_still_open(self):
        self.launch_game()
        FSR.forget("0xg")
        now = snapshot(client("0xl", "launcher", "Launcher"), client("0xo", "other"))
        self.assertEqual(FSR.restore_target(FSR.stacks[1], now)[0]["address"], "0xl")

    def test_matches_recreated_launcher_by_class_and_title(self):
        self.launch_game()
        FSR.forget("0xg")
        now = snapshot(client("0xnew", "launcher", "Launcher"))
        self.assertEqual(FSR.restore_target(FSR.stacks[1], now)[0]["address"], "0xnew")

    def test_older_closed_entries_do_not_match_by_title(self):
        FSR.stacks[1] = [
            {"addr": "0xold", "cls": "foot", "title": "foot", "mode": 2},
            {"addr": "0xl", "cls": "launcher", "title": "Launcher", "mode": 2},
        ]
        self.assertIsNone(FSR.restore_target(FSR.stacks[1], snapshot(client("0xf", "foot", "foot"))))

    def test_leaving_fullscreen_without_handoff_forgets_window(self):
        FSR.refresh(snapshot(client("0xl", "launcher", "Launcher", 2)))
        with mock.patch.object(FSR, "clients", return_value=snapshot(client("0xl", "launcher", "Launcher"))):
            FSR.check_handoff("0xl")
        self.assertEqual(FSR.stacks[1], [])

    def test_handoff_keeps_window(self):
        self.launch_game()
        now = snapshot(client("0xl", "launcher", "Launcher"), client("0xg", "game", "Game", 2))
        with mock.patch.object(FSR, "clients", return_value=now):
            FSR.check_handoff("0xl")
        self.assertEqual([e["addr"] for e in FSR.stacks[1]], ["0xl", "0xg"])

    def test_stack_is_capped(self):
        for i in range(FSR.STACK_LIMIT + 5):
            FSR.known.clear()
            FSR.refresh(snapshot(client(f"0x{i}", "app", fullscreen=2)))
        self.assertEqual(len(FSR.stacks[1]), FSR.STACK_LIMIT)
        self.assertEqual(FSR.stacks[1][-1]["addr"], f"0x{FSR.STACK_LIMIT + 4}")

    def test_closing_windowed_window_does_not_restore(self):
        FSR.known["0xg"] = client("0xg", "game")
        with mock.patch.object(FSR.threading, "Thread") as thread:
            FSR.on_close("0xg")
        thread.assert_not_called()


if __name__ == "__main__":
    unittest.main()
