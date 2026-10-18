<div align="center">

# shared

### One app for Windows and Linux, written once.

[![Tauri 2](https://img.shields.io/badge/Tauri-2-24C8DB?logo=tauri&logoColor=white)](tauri-core/src-tauri)
[![React 18](https://img.shields.io/badge/React-18-61DAFB?logo=react&logoColor=black)](tauri-core/src/ui)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.7-3178C6?logo=typescript&logoColor=white)](tauri-core/src/core)
[![Rust](https://img.shields.io/badge/Rust-stable-000000?logo=rust&logoColor=white)](tauri-core/crates)

<br>

<img src="../docs/images/tauri-island-dictation.png" width="80%" alt="The Memnox island while dictating, with a Dictating chip, a small orb and the words being typed into the app in front.">

</div>

---

Everything Windows and Linux share lives here, so a feature is written once and a platform folder,
[`windows/`](../windows) or [`linux/`](../linux), holds only what its system does differently. The
app is ported from the Mac's: its rules, its states, its copy and its orb shader, line for line where
it can be.

## What is here

| Path | Holds |
|---|---|
| [`tauri-core/src/core`](tauri-core/src/core) | TypeScript with no DOM and no Tauri, ported from `macos/Sources/MemnoxVoiceCore`: every rule, in `domain/` as pure functions and in `application/` as use cases behind ports. Held calls and their signed answers, the voice (`Talking`, where what you said goes whole to `ask`), dictation, rules and drafts that go in force only with a signature, sessions and their focus, Home, setup, pairing phones and servers, the team's inbox, and keeping awake. The wire types and `confirmationMessage` come from `@memnox/core/wire`, never copied. |
| [`tauri-core/src/core/application/ports`](tauri-core/src/core/application/ports) | What the core asks of the world: `DaemonLink`, `ConfirmKey`, `Speaker`, `Ear`, `Typist`, `Terminals`, `Power`, `Runtime`, `Pairer`, `Chimes`, `PreferenceStore` and `WorkspaceInbox`. |
| [`tauri-core/src/ui`](tauri-core/src/ui) | React and Tailwind in Inter and DM Mono, with lucide icons: the island and its orb in WebGL2 (the Mac's Metal shader ported), the cards, sessions, the voice, Settings, the first run, the tray panel, tools and scan, and the Tauri adapters for the ports. |
| [`tauri-core/src-tauri`](tauri-core/src-tauri) | Rust: the daemon link over the socket or the named pipe, the confirm key, the keys and typing on each system, focus through each terminal's and editor's own controls, the island and session windows, the tray and its glass, the relay to paired servers, Memnox Cloud sign in, permissions, presence, and the runtime's setup steps, each a fixed `memnox` line, so the webview names a step and never a command. |
| [`tauri-core/crates/desktop-key`](tauri-core/crates/desktop-key) | The confirm key trait both systems implement, and the raw to DER conversion, tested against the runtime's signature vector. |
| [`tauri-core/crates/desktop-noise`](tauri-core/crates/desktop-noise) | The one Noise layer the runtime, the phones and the Mac share, copied whole from memnox-runtime by `scripts/sync-noise.sh` and tested against its vectors. |
| [`tauri-core/crates/desktop-voice`](tauri-core/crates/desktop-voice) | The voice through sherpa-onnx: Silero finds where you spoke, Parakeet TDT v3 writes it down, and Kokoro v1.0 answers in the Mac's `af_sky` voice, with echo cancelling and chimes. |
| [`tauri-core/test`](tauri-core/test) | The core's tests, run by vitest against a scripted daemon and the protocol vectors. |
| [`tauri-core/src-tauri/icons`](tauri-core/src-tauri/icons) | The Mac's `.icns`, and for Windows and Linux the tile cut out of it: an `.ico` of six sizes and PNGs from 32 to 512. |
| [`vectors/`](vectors) | `protocol.json`, written by memnox-runtime's `pnpm vectors` and copied here by [`scripts/sync-vectors.sh`](scripts/sync-vectors.sh): every signed message with its exact text, one signature in DER and raw form, and every value a mirror must know. The Mac's tests read it too, and CI fails when the copy falls behind the runtime. |

## The voice

The models, about 620 MB, install once on first use: Parakeet in int8 (about 490 MB), Kokoro in int8
(about 130 MB) and Silero. They come from `https://assets.memnox.com/sherpa`, a byte for byte mirror of
sherpa-onnx's releases, and from GitHub when the mirror lacks a file. `MEMNOX_VOICE_PACK` names
another mirror. Until Kokoro is in, the system's own voice speaks.

```sh
cargo run --release -p memnox-desktop-voice --example round_trip -- <models>
```

runs the whole voice with no microphone.

## Build and test

```sh
cd shared/tauri-core
pnpm wire                 # builds memnox-runtime's core and copies its wire into .runtime
pnpm install
pnpm typecheck            # the webview and the core, on their own tsconfigs
pnpm test                 # the core against a scripted daemon and the vectors
cargo test --workspace    # from the repo root: the key, DER, Noise, the daemon link, the voice
pnpm tauri dev            # the app, on Windows or Linux
```

`MEMNOX_RUNTIME` names the runtime checkout when it is not beside this repo, and a development build
started with `MEMNOX_RUNTIME_DIR` runs that checkout's own CLI. CI builds and tests the app on Windows
and Ubuntu.

<details>
<summary><b>Every screen in a browser</b></summary>

`pnpm dev` serves the pages on `http://localhost:1420` over a scripted daemon, with no Tauri:

| Page | Shows |
|---|---|
| `preview.html` | every island scene, listed; `?mode=held`, `?mode=voice-listening`, `?mode=sessions-overview` and the rest |
| `settings.html` | Settings, with `?theme=light` or `dark`, `?page=` for one page, `?platform=linux` |
| `tray.html?preview=panel` | the tray panel, with `&theme=light` or `dark` |
| `preview.html?mode=sessions-live` | the session windows too: `sessions-side`, `sessions-switcher` and `sessions-board` |
| `onboarding.html` | the first run, with `?stage=intro`, `name` or `steps` and `&step=` |
| `previews/tour.html` and `previews/tools.html` | the first run's demo and the tools cards |

The screenshots in [`docs/images`](../docs/images) are shot from these pages with headless Chrome.

</details>
