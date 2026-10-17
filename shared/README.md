# shared

What Windows and Linux share, so a feature is written once.

| Path | Will hold |
|---|---|
| `tauri-core/src/core` | TypeScript with no DOM: what to say and when, ported from `macos/Sources/MemnoxVoiceCore/Application/Conversation.swift`, behind ports, with the wire types and `confirmationMessage` imported from `@memnox/core`. |
| `tauri-core/src/ui` | React: the island, the orb in WebGL, the cards, setup and settings. |
| `tauri-core/src-tauri` | Rust: the daemon link over the socket or the named pipe, audio, speech with sherpa-onnx, the tray, autostart and keeping the computer awake while a phone is paired. |
| `vectors/` | JSON fixtures written by `memnox-runtime`, every event and every signed message with its exact bytes, which every desktop's tests read. |
| `tokens/` | the colours, type sizes and spacing every desktop draws with. |

Nothing here is built yet.
