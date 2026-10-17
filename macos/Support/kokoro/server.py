"""Kokoro on this Mac, for Memnox's voice.

A tiny HTTP server on 127.0.0.1 that turns a sentence into a WAV with the Kokoro model, so the
app speaks with a natural voice and nothing it says leaves the machine. The model loads once at
start, which is the only slow part; each sentence after that takes a fraction of a second.
"""

import argparse
import importlib.util
import io
import json
import re
import sys
import threading
import types
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import numpy as np
from kokoro_onnx import Kokoro

HERE = Path(__file__).resolve().parent
# One sentence is what the app sends, so anything longer is a mistake rather than a reply.
MOST_CHARACTERS = 1_000

# A line this short is a quick reply such as "Yes, sir." The model rushes one, since its style is
# picked by length, so it is said a touch slower with more room around it.
SHORT_WORDS = 3
SHORT_SLOWER = 0.88
SLOWEST = 0.5

# Silence around every line, so playback starting never swallows the first sound and the last
# word is not cut, and more around a short reply, which has the least to lose.
LEAD_SECONDS = 0.05
TAIL_SECONDS = 0.12
SHORT_LEAD_SECONDS = 0.08
SHORT_TAIL_SECONDS = 0.18
# A fade this short is not heard as one, but it takes away the click of a sound cut mid wave.
FADE_SECONDS = 0.012
# Every line at the same loudness, a little under full scale, so one sentence is never louder
# than the next and nothing clips.
PEAK = 0.85

# Calm pauses where a person breathes: after a comma, and between sentences. Read by kokoro-onnx
# releases that support them; an older one speaks with its own.
CLAUSE_PAUSE = 0.16
SENTENCE_PAUSE = 0.32

# Words said a set way, in the phonemes misaki reads inline: names no dictionary has, and "sir",
# which it gives only a weak stress, so at the end of "Yes, sir." the word all but disappears.
NAMES = {
    "Memnox": {"british": "mˈɛmnɒks", "american": "mˈɛmnɑks"},
    "sir": {"british": "sˈɜː", "american": "sˈɜɹ"},
}


def wav_bytes(samples: np.ndarray, rate: int) -> bytes:
    """Float samples as a 16 bit mono WAV, written with the standard library alone."""
    pcm = (np.clip(samples, -1.0, 1.0) * 32767).astype("<i2").tobytes()
    out = io.BytesIO()
    with wave.open(out, "wb") as file:
        file.setnchannels(1)
        file.setsampwidth(2)
        file.setframerate(rate)
        file.writeframes(pcm)
    return out.getvalue()


def without_neural_fallback() -> None:
    """Misaki imports torch and transformers at the top for a neural fallback it builds only when
    asked; espeak is the fallback here, so they are stood in for rather than installed at gigabytes."""
    for name in ("torch", "transformers"):
        if importlib.util.find_spec(name) is None:
            sys.modules[name] = types.SimpleNamespace(BartForConditionalGeneration=None)


def pronouncer(british: bool):
    """Misaki, the pronunciation Kokoro was trained on, or None where it is not installed."""
    try:
        without_neural_fallback()
        from misaki import en, espeak

        fallback = espeak.EspeakFallback(british=british)
        return en.G2P(trf=False, british=british, fallback=fallback)
    except Exception:  # noqa: BLE001, espeak inside kokoro-onnx speaks instead
        return None


def with_names(text: str, british: bool) -> str:
    """The names no dictionary has, marked with how to say them."""
    accent = "british" if british else "american"
    for name, said in NAMES.items():
        text = re.sub(rf"\b{name}\b", lambda found: f"[{found.group(0)}](/{said[accent]}/)", text, flags=re.IGNORECASE)
    return text


def short_line(text: str) -> bool:
    return len(text.split()) <= SHORT_WORDS


