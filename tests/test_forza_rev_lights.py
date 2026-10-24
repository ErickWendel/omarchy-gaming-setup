import importlib.machinery
import importlib.util
from pathlib import Path
import socket
import struct
import tempfile
import threading
import unittest

WRAPPER = Path(__file__).parents[1] / "components/forza-horizon-5/forza-rev-lights"
CONFIGURE = Path(__file__).parents[1] / "components/forza-horizon-5/configure_steam.py"


def load(path, name):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def forza_packet(race_on=1, max_rpm=7500.0, rpm=4500.0, speed=20.0, accel=255, brake=0, gear=3, length=324):
    packet = bytearray(324)
    struct.pack_into("<iIfff", packet, 0, race_on, 0, max_rpm, 1000.0, rpm)
    struct.pack_into("<f", packet, 256, speed)
    packet[315], packet[316], packet[319] = accel, brake, gear
    return bytes(packet[:length])


class TranslateTests(unittest.TestCase):
    def setUp(self):
        self.bridge = load(WRAPPER, "forza_rev_lights")

    def decode(self, datagram):
        self.assertEqual(len(datagram), 40)
        return self.bridge.LTFR.unpack(datagram)

    def test_driving_packet_becomes_ltfr(self):
        magic, version, flags, game, rpm, max_rpm, throttle, gear, shift, speed, brake = self.decode(
            self.bridge.translate(forza_packet(brake=51))
        )
        self.assertEqual((magic, version, flags), (b"LTFR", 2, 0))
        self.assertEqual(game.rstrip(b"\0"), b"forza")
        self.assertEqual((rpm, max_rpm, gear, shift), (4500.0, 7500.0, 3, 0.0))
        self.assertAlmostEqual(throttle, 1.0)
        self.assertAlmostEqual(brake, 0.2)
        self.assertAlmostEqual(speed, 20.0)

    def test_gears(self):
        self.assertEqual(self.bridge.gear_from_forza(0), -1)
        self.assertEqual(self.bridge.gear_from_forza(1), 1)
        self.assertEqual(self.bridge.gear_from_forza(10), 10)
        self.assertEqual(self.bridge.gear_from_forza(11), 0)

    def test_menus_and_bad_packets_send_nothing(self):
        self.assertIsNone(self.bridge.translate(forza_packet(race_on=0)))
        self.assertIsNone(self.bridge.translate(forza_packet(max_rpm=0.0)))
        self.assertIsNone(self.bridge.translate(forza_packet(rpm=float("nan"))))
        self.assertIsNone(self.bridge.translate(forza_packet(length=311)))  # FM7 Dash
        self.assertIsNone(self.bridge.translate(forza_packet(length=232)))  # Sled

    def test_bridge_forwards_over_udp(self):
        listen = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        listen.bind(("127.0.0.1", 0))
        send = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sink = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sink.bind(("127.0.0.1", 0))
        sink.settimeout(2)
        with tempfile.TemporaryDirectory() as tmp:
            self.bridge.LOG = f"{tmp}/log"
            threading.Thread(target=self.bridge.bridge, args=(listen, send, sink.getsockname()), daemon=True).start()
            send.sendto(forza_packet(rpm=6100.0), listen.getsockname())
            datagram = sink.recv(64)
        self.assertEqual(self.decode(datagram)[4], 6100.0)


class LaunchOptionTests(unittest.TestCase):
    def setUp(self):
        self.configure = load(CONFIGURE, "forza_configure_steam")
        self.wrapper = "/home/u/.local/bin/omarchy-forza-rev-lights"

    def test_wrapper_goes_right_before_command(self):
        options = "PROTON_ENABLE_HIDRAW=0x046D/0xC219 /home/u/.local/bin/omarchy-match-resolution %command%"
        updated = self.configure.with_wrapper(options, self.wrapper)
        self.assertEqual(updated, options.replace("%command%", f"{self.wrapper} %command%"))
        self.assertEqual(self.configure.with_wrapper(updated, self.wrapper), updated)
        self.assertEqual(self.configure.without_wrapper(updated, self.wrapper), options)

    def test_options_without_command(self):
        self.assertEqual(self.configure.with_wrapper("", self.wrapper), f"{self.wrapper} %command%")
        self.assertEqual(self.configure.with_wrapper("-skipintro", self.wrapper), f"{self.wrapper} %command% -skipintro")


if __name__ == "__main__":
    unittest.main()
