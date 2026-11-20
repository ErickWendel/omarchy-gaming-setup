#!/usr/bin/env python3
"""Starts BackstageHero's gui.py with video_filter hooked into its download code.

Run with the BackstageHero venv's Python: omarchy-bh-run.py SRC_DIR [args...]
video_filter.py sits next to this file (both installed by install.sh).
"""
import os
import runpy
import sys

here = os.path.dirname(os.path.abspath(__file__))
src = os.path.abspath(sys.argv[1])
sys.argv = [os.path.join(src, 'gui.py')] + sys.argv[2:]
sys.path[:0] = [src, here]

import video_filter  # noqa: E402
import VideoDownload  # noqa: E402
try:
    import resolver_client  # noqa: E402
except ImportError:
    resolver_client = None
try:
    video_filter.install(VideoDownload, resolver_client)
except Exception as e:  # an upstream change must not stop the app from starting
    print(f'omarchy-bh-run: video filter not installed ({e})', file=sys.stderr)
runpy.run_path(sys.argv[0], run_name='__main__')
