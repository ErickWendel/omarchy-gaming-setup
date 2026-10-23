import importlib.machinery
import importlib.util
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace

try:
    from evdev import ecodes as e
except ImportError:  # python-evdev is installed by scripts/packages.sh
    e = None

BRIDGE = Path(__file__).parents[1] / "components/handbrake/omarchy-handbrake-bridge"


def load_bridge():
    loader = importlib.machinery.SourceFileLoader("handbrake_bridge", str(BRIDGE))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


class FakeSource:
    path = "/dev/input/fake"
    name = "fake handbrake"

    def __init__(self, values):
        self.events = [SimpleNamespace(type=e.EV_ABS, code=e.ABS_RUDDER, value=v) for v in values]

    def grab(self):
        pass

    def read_loop(self):
        return iter(self.events)


class FakeVirtual:
    device = SimpleNamespace(path="/dev/input/virtual")

    def __init__(self):
        self.buttons = []

    def write(self, kind, code, value):
        if kind == e.EV_KEY:
            self.buttons.append(value)

    def syn(self):
        pass


@unittest.skipIf(e is None, "python-evdev is not installed")
class HandbrakeBridgeTests(unittest.TestCase):
    def setUp(self):
        self.bridge = load_bridge()
        self.absinfo = SimpleNamespace(min=0, max=100)
        self.tmp = tempfile.TemporaryDirectory()
        self.bridge.AXIS_ONLY_FLAG = f"{self.tmp.name}/axis-only"

    def tearDown(self):
        self.tmp.cleanup()

    def pull_twice(self):
        virtual = FakeVirtual()
        self.bridge.bridge(FakeSource([0, 60, 20, 70, 10]), self.absinfo, virtual)
        return virtual.buttons

    def test_lever_presses_the_button(self):
        self.assertEqual(self.pull_twice(), [1, 0, 1, 0])

    def test_axis_only_flag_skips_the_button(self):
        Path(self.bridge.AXIS_ONLY_FLAG).touch()
        self.assertEqual(self.pull_twice(), [])


if __name__ == "__main__":
    unittest.main()
