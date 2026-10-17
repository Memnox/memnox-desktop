# shared

What Windows and Linux share, so a feature is written once.

| Path | Will hold |
|---|---|
| `tauri-core/src/core` | TypeScript with no DOM and no Tauri, ported from `macos/Sources/MemnoxVoiceCore`: the held calls waiting on the person and their signed answers (`HeldCalls`), keeping awake while a phone is paired (`Wakefulness`), behind the ports `DaemonLink`, `ConfirmKey` and `Power`. The wire types, the answer words and `confirmationMessage` come from `@memnox/core/wire`, never copied. |
| `tauri-core/src/ui` | React: the island with the held call, its three answers and the queue, and the Tauri adapters for the ports. The orb in WebGL, setup and settings come next. |
| `tauri-core/src-tauri` | Rust: the daemon link over the socket (refused unless it belongs to the same user) or the named pipe, the confirm key and keep awake commands, and the island window. Audio, speech with sherpa-onnx, the tray and autostart come next. |
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
pnpm tauri dev      # on Windows or Linux; on a Mac it runs with no key and signs nothing
```

`MEMNOX_RUNTIME` names the runtime checkout when it is not beside this repo. CI builds and tests the app on Windows and Ubuntu.
