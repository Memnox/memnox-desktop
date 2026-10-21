#!/usr/bin/env python3
"""Writes Memnox's cue sounds into Support/Sounds, one WAV per Cue in MemnoxVoiceCore.

Synthesised here rather than recorded or licensed, so every sound is Memnox's own and the set can be
retuned by changing a number. Every cue is in D major and struck on the same two FM voices, a glass bell
and a soft marimba, then given the same small room, so ten cues read as one family. Setup also gets a calm
looping bed, ambience(). Standard library only, and afconvert to make the bed small.

    python3 scripts/make-sounds.py
"""

import math
import random
import struct
import subprocess
import wave
from pathlib import Path

RATE = 48_000
# Peak level, under full scale so nothing clips and the app's own volume does the rest.
PEAK = 0.5
# A fade this short is not heard as one, but it takes away the click of a sound cut mid wave.
EDGE = 0.004
# The two channels a few cents apart, which is what makes a tone sound wide rather than come from a point.
DETUNE_CENTS = 4
OUT = Path(__file__).resolve().parent.parent / "Support" / "Sounds"

Track = list[float]
# The ear being drawn, as a pitch multiple, set by stereo() for each side in turn.
DETUNE = 1.0


def hz(note: str) -> float:
    """A note name such as D5 or F#6 as a frequency, with A4 at 440."""
    names = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}
    pitch, octave = note[:-1], int(note[-1])
    return 440.0 * 2 ** ((names[pitch] + 12 * (octave - 4)) / 12)


def tuned(note: str) -> float:
    """The note as the side being drawn hears it."""
    return hz(note) * DETUNE


def fm(freq: float, seconds: float, ratio: float, index: float, index_decay: float, decay: float,
       attack: float = 0.002) -> Track:
    """One FM strike: a bright edge from the modulator that dies away into the pure tone underneath it."""
    out = []
    for i in range(int(seconds * RATE)):
        t = i / RATE
        bend = index * math.exp(-index_decay * t)
        tone = math.sin(2 * math.pi * freq * t + bend * math.sin(2 * math.pi * freq * ratio * t))
        out.append(min(1.0, t / attack) * math.exp(-decay * t) * tone)
    return out


def bell(note: str, seconds: float = 1.0, bright: float = 1.0, decay: float = 4.0) -> Track:
    """Glass: an inharmonic ratio is what makes a strike read as a bell rather than a string."""
    return fm(tuned(note), seconds, ratio=3.5, index=2.2 * bright, index_decay=9, decay=decay)


def marimba(note: str, seconds: float = 0.5, decay: float = 9.0, soft: float = 1.0) -> Track:
    """Wood: a whole number ratio and a quick fading edge, warm and short."""
    return fm(tuned(note), seconds, ratio=4.0, index=1.6 * soft, index_decay=30, decay=decay, attack=0.004)


def bloom(note: str, seconds: float) -> Track:
    """A soft swell with no strike at all, for the cue that should barely be noticed."""
    out = []
    count = int(seconds * RATE)
    for i in range(count):
        t, progress = i / RATE, i / count
        envelope = math.sin(math.pi * progress) ** 2
        out.append(envelope * (math.sin(2 * math.pi * tuned(note) * t) + 0.2 * math.sin(2 * math.pi * 2 * tuned(note) * t)))
    return out


def tap(seconds: float, seed: int) -> Track:
    """A breath of filtered noise, the air under a light touch."""
    rng, out, low = random.Random(seed), [], 0.0
    for i in range(int(seconds * RATE)):
        low += 0.12 * (rng.uniform(-1, 1) - low)
        out.append(low * math.exp(-60 * i / RATE))
    return out


def mix(*parts: tuple[float, Track, float]) -> Track:
    """Lays each (start seconds, samples, gain) onto one track."""
    length = max(int(start * RATE) + len(samples) for start, samples, _ in parts)
    track = [0.0] * length
    for start, samples, gain in parts:
        offset = int(start * RATE)
        for i, sample in enumerate(samples):
            track[offset + i] += gain * sample
    return track


def low_pass(samples: Track, cutoff: float) -> Track:
    """One pole, enough to take the glare off a cue or soften one that says something went wrong."""
    alpha = 1 - math.exp(-2 * math.pi * cutoff / RATE)
    out, last = [], 0.0
    for sample in samples:
        last += alpha * (sample - last)
        out.append(last)
    return out


def high_pass(samples: Track, cutoff: float) -> Track:
    """Takes out the rumble under a cue, which laptop speakers only turn into mud."""
    return [s - l for s, l in zip(samples, low_pass(samples, cutoff))]


