# shared

What Windows and Linux share, so a feature is written once.

| Path | Will hold |
|---|---|
| `tauri-core/src/core` | TypeScript with no DOM and no Tauri, ported from `macos/Sources/MemnoxVoiceCore`: the held calls waiting on the person and their signed answers (`HeldCalls`), the voice (`Talking`: what they said goes whole to `ask`, held calls are briefed aloud, and a proposal is confirmed only within two minutes of their own words and only with a signature, otherwise declined), the cards a rule or a draft waits on (`ProposalCards`: a rule goes in force only with a signature over the place picked, a Send only with one over exactly the words sent), one place every yes is signed (`Signer`), keeping awake while a phone is paired (`Wakefulness`), setting the runtime up with no terminal (`Setup`: finds `memnox` or installs it from npm, wires the computer the first time, starts the service, updates one too old, as the Mac's `RuntimeInstaller` does), and the agent the voice thinks with (`VoiceSettings`), behind the ports `DaemonLink`, `ConfirmKey`, `Speaker`, `Power` and `Runtime`. The wire types, the answer words and `confirmationMessage` come from `@memnox/core/wire`, never copied. |
| `tauri-core/src/ui` | React and Tailwind, in memnox-client's dark palette with lucide icons: the island with the orb in WebGL2 (the Mac's Metal shader ported line for line, its motion in the core's `OrbMotion`), the held call, its three answers and the queue, the rule and draft cards, the setup row, settings (the Kokoro voice, the agent it thinks with, putting agents under Memnox), the Talk button and the voice install, and the Tauri adapters for the ports. `pnpm dev` and `/preview.html` (or `/preview.html?settings`) draw it from a scripted daemon with no Tauri. |
| `tauri-core/src-tauri/icons` | The Mac's own `.icns` for macOS, and for Windows and Linux the tile cut out of it without the Dock's margin and shadow: an `.ico` of six sizes and PNGs from 32 to 512. |
| `tauri-core/src-tauri` | Rust: the daemon link over the socket (refused unless it belongs to the same user) or the named pipe, the confirm key, keep awake and voice commands, the island window, the tray, starting at sign in (on from the first run, off from the tray), the talk key, Ctrl Alt Space, and the runtime's three setup steps, each one fixed `memnox` line run through the person's login shell, so the webview names a step and never a command. |
| `tauri-core/crates/desktop-voice` | The voice on this computer through sherpa-onnx: Silero finds where the person spoke, Parakeet TDT v3 writes it down, Kokoro v1.0 says the reply in the Mac's `af_sky` voice. The models, about 620 MB, are fetched on first use from sherpa-onnx's releases, or from `MEMNOX_VOICE_PACK` when a mirror is set. `cargo run --release -p memnox-desktop-voice --example round_trip -- <models>` runs the whole voice without a microphone. |
| `tauri-core/crates/desktop-key` | The confirm key trait both platforms implement, and the raw to DER conversion, tested against the runtime's signature vector. |
| `vectors/` | `protocol.json`, written by `memnox-runtime`'s `pnpm vectors` and copied here by `scripts/sync-vectors.sh`: every signed message with its exact text, one signature in DER and raw form, and every value a mirror must know. The Mac's `ProtocolVectorsTests` reads it, and CI fails when the copy falls behind the runtime. |
| `tokens/` | the colours, type sizes and spacing every desktop draws with. |

`tokens/` is still planned.

## Build the Windows and Linux app

```sh
cd shared/tauri-core
pnpm wire           # builds memnox-runtime's core and copies its wire into .runtime
pnpm install
pnpm test           # the core against a scripted daemon and the vectors
cargo test --workspace   # from the repo root: the key, the DER conversion, the daemon link
pnpm tauri dev      # on Windows or Linux; on a Mac it runs with no key and signs nothing, though it talks
```

`MEMNOX_RUNTIME` names the runtime checkout when it is not beside this repo. CI builds and tests the app on Windows and Ubuntu.
