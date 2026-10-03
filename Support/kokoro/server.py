"""Kokoro on this Mac, for Memnox's voice.

A tiny HTTP server on 127.0.0.1 that turns a sentence into a WAV with the Kokoro model, so the
app speaks with a natural voice and nothing it says leaves the machine. The model loads once at
start, which is the only slow part; each sentence after that takes a fraction of a second.
"""

import argparse
import io
import json
import threading
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import numpy as np
from kokoro_onnx import Kokoro

HERE = Path(__file__).resolve().parent
# One sentence is what the app sends, so anything longer is a mistake rather than a reply.
MOST_CHARACTERS = 1_000


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


def serve(port: int) -> None:
    kokoro = Kokoro(str(HERE / "kokoro-v1.0.onnx"), str(HERE / "voices-v1.0.bin"))
    voices = sorted(kokoro.get_voices())
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
            self.reply(200, json.dumps({"ok": True, "voices": voices}).encode(), "application/json")

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
                    samples, rate = kokoro.create(text, voice=voice, speed=speed, lang=lang)
                self.reply(200, wav_bytes(samples, rate), "audio/wav")
            except Exception as error:  # noqa: BLE001, the app falls back to the system voice on any failure
                self.reply(400, json.dumps({"error": str(error)}).encode(), "application/json")

    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8723)
    serve(parser.parse_args().port)
