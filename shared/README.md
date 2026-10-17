# shared

What Windows and Linux share, so a feature is written once.

| Path | Will hold |
|---|---|
| `tauri-core/src/core` | TypeScript with no DOM: what to say and when, ported from `macos/Sources/MemnoxVoiceCore/Application/Conversation.swift`, behind ports, with the wire types and `confirmationMessage` imported from `@memnox/core`. |
| `tauri-core/src/ui` | React: the island, the orb in WebGL, the cards, setup and settings. |
| `tauri-core/src-tauri` | Rust: the daemon link over the socket or the named pipe, audio, speech with sherpa-onnx, the tray, autostart and keeping the computer awake while a phone is paired. |
| `vectors/` | `protocol.json`, written by `memnox-runtime`'s `pnpm vectors` and copied here by `scripts/sync-vectors.sh`: every signed message with its exact text, one signature in DER and raw form, and every value a mirror must know. The Mac's `ProtocolVectorsTests` reads it, and CI fails when the copy falls behind the runtime. |
| `tokens/` | the colours, type sizes and spacing every desktop draws with. |

Only `vectors/` exists so far; the rest is planned.
