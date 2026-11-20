import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock

ROOT = Path(__file__).parents[1] / "components/backstagehero"
SPEC = importlib.util.spec_from_file_location("video_filter", ROOT / "video_filter.py")
VF = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VF)

HAVE_FFMPEG = bool(shutil.which("ffmpeg") and shutil.which("ffprobe"))


def rejected(title, channel="", description="", song=""):
    return VF.judge(title, channel, description, song)[1] is not None


class JudgeTest(unittest.TestCase):
    def test_audio_uploads_rejected(self):
        for title in [
            "Foo Fighters - Everlong (Official Audio)",
            "Everlong [Audio]",
            "Everlong (Official HD Audio)",
            "Metallica - Master of Puppets (Full Album)",
            "Everlong - Nightcore",
            "Everlong (slowed + reverb)",
            "Everlong 100% FC Expert+ Clone Hero",
            "Everlong - Guitar Hero World Tour",
            "Everlong (Karaoke Version)",
        ]:
            self.assertTrue(rejected(title), title)

    def test_art_tracks_rejected(self):
        self.assertTrue(rejected("Everlong", channel="Foo Fighters - Topic"))
        self.assertTrue(rejected("Everlong", description="Provided to YouTube by RCA Records\n\nEverlong"))

    def test_real_videos_kept(self):
        for title in [
            "Foo Fighters - Everlong (Official HD Video)",
            "Everlong (Live At Wembley Stadium, 2008)",
            "Foo Fighters - Everlong",
            "Everlong (Official Music Video)",
        ]:
            self.assertFalse(rejected(title, channel="Foo Fighters"), title)

    def test_song_name_does_not_count(self):
        # A song called "Audio" or "Live Forever" is not an audio upload / live set.
        self.assertFalse(rejected("Sia - Audio (Official Video)", song="Sia Audio"))
        live = VF.judge("Oasis - Live Forever", song="Oasis Live Forever")
        plain = VF.judge("Oasis - Live Forever", song="")
        self.assertLess(live[0], plain[0])

    def test_scores(self):
        mv = VF.judge("Song (Official Music Video)", "ArtistVEVO")[0]
        live = VF.judge("Song (Live at Rock in Rio)")[0]
        plain = VF.judge("Artist - Song")[0]
        lyric = VF.judge("Artist - Song (Lyrics)")[0]
        self.assertGreater(mv, live)
        self.assertGreater(live, plain)
        self.assertGreater(plain, lyric)


class RankTest(unittest.TestCase):
    def test_order_and_drop(self):
        entries = [
            {"id": "a", "title": "Band - Song (Official Audio)", "channel": "Band"},
            {"id": "b", "title": "Song", "channel": "Band - Topic"},
            {"id": "c", "title": "Band - Song (Lyrics)", "channel": "x"},
            {"id": "d", "title": "Band - Song", "channel": "Band"},
            {"id": "e", "title": "Band - Song (Official Video)", "channel": "BandVEVO"},
            {"id": "f", "title": "Band - Song (Official Video)", "channel": "Band"},
        ]
        kept, dropped = VF.rank(entries, song="Band Song", rejected_ids={"f"})
        self.assertEqual([e["id"] for e in kept], ["e", "d", "c"])
        self.assertEqual({e["id"] for e, _ in dropped}, {"a", "b", "f"})


class FakeYDL:
    results = {}

    def __init__(self, opts):
        pass

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def extract_info(self, q, download=False):
        query = q.split(":", 1)[1]
        return {"entries": FakeYDL.results.get(query, [])}


def fake_vd():
    vd = types.SimpleNamespace(
        SEARCH_RESULTS=5,
        _base_opts=lambda: {},
        yt_dlp=types.SimpleNamespace(YoutubeDL=FakeYDL),
        is_bot_error=lambda e: False,
        BotDetected=type("BotDetected", (Exception,), {}),
        video_id_of=lambda url: url.rsplit("=", 1)[-1],
    )
    vd.download_video = mock.Mock()
    return vd


class InstallTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.env = mock.patch.dict(os.environ, {"XDG_STATE_HOME": self.tmp,
                                                "OMARCHY_BACKSTAGEHERO_FILTER": "1"})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        shutil.rmtree(self.tmp)

    def test_search_reranks_and_falls_back(self):
        vd = fake_vd()
        VF.install(vd)
        FakeYDL.results = {
            "Band Song": [
                {"id": "a", "title": "Band - Song (Official Audio)", "duration": 200},
                {"id": "b", "title": "Band - Song (Official Video)", "duration": 230},
            ],
        }
        with mock.patch("builtins.print"):
            got = vd.search_candidates("Band Song")
        self.assertEqual(got, [("https://www.youtube.com/watch?v=b", "Band - Song (Official Video)", 230)])

        FakeYDL.results = {
            "Band Song": [{"id": "a", "title": "Band - Song (Official Audio)"}],
            "Band Song official video": [{"id": "c", "title": "Band - Song"}],
        }
        with mock.patch("builtins.print"):
            self.assertEqual(vd.search_candidates("Band Song")[0][0], "https://www.youtube.com/watch?v=c")
            FakeYDL.results["Band Song official video"] = []
            with self.assertRaises(Exception):
                vd.search_candidates("Band Song")

    def test_static_download_rejected_and_old_video_kept(self):
        vd = fake_vd()
        folder = Path(self.tmp) / "song"
        folder.mkdir()
        final = folder / "video.mp4"
        final.write_bytes(b"old")

        def download(folder_, url, quality, info=None):
            os.replace(Path(folder_) / "new", final)  # like BackstageHero's rename
        (folder / "new").write_bytes(b"new")
        vd.download_video = download
        resolver = types.SimpleNamespace(resolve=lambda h: {"video_id": "zzz"})
        VF.install(vd, resolver)
        with mock.patch.object(VF, "check_video", return_value=(True, 0.0)), \
                mock.patch("builtins.print"):
            with self.assertRaises(VF.StaticVideo):
                vd.download_video(str(folder), "https://www.youtube.com/watch?v=zzz", "q")
            self.assertEqual(final.read_bytes(), b"old")
            self.assertFalse((folder / "video.omarchy-prev.mp4").exists())
            self.assertIn("zzz", VF.rejected_ids())
            self.assertIsNone(resolver.resolve("hash"))

        # No earlier video: the still one is removed.
        final.unlink()
        (folder / "new").write_bytes(b"new")
        with mock.patch.object(VF, "check_video", return_value=(True, 0.0)), \
                mock.patch("builtins.print"), self.assertRaises(VF.StaticVideo):
            vd.download_video(str(folder), "https://www.youtube.com/watch?v=y", "q")
        self.assertFalse(final.exists())

        # A moving video stays.
        (folder / "new").write_bytes(b"new")
        with mock.patch.object(VF, "check_video", return_value=(False, 0.9)):
            vd.download_video(str(folder), "https://www.youtube.com/watch?v=y", "q")
        self.assertEqual(final.read_bytes(), b"new")

    def test_disabled(self):
        vd = fake_vd()
        orig = vd.download_video
        with mock.patch.dict(os.environ, {"OMARCHY_BACKSTAGEHERO_FILTER": "0"}):
            VF.install(vd)
        self.assertIs(vd.download_video, orig)
        self.assertFalse(hasattr(vd, "search_candidates"))


class RunnerTest(unittest.TestCase):
    def test_gui_runs_with_filter_hooked(self):
        with tempfile.TemporaryDirectory() as src:
            Path(src, "VideoDownload.py").write_text(
                "SEARCH_RESULTS = 5\n"
                "def download_video(*a, **k): pass\n"
                "def search_candidates(*a, **k): pass\n")
            Path(src, "resolver_client.py").write_text("def resolve(h): return None\n")
            Path(src, "gui.py").write_text(
                "import sys, VideoDownload, resolver_client\n"
                "print(__name__, VideoDownload.search_candidates.__module__,\n"
                "      resolver_client.resolve.__module__, sys.argv[1:])\n")
            out = subprocess.run(
                [sys.executable, "-I", str(ROOT / "omarchy-bh-run.py"), src, "--x"],
                capture_output=True, text=True, check=True,
                env={**os.environ, "OMARCHY_BACKSTAGEHERO_FILTER": "1"}).stdout
        self.assertEqual(out.strip(), "__main__ video_filter video_filter ['--x']")


@unittest.skipUnless(HAVE_FFMPEG, "no ffmpeg")
class FramesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        lib = Path(cls.tmp) / "lib"

        def make(name, src, *codec):
            d = lib / name
            d.mkdir(parents=True)
            (d / "song.ini").write_text(f"[song]\nname = x\nbackstagehero_source = id-{name}\n")
            subprocess.run(["ffmpeg", "-nostdin", "-loglevel", "error", "-f", "lavfi", "-i", src,
                            *codec, str(d / "bg.webm")], check=True)
        # A cover image held for 30 s, encoded the way still uploads are (long GOP).
        make("still", "color=c=red:size=320x180:rate=10:duration=30",
             "-c:v", "libvpx", "-g", "300")
        make("still2", "smptebars=size=320x180:rate=10:duration=30", "-c:v", "libvpx")
        make("moving", "testsrc2=size=320x180:rate=10:duration=30", "-c:v", "libvpx")
        make("cuts", "mandelbrot=size=320x180:rate=10,trim=duration=30", "-c:v", "libvpx")
        cls.lib = lib

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def test_check_video(self):
        self.assertTrue(VF.check_video(str(self.lib / "still2/bg.webm"))[0])
        self.assertFalse(VF.check_video(str(self.lib / "moving/bg.webm"))[0])
        self.assertFalse(VF.check_video(str(self.lib / "cuts/bg.webm"))[0])

    def test_scan_and_quarantine(self):
        with open(os.devnull, "w") as out:
            found = VF.scan([str(self.lib)], out=out)
        self.assertEqual(sorted(Path(f).name for f, _ in found), ["still", "still2"])
        with open(os.devnull, "w") as out, \
                mock.patch.dict(os.environ, {"XDG_STATE_HOME": self.tmp}):
            VF.scan([str(self.lib)], quarantine=True, out=out)
            self.assertEqual(VF.rejected_ids(), {"id-still", "id-still2"})
        self.assertFalse((self.lib / "still2/bg.webm").exists())
        self.assertTrue((self.lib / VF.QUARANTINE / "still2/bg.webm").exists())
        self.assertTrue((self.lib / "still2/song.ini").exists())
        self.assertTrue((self.lib / "moving/bg.webm").exists())
        # Quarantined videos are not scanned again.
        with open(os.devnull, "w") as out:
            self.assertEqual(VF.scan([str(self.lib)], out=out), [])


if __name__ == "__main__":
    unittest.main()
