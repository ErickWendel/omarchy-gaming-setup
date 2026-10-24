import importlib.machinery
import importlib.util
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace

try:
    from evdev import AbsInfo, ecodes as e
except ImportError:  # python-evdev is installed by scripts/packages.sh
    e = None

BRIDGE = Path(__file__).parents[1] / "components/nfsmw/nfsmw-wheel-bridge"


def load_bridge():
    loader = importlib.machinery.SourceFileLoader("nfsmw_wheel_bridge", str(BRIDGE))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class FakeWheel:
    """The G923 on hid-logitech-dd with g923_pedal_invert=N."""

    def __init__(self):
        self.written, self.uploaded, self.erased = [], [], []

    def capabilities(self, absinfo=False):
        pedal = AbsInfo(255, 0, 255, 0, 0, 0)
        return {
            e.EV_KEY: [e.BTN_TRIGGER, e.BTN_THUMB],
            e.EV_ABS: [(e.ABS_X, AbsInfo(32768, 0, 65535, 0, 0, 0)), (e.ABS_Y, pedal), (e.ABS_Z, pedal),
                       (e.ABS_RZ, pedal), (e.ABS_HAT0X, AbsInfo(0, -1, 1, 0, 0, 0))],
            e.EV_FF: [e.FF_CONSTANT, e.FF_SPRING, e.FF_GAIN],
        }

    def upload_effect(self, effect):
        self.uploaded.append(effect.id)
        return effect.id if effect.id >= 0 else 10 + len(self.uploaded)

    def erase_effect(self, effect_id):
        self.erased.append(effect_id)

    def write(self, kind, code, value):
        self.written.append((kind, code, value))


class FakeVirtual:
    def __init__(self):
        self.events, self.uploads, self.erases = [], [], []

    def write(self, kind, code, value):
        self.events.append((kind, code, value))

    def syn(self):
        self.events.append("syn")

    def begin_upload(self, request):
        upload = SimpleNamespace(effect=SimpleNamespace(id=request), retval=None)
        self.uploads.append(upload)
        return upload

    def end_upload(self, upload):
        pass

    def begin_erase(self, request):
        erase = SimpleNamespace(effect_id=request, retval=None)
        self.erases.append(erase)
        return erase

    def end_erase(self, erase):
        pass


def ev(kind, code, value):
    return SimpleNamespace(type=kind, code=code, value=value)


