import importlib.machinery
import importlib.util
from pathlib import Path
import subprocess
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

    def run_restore(self, now, alive):
        """Run restore() for a closed Content Manager over Big Picture; return dispatched commands."""
        FSR.stacks[1] = [
            {"addr": "0xbp", "cls": "steam", "title": "Big Picture", "mode": 2},
            {"addr": "0xcm", "cls": "cm", "title": "Content Manager", "mode": 2},
        ]
        with mock.patch.object(FSR, "clients", return_value=now), \
                mock.patch.object(FSR, "process_alive", return_value=alive), \
                mock.patch.object(FSR, "dispatch") as dispatch, \
                mock.patch.object(FSR, "EXIT_WAIT", 0), mock.patch.object(FSR, "REAPPEAR_WAIT", 0), \
                mock.patch.object(FSR.time, "sleep"):
            FSR.restore("0xcm", 42, 1)
        return [call.args[0] for call in dispatch.call_args_list]

    def test_hidden_launcher_does_not_hand_fullscreen_down(self):
        """Content Manager hiding to the tray before the race window exists."""
        self.assertEqual(self.run_restore(snapshot(client("0xbp", "steam", "Big Picture")), alive=True), [])
        self.assertEqual([e["addr"] for e in FSR.stacks[1]], ["0xbp", "0xcm"])

    def test_hidden_launcher_coming_back_gets_fullscreen(self):
        now = snapshot(client("0xbp", "steam", "Big Picture"), client("0xnew", "cm", "Content Manager"))
        self.assertIn("address:0xnew", self.run_restore(now, alive=True)[0])

    def test_exited_window_hands_fullscreen_down(self):
        commands = self.run_restore(snapshot(client("0xbp", "steam", "Big Picture")), alive=False)
        self.assertIn("address:0xbp", commands[0])
        self.assertEqual([e["addr"] for e in FSR.stacks[1]], ["0xbp"])

    def run_launcher_handoff(self, now, running, wait=FSR.APP_WINDOW_WAIT):
        """Run restore() for FIFA Mod Manager closing over Big Picture after starting the game."""
        FSR.stacks[1] = [
            {"addr": "0xbp", "cls": "steam", "title": "Big Picture", "mode": 2},
            {"addr": "0xmm", "cls": "steam_app_42", "title": "FIFA Mod Manager", "mode": 2},
        ]
        with mock.patch.object(FSR, "clients", return_value=now), \
                mock.patch.object(FSR, "process_alive", return_value=False), \
                mock.patch.object(FSR, "app_running", return_value=running) as app_running, \
                mock.patch.object(FSR, "dispatch") as dispatch, \
                mock.patch.object(FSR, "REAPPEAR_WAIT", 0), mock.patch.object(FSR, "APP_WINDOW_WAIT", wait), \
                mock.patch.object(FSR.time, "sleep"):
            FSR.restore("0xmm", 42, 1, "steam_app_42")
        if running and wait:
            app_running.assert_called_with("42", 42)
        return [call.args[0] for call in dispatch.call_args_list]

    def test_closed_launcher_hands_fullscreen_to_its_game(self):
        now = snapshot(client("0xbp", "steam", "Big Picture"), client("0xg", "steam_app_42", "FIFA 23"))
        commands = self.run_launcher_handoff(now, running=True)
        self.assertIn("address:0xg", commands[0])
        self.assertIn('mode = "fullscreen"', commands[1])

    def test_exited_app_hands_fullscreen_back_to_big_picture(self):
        now = snapshot(client("0xbp", "steam", "Big Picture"))
        self.assertIn("address:0xbp", self.run_launcher_handoff(now, running=False)[0])

    def test_app_popup_does_not_take_fullscreen(self):
        """The launcher's floating glow windows are not the game; Big Picture comes back once the wait ends."""
        glow = dict(client("0xglow", "steam_app_42", "GlowWindow_Left"), floating=True)
        now = snapshot(client("0xbp", "steam", "Big Picture"), glow)
        self.assertIn("address:0xbp", self.run_launcher_handoff(now, running=True, wait=0)[0])

    def test_steam_appid(self):
        self.assertEqual(FSR.steam_appid("steam_app_2610707543"), "2610707543")
        self.assertIsNone(FSR.steam_appid("steam"))
        self.assertIsNone(FSR.steam_appid("steam_app_default"))

    def test_app_running_counts_windows_programs_of_the_app(self):
        env = dict(FSR.os.environ, SteamAppId="987654321")
        procs = [subprocess.Popen([argv0, "30"], executable="/usr/bin/sleep", env=env)
                 for argv0 in ("C:\\windows\\system32\\services.exe", "D:\\Games\\FIFA 23\\FIFA23.exe")]
        try:
            self.assertTrue(FSR.app_running("987654321", -1))
            self.assertFalse(FSR.app_running("987654321", procs[1].pid))
            self.assertFalse(FSR.app_running("123", -1))
        finally:
            for p in procs:
                p.kill()
                p.wait()

    def test_process_alive(self):
        self.assertTrue(FSR.process_alive(FSR.os.getpid()))
        self.assertFalse(FSR.process_alive(2 ** 22 + 1))

    def test_closing_windowed_window_does_not_restore(self):
        FSR.known["0xg"] = client("0xg", "game")
        with mock.patch.object(FSR.threading, "Thread") as thread:
            FSR.on_close("0xg")
        thread.assert_not_called()


if __name__ == "__main__":
    unittest.main()