def room(samples: Track, seed_delays: tuple[int, ...], wet: float, decay_seconds: float) -> Track:
    """A small room: four combs in parallel and two allpasses after them, the classic Schroeder shape."""
    tail = int(decay_seconds * RATE)
    dry = samples + [0.0] * tail
    combs = []
    for delay in seed_delays:
        feedback = 10 ** (-3 * delay / (decay_seconds * RATE))
        buffer, out = [0.0] * delay, []
        for i, sample in enumerate(dry):
            echo = buffer[i % delay]
            buffer[i % delay] = sample + echo * feedback * 0.98
            out.append(echo)
        combs.append(out)
    wet_track = [sum(c[i] for c in combs) / len(combs) for i in range(len(dry))]
    for delay, gain in ((347, 0.7), (113, 0.7)):
        buffer, out = [0.0] * delay, []
        for i, sample in enumerate(wet_track):
            delayed = buffer[i % delay]
            value = -gain * sample + delayed
            buffer[i % delay] = sample + gain * value
            out.append(value)
        wet_track = out
    return [d + wet * w for d, w in zip(dry, wet_track)]


def stereo(make) -> tuple[Track, Track]:
    """The cue drawn twice a few cents apart and put in two slightly different rooms, one per ear."""
    global DETUNE
    sides = []
    for cents, delays in ((-DETUNE_CENTS / 2, (1557, 1617, 1491, 1422)), (DETUNE_CENTS / 2, (1580, 1640, 1514, 1445))):
        DETUNE = 2 ** (cents / 1200)
        dry = high_pass(low_pass(make(), 9000), 160)
        sides.append(room(dry, delays, wet=0.22, decay_seconds=0.7))
    DETUNE = 1.0
    length = max(len(side) for side in sides)
    return tuple(side + [0.0] * (length - len(side)) for side in sides)


CUES = {
    # The orb opens: two light notes up, the question being asked of it.
    "listening": lambda: mix((0, marimba("A5", 0.25, decay=14), 0.9), (0.06, marimba("D6", 0.3, decay=12), 1.0)),
    # What they said is on its way: one soft touch.
    "sent": lambda: mix((0, marimba("F#6", 0.14, decay=30, soft=0.6), 1.0), (0, tap(0.04, 1), 0.2)),
    # An agent is waiting on them: two glass tones a fifth apart, unhurried enough to be heard over work.
    "held": lambda: mix((0, bell("D6", 1.1, decay=3.2), 1.0), (0.17, bell("A5", 1.1, decay=3.2), 0.85)),
    # An allow was signed: the chord climbing, quick and settled.
    "allowed": lambda: mix(*[(i * 0.05, marimba(n, 0.55, decay=7), 0.8) for i, n in enumerate(["D5", "F#5", "A5", "D6"])]),
    # Left as it was: two notes falling, muted, never a buzzer.
    "declined": lambda: low_pass(mix((0, marimba("A5", 0.3, decay=11, soft=0.5), 1.0), (0.09, marimba("E5", 0.4, decay=9, soft=0.5), 0.9)), 2200),
    # Done as asked: one clear glass strike with its octave over it.
    "done": lambda: mix((0, bell("D6", 0.8, bright=0.8, decay=5), 1.0), (0.025, bell("D7", 0.5, bright=0.4, decay=8), 0.3)),
    # An agent finished its work: a rising fourth that comes to rest, warmer and slower than done.
    "finished": lambda: mix((0, bell("A5", 0.8, bright=0.6, decay=4.5), 0.8), (0.14, bell("D6", 1.2, bright=0.7, decay=2.8), 1.0)),
    # Could not be done: low and soft, a minor third down, noticed without alarm.
    "failed": lambda: low_pass(mix((0, marimba("F4", 0.45, decay=7, soft=0.7), 1.0), (0.12, marimba("D4", 0.55, decay=5.5, soft=0.7), 1.0)), 1400),
    # Answered somewhere else: one low swell that comes and goes, the quietest of the set.
    "settled": lambda: bloom("D5", 0.4),
    # The orb closes: the opening, falling.
    "closed": lambda: mix((0, marimba("D6", 0.25, decay=14), 0.9), (0.06, marimba("A5", 0.3, decay=12), 1.0)),
}

# Each cue's level after the peaks are matched: a swell carries more energy than a strike at the same peak, and settled
# sits lowest because nothing waits on it.
LEVEL = {"settled": 0.45, "sent": 0.8}


def finished(left: Track, right: Track, level: float) -> tuple[Track, Track]:
    """Trailing quiet trimmed, edges faded, and both ears set to one peak so every cue starts equally loud."""
    while left and abs(left[-1]) < 2e-4 and abs(right[-1]) < 2e-4:
        left.pop()
        right.pop()
    edge = int(EDGE * RATE)
    for side in (left, right):
        for i in range(min(edge, len(side))):
            side[i] *= i / edge
            side[-1 - i] *= i / edge
    top = max(max(abs(s) for s in left), max(abs(s) for s in right)) or 1.0
    scale = level * PEAK / top
    pad = [0.0] * int(0.01 * RATE)
    return [s * scale for s in left] + pad, [s * scale for s in right] + pad


def write(path: Path, left: Track, right: Track) -> None:
    frames = b"".join(struct.pack("<hh", int(l * 32767), int(r * 32767)) for l, r in zip(left, right))
    with wave.open(str(path), "wb") as out:
        out.setnchannels(2)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(frames)