@unittest.skipIf(e is None, "python-evdev is not installed")
class NfsmwWheelBridgeTests(unittest.TestCase):
    def setUp(self):
        self.mod = load_bridge()
        self.wheel, self.virtual = FakeWheel(), FakeVirtual()
        self.bridge = self.mod.Bridge(self.wheel, self.virtual, at_max=True)

    def y_values(self):
        return [v for kind, code, v in (x for x in self.virtual.events if x != "syn") if code == e.ABS_Y]

    def test_pedals_combine_on_a_centred_axis(self):
        for code, value in ((e.ABS_Y, 0), (e.ABS_Y, 255), (e.ABS_Z, 0), (e.ABS_Y, 0)):
            self.bridge.source_event(ev(e.EV_ABS, code, value))
        # gas floored, released, brake floored, both floored
        self.assertEqual(self.y_values(), [-32767, 0, 32767, 0])

    def test_clutch_is_dropped_and_steering_buttons_hat_pass(self):
        for event in (ev(e.EV_ABS, e.ABS_RZ, 0), ev(e.EV_ABS, e.ABS_X, 100), ev(e.EV_KEY, e.BTN_THUMB, 1),
                      ev(e.EV_ABS, e.ABS_HAT0X, -1), ev(e.EV_SYN, 0, 0)):
            self.bridge.source_event(event)
        self.assertEqual(self.virtual.events, [(e.EV_ABS, e.ABS_X, 100), (e.EV_KEY, e.BTN_THUMB, 1),
                                               (e.EV_ABS, e.ABS_HAT0X, -1), "syn"])

    def test_released_at_zero_when_the_driver_inverts(self):
        bridge = self.mod.Bridge(self.wheel, self.virtual, at_max=False)
        bridge.source_event(ev(e.EV_ABS, e.ABS_Y, 255))
        self.assertEqual(self.y_values(), [-32767])

    def test_invert_parameter(self):
        with tempfile.NamedTemporaryFile("w") as f:
            f.write("Y\n"); f.flush()
            self.assertFalse(self.mod.released_at_max(f.name))
            f.seek(0); f.write("N\n"); f.flush()
            self.assertTrue(self.mod.released_at_max(f.name))
        self.assertTrue(self.mod.released_at_max("/nonexistent"))

    def test_virtual_device_has_no_separate_pedals(self):
        caps = self.mod.virtual_capabilities(self.wheel)
        self.assertEqual([code for code, _ in caps[e.EV_ABS]], [e.ABS_X, e.ABS_Y, e.ABS_HAT0X])
        self.assertEqual(caps[e.EV_ABS][1][1].min, -self.mod.COMBINED_MAX)
        self.assertEqual(caps[e.EV_FF], self.wheel.capabilities()[e.EV_FF])

    def test_separate_pedals_pass_and_clutch_is_dropped(self):
        bridge = self.mod.Bridge(self.wheel, self.virtual, at_max=True, separate=True)
        for event in (ev(e.EV_ABS, e.ABS_Y, 10), ev(e.EV_ABS, e.ABS_Z, 20), ev(e.EV_ABS, e.ABS_RZ, 0),
                      ev(e.EV_ABS, e.ABS_X, 100), ev(e.EV_SYN, 0, 0)):
            bridge.source_event(event)
        self.assertEqual(self.virtual.events, [(e.EV_ABS, e.ABS_Y, 10), (e.EV_ABS, e.ABS_Z, 20),
                                               (e.EV_ABS, e.ABS_X, 100), "syn"])

    def test_separate_pedals_device_has_no_clutch(self):
        caps = self.mod.virtual_capabilities(self.wheel, separate=True)
        self.assertEqual([code for code, _ in caps[e.EV_ABS]], [e.ABS_X, e.ABS_Y, e.ABS_Z, e.ABS_HAT0X])
        self.assertEqual(caps[e.EV_ABS][1][1].max, 255)

    def test_separate_pedals_rest_released(self):
        info = {e.ABS_Y: AbsInfo(0, 0, 255, 0, 0, 0), e.ABS_Z: AbsInfo(0, 0, 255, 0, 0, 0)}
        self.mod.neutral(self.virtual, True, info, at_max=True)
        self.assertEqual(self.virtual.events, [(e.EV_ABS, e.ABS_Y, 255), (e.EV_ABS, e.ABS_Z, 255), "syn"])

    def test_force_feedback_is_forwarded(self):
        self.bridge.virtual_event(ev(e.EV_UINPUT, e.UI_FF_UPLOAD, 0))
        self.bridge.virtual_event(ev(e.EV_UINPUT, e.UI_FF_UPLOAD, 0))  # update of effect 0
        self.bridge.virtual_event(ev(e.EV_FF, 0, 1))
        self.bridge.virtual_event(ev(e.EV_FF, e.FF_GAIN, 0xC000))
        self.bridge.virtual_event(ev(e.EV_UINPUT, e.UI_FF_ERASE, 0))
        self.assertEqual(self.wheel.uploaded, [-1, 11])
        self.assertEqual([u.retval for u in self.virtual.uploads], [0, 0])
        self.assertEqual([u.effect.id for u in self.virtual.uploads], [0, 0])
        self.assertEqual(self.wheel.written, [(e.EV_FF, 11, 1), (e.EV_FF, e.FF_GAIN, 0xC000)])
        self.assertEqual(self.wheel.erased, [11])
        self.assertEqual(self.bridge.effects, {})

    def test_reset_wheel_gets_the_games_force_feedback_back(self):
        for code, value in ((e.UI_FF_UPLOAD, 0), (e.UI_FF_UPLOAD, 1), (e.UI_FF_UPLOAD, 2)):
            self.bridge.virtual_event(ev(e.EV_UINPUT, code, value))
        self.bridge.virtual_event(ev(e.EV_FF, e.FF_AUTOCENTER, 0))
        self.bridge.virtual_event(ev(e.EV_FF, 0, 1))
        self.bridge.virtual_event(ev(e.EV_FF, 1, 1))
        self.bridge.virtual_event(ev(e.EV_FF, 1, 0))  # stopped
        self.bridge.virtual_event(ev(e.EV_UINPUT, e.UI_FF_ERASE, 2))
        # The wheel re-enumerates: a fresh device, same game state.
        wheel = FakeWheel()
        bridge = self.mod.Bridge(wheel, self.virtual, True, force=self.bridge.force)
        bridge.restore()
        self.assertEqual(wheel.uploaded, [-1, -1])
        self.assertEqual(bridge.effects, {0: 11, 1: 12})
        self.assertEqual(wheel.written, [(e.EV_FF, e.FF_AUTOCENTER, 0), (e.EV_FF, 11, 1)])
        # The game's ids keep working on the new wheel.
        bridge.virtual_event(ev(e.EV_FF, 1, 1))
        self.assertEqual(wheel.written[-1], (e.EV_FF, 12, 1))


if __name__ == "__main__":
    unittest.main()