def polished(samples: np.ndarray, rate: int, short: bool) -> np.ndarray:
    """One steady level, soft edges, and room before and after."""
    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    if peak > 0:
        samples = samples * (PEAK / peak)
    fade = min(int(FADE_SECONDS * rate), samples.size // 2)
    if fade > 0:
        ramp = np.linspace(0.0, 1.0, fade, dtype=samples.dtype)
        samples = samples.copy()
        samples[:fade] *= ramp
        samples[-fade:] *= ramp[::-1]
    lead = np.zeros(int((SHORT_LEAD_SECONDS if short else LEAD_SECONDS) * rate), dtype=samples.dtype)
    tail = np.zeros(int((SHORT_TAIL_SECONDS if short else TAIL_SECONDS) * rate), dtype=samples.dtype)
    return np.concatenate([lead, samples, tail])


def created(kokoro: Kokoro, said: str, **options) -> tuple[np.ndarray, int]:
    """Kokoro's create with calm pauses, and without them on a release that does not take them."""
    try:
        return kokoro.create(said, clause_pause=CLAUSE_PAUSE, sentence_pause=SENTENCE_PAUSE, **options)
    except TypeError:
        return kokoro.create(said, **options)


def spoken(kokoro: Kokoro, pronouncers: dict, text: str, voice: str, speed: float, lang: str) -> tuple[np.ndarray, int]:
    """The line as audio: pronounced by misaki where it is installed, a short reply slowed a little."""
    short = short_line(text)
    pace = max(SLOWEST, speed * SHORT_SLOWER) if short else speed
    british = lang == "en-gb"
    g2p = pronouncers.get(british)
    samples, rate = None, 0
    if g2p is not None:
        try:
            phonemes, _ = g2p(with_names(text, british))
            if phonemes.strip():
                samples, rate = created(kokoro, phonemes, voice=voice, speed=pace, is_phonemes=True)
        except Exception:  # noqa: BLE001, a line misaki cannot read is spoken by espeak instead
            samples = None
    if samples is None:
        samples, rate = created(kokoro, text, voice=voice, speed=pace, lang=lang)
    return polished(samples, rate, short), rate


def serve(port: int) -> None:
    kokoro = Kokoro(str(HERE / "kokoro-v1.0.onnx"), str(HERE / "voices-v1.0.bin"))
    voices = sorted(kokoro.get_voices())
    pronouncers = {british: pronouncer(british) for british in (True, False)}
    g2p = "misaki" if pronouncers[True] is not None else "espeak"
    print(f"pronouncing with {g2p}", flush=True)
    # The model is not documented as safe across threads, so one sentence is spoken at a time.
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format: str, *args: object) -> None:
            return

        def reply(self, status: int, body: bytes, kind: str) -> None:
            self.send_response(status)
            self.send_header("Content-Type", kind)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:
            if self.path != "/health":
                self.reply(404, b"{}", "application/json")
                return
            self.reply(200, json.dumps({"ok": True, "voices": voices, "g2p": g2p}).encode(), "application/json")

        def do_POST(self) -> None:
            if self.path != "/speak":
                self.reply(404, b"{}", "application/json")
                return
            try:
                length = int(self.headers.get("Content-Length", "0"))
                asked = json.loads(self.rfile.read(length) or b"{}")
                text = str(asked.get("text", "")).strip()[:MOST_CHARACTERS]
                voice = str(asked.get("voice", "bm_george"))
                speed = float(asked.get("speed", 0.95))
                if not text or voice not in voices:
                    raise ValueError(f"needs text and one of {len(voices)} voices")
                # British voices start with b, and read best with the British lexicon.
                lang = "en-gb" if voice.startswith("b") else "en-us"
                with lock:
                    samples, rate = spoken(kokoro, pronouncers, text, voice, speed, lang)
                self.reply(200, wav_bytes(samples, rate), "audio/wav")
            except Exception as error:  # noqa: BLE001, the app falls back to the system voice on any failure
                self.reply(400, json.dumps({"error": str(error)}).encode(), "application/json")

    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8723)
    serve(parser.parse_args().port)