# The bed under setup: four chords of D major, each held and breathed into the next, with no beat and no tune, so it
# calms the room and never competes with the voice. Voiced low and open, every note a sine with a soft octave over it.
AMBIENCE_CHORDS = [
    ["D3", "A3", "E4", "F#4", "C#5"],
    ["B2", "F#3", "C#4", "D4", "A4"],
    ["G2", "D3", "A3", "B3", "F#4"],
    ["A2", "E3", "B3", "C#4", "E4"],
]
AMBIENCE_CHORD_SECONDS = 9.0
# Each note swells on its own slow wave, so the chord moves inside itself while it is held.
AMBIENCE_SWELL_HZ = (0.05, 0.13)
# Long enough that the end blending into the start is never heard as a change.
AMBIENCE_SEAM_SECONDS = 2.0


def ambience_cycle(cycles: int) -> tuple[Track, Track]:
    """The progression played `cycles` times, the chords crossfading on a raised cosine so no change is heard as a cut."""
    length = int(AMBIENCE_CHORD_SECONDS * len(AMBIENCE_CHORDS) * cycles * RATE)
    chord_samples = AMBIENCE_CHORD_SECONDS * RATE
    rng = random.Random(7)
    voices = []
    for chord_index, chord in enumerate(AMBIENCE_CHORDS):
        for note in chord:
            voices.append((chord_index, hz(note), rng.uniform(*AMBIENCE_SWELL_HZ), rng.uniform(0, 2 * math.pi)))
    sides = []
    for cents in (-3.0, 3.0):
        detune = 2 ** (cents / 1200)
        out = [0.0] * length
        for chord_index, freq, swell_hz, swell_phase in voices:
            f = freq * detune
            for i in range(length):
                # Where this chord stands in the progression, wrapped, so the last chord breathes into the first.
                position = (i / chord_samples - chord_index) % len(AMBIENCE_CHORDS)
                distance = min(position, len(AMBIENCE_CHORDS) - position)
                if distance >= 1:
                    continue
                presence = 0.5 + 0.5 * math.cos(math.pi * distance)
                t = i / RATE
                swell = 0.65 + 0.35 * math.sin(2 * math.pi * swell_hz * t + swell_phase)
                out[i] += presence * swell * (math.sin(2 * math.pi * f * t) + 0.22 * math.sin(4 * math.pi * f * t))
        sides.append(out)
    return sides[0], sides[1]


def ambience() -> tuple[Track, Track]:
    """Two cycles through the room and only the second kept, so its start already carries the tail of the end. Its last
    seconds are crossfaded into the seconds just before it starts, since the notes' own phases do not come round in step
    with the chords, and without it the wrap from end to start is a click."""
    left, right = ambience_cycle(2)
    one = len(left) // 2
    fade = int(AMBIENCE_SEAM_SECONDS * RATE)
    rooms = ((1557, 1617, 1491, 1422), (1580, 1640, 1514, 1445))
    shaped = []
    for side, delays in zip((left, right), rooms):
        wet = room(low_pass(side, 2400), delays, wet=0.45, decay_seconds=2.5)
        loop = wet[one:2 * one]
        for k in range(fade):
            # Equal power, so the level holds steady through the crossfade.
            angle = (k / fade) * math.pi / 2
            loop[-fade + k] = loop[-fade + k] * math.cos(angle) + wet[one - fade + k] * math.sin(angle)
        shaped.append(loop)
    top = max(max(abs(s) for s in shaped[0]), max(abs(s) for s in shaped[1])) or 1.0
    return [s * PEAK / top for s in shaped[0]], [s * PEAK / top for s in shaped[1]]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name, make in CUES.items():
        left, right = finished(*stereo(make), LEVEL.get(name, 1.0))
        write(OUT / f"{name}.wav", left, right)
        print(f"{name}.wav  {len(left) / RATE:.2f}s")
    # The bed is long, so it ships as AAC, a tenth the size, where this Mac's afconvert can encode it; otherwise as a
    # mono WAV at half the rate, which loses nothing of a pad already filtered under 2.4 kHz.
    left, right = ambience()
    wav = OUT / "setup-ambience.wav"
    m4a = OUT / "setup-ambience.m4a"
    write(wav, left, right)
    encoded = subprocess.run(["/usr/bin/afconvert", "-f", "m4af", "-d", "aac", "-b", "96000", str(wav), str(m4a)],
                             capture_output=True).returncode == 0
    if encoded:
        wav.unlink()
        print(f"setup-ambience.m4a  {len(left) / RATE:.1f}s loop")
        return
    m4a.unlink(missing_ok=True)
    mono = [(l + r) / 2 for l, r in zip(left[::2], right[::2])]
    with wave.open(str(wav), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE // 2)
        out.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in mono))
    print(f"setup-ambience.wav  {len(mono) / (RATE // 2):.1f}s loop, mono, since this afconvert cannot encode AAC")


if __name__ == "__main__":
    main()
