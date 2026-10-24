import importlib.machinery
import importlib.util
from pathlib import Path
import struct
import unittest

BRIDGE = Path(__file__).parents[1] / "components/f1-2020/f1-2020-rev-lights"


def load_bridge():
    loader = importlib.machinery.SourceFileLoader("f1_2020_rev_lights", str(BRIDGE))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


bridge = load_bridge()


def header(packet_id, player=0, packet_format=2020):
    return struct.pack("<HBBBBQfIBB", packet_format, 1, 18, 1, packet_id, 1, 0.0, 0, player, 255)


def telemetry(player_car, player=0, other=None):
    other = other or player_car
    cars = [player_car if i == player else other for i in range(22)]
    return header(6, player) + b"".join(cars) + struct.pack("<IBBb", 0, 255, 255, 0)


def telemetry_car(speed_kmh, throttle, brake, gear, rpm):
    car = struct.pack("<HfffBbHBB4H4B4BH4f4B", speed_kmh, throttle, 0.0, brake, 0, gear, rpm, 0, 50,
                      *[500] * 4, *[90] * 4, *[90] * 4, 100, *[23.0] * 4, *[0] * 4)
    assert len(car) == 58
    return car


def status(max_rpm, player=0):
    def car(top):
        data = struct.pack("<5B3f2H2BH4B3B4B6Bbf B3f".replace(" ", ""), 0, 0, 1, 56, 0, 50.0, 110.0, 20.0,
                           top, 4000, 8, 0, 0, *[0] * 4, 16, 16, 1, *[0] * 4, *[0] * 6, 0, 2e6, 1, 0.0, 0.0, 0.0)
        assert len(data) == 60
        return data
    return header(7, player) + b"".join(car(max_rpm if i == player else 9999) for i in range(22))


class RevLightsTest(unittest.TestCase):
    def test_reads_the_player_cars_redline(self):
        self.assertEqual(bridge.max_rpm_from_status(status(12000, player=3)), 12000.0)

    def test_translates_the_player_car(self):
        packet = telemetry(telemetry_car(180, 0.75, 0.25, 5, 10500), player=2,
                           other=telemetry_car(90, 0.0, 1.0, 2, 5000))
        datagram = bridge.translate(packet, 12000.0)
        magic, version, _, game, rpm, top, throttle, gear, shift, speed, brake = bridge.LTFR.unpack(datagram)
        self.assertEqual((magic, version, game.rstrip(b"\0")), (b"LTFR", 2, b"f1-2020"))
        self.assertEqual((rpm, top, gear, shift), (10500.0, 12000.0, 5, 0.0))
        self.assertAlmostEqual(throttle, 0.75)
        self.assertAlmostEqual(brake, 0.25)
        self.assertAlmostEqual(speed, 50.0)

    def test_reverse_is_minus_one(self):
        datagram = bridge.translate(telemetry(telemetry_car(5, 0.3, 0.0, -1, 6000)), 12000.0)
        self.assertEqual(bridge.LTFR.unpack(datagram)[7], -1)

    def test_ignores_other_packet_formats(self):
        packet = header(6, packet_format=2021) + telemetry(telemetry_car(100, 1, 0, 3, 9000))[24:]
        self.assertIsNone(bridge.translate(packet, 12000.0))
        self.assertIsNone(bridge.max_rpm_from_status(b"short"))


if __name__ == "__main__":
    unittest.main()
