# memnox-macos

The Mac voice of Memnox: the notch island and its orb, the microphone, the speaker and Touch ID. The
conventions in `../CLAUDE.md` (copy with no dashes, one-line commits, the author) apply here
and this file only adds to them. `VISION.md` is a verbatim copy of `memnox-runtime/VISION.md`.

## What this app is allowed to be

**A face, a voice and a Touch ID button over the daemon, and nothing else.** No policy, no
model call and no rule lives here: the daemon decides, the person's own agent CLI thinks,
and this app shows, speaks, listens and signs. If a change needs this app to know what is
allowed, it belongs in `memnox-runtime`.

**No keyword matching between the voice and the agents.** What the person said goes whole to
`ask`. Recognizer hints (`contextualStrings`) are allowed because they only help the
recognizer hear a word; nothing may act on a word.

**Every allow is signed, and nothing else is.** A deny or a declined proposal is sent unsigned,
since saying no can do no harm. A confirmed proposal carries a Secure Enclave signature over
`memnox-confirm:v1:<id>:<answer>`, which must stay byte for byte what the runtime's
`confirmationMessage` builds.

## Layout

| Path | Holds |
|---|---|
| `Sources/MemnoxVoiceCore/Domain` | rules with no I/O: sessions, notices, speech text, the owner's question, and `SharedKernel/DaemonProtocol.swift`. |
| `Sources/MemnoxVoiceCore/Application` | `Conversation`, which decides what to say and when, and the `Ports` it needs. |
| `Sources/MemnoxVoiceCore/Infrastructure` | adapters behind the ports: the socket link, the confirmation key, files, the diary. No AppKit anywhere in the core, so it is tested headless. |
| `Sources/MemnoxVoice/App` | the composition root that wires every adapter into the core. |
| `Sources/MemnoxVoice/Presentation` | AppKit, SwiftUI and Metal: the notch island, the orb, cards, the menu bar, setup, the design system. |
| `Sources/MemnoxVoice/Platform` | audio in and out, the recognizer, Kokoro, typing into other apps, the hotkey. |
| `Tests/MemnoxVoiceCoreTests` | XCTest laid out like the source tree, against the doubles in `Support/`: a scripted daemon, a recording speaker and face, and a software key. |
| `Support/Info.plist` | the usage descriptions macOS shows before it grants the microphone and speech. |

`docs/ARCHITECTURE.md` holds the dependency rule and where new code goes. `DaemonProtocol.swift` mirrors `memnox-runtime/packages/core/src/daemon/protocol.ts`. Change
one and change the other in the same piece of work.

## Code

- Comments are one line and say why, the same rule as the runtime.
- Force unwraps only where the system guarantees the value, with the reason beside it.
- The app target builds with no warnings in Swift 6 language checks: anything touching AppKit
  is on the main actor, and anything the daemon's thread calls hops there.
- `swift test` must pass at every commit.
