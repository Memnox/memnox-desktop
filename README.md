<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Support/Logo/memnox-mark-white.png">
  <img src="Support/Logo/memnox-mark-template.png" alt="Memnox" width="88">
</picture>

# Memnox for macOS

### Talk to your coding agents. Approve with your fingerprint.

An orb that lives in your notch, knows what every agent on your Mac is doing,<br>
tells you out loud, and lets you answer them by voice, with Touch ID guarding every yes.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![No dependencies](https://img.shields.io/badge/dependencies-Apple%20only-1E86EE)
![License MIT](https://img.shields.io/badge/license-MIT-37CD8F)
![PRs welcome](https://img.shields.io/badge/PRs-welcome-DD815D)

[Quick start](#quick-start) · [What it does](#what-it-does) · [How it works](#how-it-works) · [Architecture](docs/ARCHITECTURE.md) · [Contributing](#contributing)

</div>

---

> **"Moise, Claude has been on order cancellation in shop for twenty minutes, four files and
> the tests pass. Now it wants to push to main. Should I let it?"**
>
> You say *yes*. Touch ID asks for your finger. The push goes through. You never left your editor.

Your agents already do the work. The hard part is knowing what they are up to and feeling safe
letting them carry on. Memnox for macOS is the face and voice of [Memnox](VISION.md), the control
plane for autonomous work: it watches Claude Code, Codex, Cursor and the rest through the Memnox
daemon, speaks up only when something needs you, and turns your spoken answer into a signed
decision.

## Why people like it

| | |
|---|---|
| 🎙️ **Just talk** | Your words go whole to your own Claude Code. No keyword matching, no command syntax, no Memnox API key. |
| 🔐 **Touch ID on every yes** | Anything that lets an agent act is signed by a key that never leaves the Secure Enclave. An agent running as you can raise the sheet, and never finish it. |
| 🏝️ **Lives in the notch** | An island grows out of the notch with one dot per working session, their latest steps rolling up, and the code they are changing line by line. |
| 🤫 **Quiet by default** | It says nothing until something needs you: a held call, a question, a paused session, a failure, or what you asked to hear about. |
| 🗣️ **A voice worth hearing** | Kokoro, an open model, runs on your Mac for free. Nothing it says leaves the machine. |
| 🧱 **Built to be read** | Pure Swift on Apple frameworks only, a headless core in DDD layers, and a test suite that runs in about a second. |

## What it does

Things you can say, and what happens:

| You say | It does |
|---|---|
| *"Which one is working?"* | Counts sessions with activity in the last few minutes, never a paused or ended one. |
| *"Open the one fixing checkout."* | Brings forward that session's exact iTerm or Terminal tab, or its editor window. |
| *"Give me a summary of it."* | Puts a glass card in the corner and reads it to you. |
| *"Walk me through it."* | Turns a page per changed file while the voice explains each change. |
| *"Tell Claude Code to commit this in separate commits."* | Reads it back, and after your yes types it into the agent's own prompt. |
| *"Start Claude in memnox cloud on the failing auth test."* | Opens a new tab in that repository and starts a governed session with `memnox run`. |
| *"Have Codex review what Claude just changed."* | Hands Codex your words plus the files Claude changed. |
| *"Tell me when the tests pass."* | Sets a one time watch, and speaks up when it happens. |
| *"That broke the UI, put it back."* | Reads back what goes back, to when, then waits for Touch ID. "Bring it back" undoes the undo. |
| *"Scan my computer."* | Fills the screen with every agent it finds, its MCP servers and its sessions, in a ring. |
| *"Why did that take so long?"* | Draws a waterfall of the turn: hearing you, thinking, each tool, speaking. |
| *"Pause that one."* | Happens at once, because holding an agent back is always safe. *"Resume it"* waits for Touch ID. |

<details>
<summary><b>Everything else it does, in detail</b></summary>

- **Held calls.** When an agent is held, the island opens on it with who is waiting, the command,
  and three answers: Deny, Allow this session and Allow once. Both allows ask for Touch ID, a deny
  needs none, and you can answer the same way by voice in any words.
- **Coming back.** After ten minutes or more with the screen locked, it catches you up on what
  finished, what got stuck and what is waiting, then listens. Turn it off in setup.
- **Talking over it.** Start speaking while it talks and it stops and listens. It tells its own
  echo apart by the words it just said, which works best with headphones.
- **Chimes.** A quiet system sound marks the orb opening and closing, a question sent, an agent
  waiting, an allow taken and a turn that broke, so you hear what happened before it is said.
- **Its name.** Turn on **Wake when I say "Memnox"** and "Memnox, what's going on?" is answered
  straight away. Recognition stays on this Mac, and it is off until you turn it on.
- **Any memnox command.** "Run the doctor" runs at once. "Freeze everything" changes something, so
  it reads it back and waits for Touch ID. A few never run by voice, and it says why.
- **Speak up on its own.** Turn it on in the menu bar panel to also hear when a session finishes,
  commits or pushes.
- **Everywhere else still works.** The terminal, `memnox approve` and the workspace DM keep
  working. Whichever answers first releases the agent.

On a Mac without a notch, the island hangs from the top centre of the screen. To see every state
without any agents running, start it with `open -n build/Memnox.app --args --island-preview`.

</details>

## Quick start

You need macOS 14 or later (26 or later for SpeechAnalyzer) and Xcode 26 or later. The app brings
the Memnox runtime itself: on every launch it finds `memnox` or installs it, wires the machine with
`memnox setup --yes` the first time, starts the daemon, and brings a daemon older than the app up
to date. Setup only names a command when one of those steps fails.

Where it gets `memnox` is chosen when it is built, and written into its Info.plist:

- **Local**, the default. `bundle.sh` builds the `memnox-runtime` checkout beside this one (or
  `MEMNOX_RUNTIME_DIR`) with pnpm first, and restarts the daemon on that build when `memnox` on
  your PATH is that checkout. The app runs the checkout: it links it with `npm link` when `memnox`
  is some other copy, and never replaces it with the published package.
- **npm**, for a release: `MEMNOX_RUNTIME_SOURCE=npm ./scripts/bundle.sh`. The app uses a
  `memnox` already installed, installs `memnox@latest` from npm when there is none, and runs
  `memnox update --yes` when the daemon is older than the app.

```sh
scripts/signing-setup.sh   # once: a local signing identity, so macOS remembers your permissions
scripts/vendor-noise.sh    # once: the Noise framework from the runtime checkout, which git never holds
swift test                 # the core, headless, in about a second
./scripts/bundle.sh        # builds ../memnox-runtime, then build/Memnox.app against it
open build/Memnox.app
```

The first run opens setup: what to call you, permission to hear you, whether the daemon is
running, your Touch ID key, and a voice to try. After that, press **⌥Space** or click the waveform
in the menu bar, and speak.

## How it works

```mermaid
sequenceDiagram
    actor You
    participant Orb as Memnox for macOS
    participant Daemon as Memnox daemon
    participant Agent as Your Claude Code
    You->>Orb: "Which one is working?"
    Orb->>Daemon: ask, with your words whole
    Daemon->>Agent: runs with only the memnox operator tools
    Agent-->>Daemon: the answer, streamed
    Daemon-->>Orb: one JSON line per chunk, over a local socket
    Orb-->>You: spoken sentence by sentence as it arrives
    Note over Daemon,Orb: Held calls, proposals and pauses arrive the same way, pushed
    You->>Orb: "Yes, let it."
    Orb->>Orb: Touch ID, then the Secure Enclave signs that one proposal
    Orb->>Daemon: the signed answer, which the daemon verifies
```

The app is a face, a voice and a Touch ID button. The daemon decides what is allowed and your own
agent does the thinking, so no policy, rule or model call lives here. Speech is recognised by
Apple's SpeechAnalyzer on this Mac (the older recognizer before macOS 26), and answers stream into
speech sentence by sentence so the voice starts before the answer is finished.

### Its voice

Pick it under **Voice** in the menu bar panel. **Kokoro** is the default: a natural voice from an
open model, run on this Mac, free. George, a calm British voice, unless you choose another with
`defaults write com.memnox.voice kokoroVoice bm_lewis` (also `bm_daniel`, `bm_fable`). The app
installs it on first launch, about 340 MB into `~/.memnox/voice/kokoro`, and the Mac's own voice
speaks until it is ready. **Mac** uses the best English voice installed. A sentence one voice
cannot say is said by the other, so it never goes quiet.

It speaks in the manner of J.A.R.V.I.S.: complete sentences, the status first, one calm tone
whether the news is good or not, and a dry line only now and then.

## Built to be read

```mermaid
flowchart TB
    subgraph app["MemnoxVoice · the Mac app"]
        AppRoot["App<br/>composition root"]
        Pres["Presentation<br/>island, cards, menu bar"]
        Plat["Platform<br/>mic, speaker, Kokoro, typing"]
    end
    subgraph core["MemnoxVoiceCore · headless, no AppKit"]
        Appl["Application<br/>Conversation and its Ports"]
        Dom["Domain<br/>pure rules, no I/O"]
        Infra["Infrastructure<br/>socket, Secure Enclave, files"]
    end
    AppRoot --> Pres & Plat & Appl & Infra
    Appl --> Dom
    Infra -. implements ports of .-> Appl
```

- **A core you can test without a Mac app.** Every decision about what to say and when lives in
  `MemnoxVoiceCore`, which imports no AppKit. Tests fake the daemon, the speaker, the face and the
  key, so they run with no socket, no audio and no Secure Enclave.
- **Tests that mirror the code.** `Tests/MemnoxVoiceCoreTests/Domain/Speech/EchoTests.swift` tests
  `Sources/MemnoxVoiceCore/Domain/Speech/Echo.swift`. Find one and you have found the other.
- **No magic values.** Design tokens live in one place, every number is named for its role, and
  values the daemon defines are enums, so a typo is a compile error.
- **No dependencies.** Apple frameworks only, by rule.

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) has the dependency rule, the ports and their
adapters, and a table of where new code goes.

## Private and secure by design

- What you say goes to **your own** agent subscription through the local daemon, never to a
  Memnox server.
- Every allow is signed by a P-256 key **made in the Secure Enclave**, usable only after Touch ID
  for each signature. A deny is never signed, because saying no can do no harm.
- The app only talks to a daemon running **as you**, and text from the daemon can never run as
  AppleScript. Both are enforced in code and the escaping is covered by tests.
- The speech server listens on **127.0.0.1 only**.

Read [SECURITY.md](SECURITY.md) for the full model, its known limits, and how to report an issue
privately.

## Contributing

**Pull requests are welcome**, and the codebase is set up to make your first one easy: small files
named for what they do, a test beside every rule, and a suite that runs in about a second.

Good places to start:

| Idea | Where it lives | Size |
|---|---|---|
| "Hey Siri, talk to Memnox" through App Intents | a new `Platform` adapter | Medium |
| A launch token so only the app can use the speech server | `Platform/Kokoro.swift`, `Support/kokoro/server.py` | Small |
| Pin SHA-256 checksums for the voice model download | `scripts/kokoro-setup.sh` | Small |
| Localize the interface (the copy is already `Text` keys) | `Presentation/` | Medium |
| Notarized release builds | `scripts/bundle.sh` | Medium |
| More recognizer spellings of "Memnox" from your own Mac | `Domain/Speech/WakeWord.swift`, with a test | Small |

Read [CONTRIBUTING.md](CONTRIBUTING.md) for how a change gets in and the rules a review checks.
Every pull request is built and tested on a Mac by CI, and the issue and pull request forms walk
you through the rest. If you are unsure where something belongs, open an issue and ask; that is
a good first contribution too. Everyone taking part follows the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Troubleshooting

- **Accessibility keeps asking again.** A build signed ad hoc is a new app to macOS each time.
  Run `scripts/signing-setup.sh` once so later builds keep the grant. From macOS 27 the setting is
  called **Device Control and Data Access**; if the switch shows on and typing still fails, turn it
  off and on again.
- **"Another key is registered."** Run `memnox voice forget-key` and open the app again.
- **It cannot reach Memnox.** Start the daemon with `memnox daemon`.

## License

[MIT](LICENSE).
