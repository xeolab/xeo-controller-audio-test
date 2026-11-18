#!/usr/bin/env python3
"""Generate isolated-channel FLAC test tones using Python and ffmpeg."""

import math
from pathlib import Path
import struct
import subprocess
import tempfile

SAMPLE_RATE = 48_000
SLOT_SECONDS = 0.95
TONE_SECONDS = 0.64
SAMPLES = Path(__file__).resolve().parents[1] / "App" / "Samples"


def make_sample(output, layout, playback_order):
    channels = len(playback_order)
    frames_per_slot = round(SAMPLE_RATE * SLOT_SECONDS)
    tone_frames = round(SAMPLE_RATE * TONE_SECONDS)
    with tempfile.TemporaryDirectory() as temp_dir:
        raw = Path(temp_dir) / "test.pcm"
        with raw.open("wb") as pcm:
            for channel in playback_order:
                frequency = 65 if channels > 2 and channel == 3 else 550
                frame = [0] * channels
                for index in range(tone_frames):
                    seconds = index / SAMPLE_RATE
                    envelope = min(1, seconds / 0.025, (TONE_SECONDS - seconds) / 0.04)
                    frame[channel] = int(6000 * envelope * math.sin(math.tau * frequency * seconds))
                    pcm.write(struct.pack(f"<{channels}h", *frame))
                pcm.write(bytes(2 * channels * (frames_per_slot - tone_frames)))
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-f", "s16le", "-ar", str(SAMPLE_RATE),
             "-ch_layout", layout, "-i", str(raw), "-c:a", "flac", str(output)],
            check=True,
        )


if __name__ == "__main__":
    SAMPLES.mkdir(parents=True, exist_ok=True)
    make_sample(SAMPLES / "stereo.flac", "stereo", [0, 1])
    make_sample(SAMPLES / "surround51.flac", "5.1(side)", [0, 1, 2, 3, 4, 5])
    # FFmpeg's 7.1 PCM order places rear surrounds before side surrounds.
    make_sample(SAMPLES / "surround71.flac", "7.1", [0, 1, 2, 3, 6, 7, 4, 5])
