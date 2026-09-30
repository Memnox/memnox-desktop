# Memnox for macOS

The voice of Memnox. An orb you talk to about your agents, and that talks back: what they
are doing, what they changed, whether one can be left running, and what is waiting on you.
It answers with your own agent subscription, never a Memnox key, and nothing you say is
matched against keywords: your words go whole to your own Claude Code, which reads the
machine through Memnox's tools and can only ever propose.

## What is on screen

Nothing but the orb: a sphere of points that breathes when idle, moves with your voice
while it listens, swirls while it reads, moves with its own voice while it speaks, and
holds still while Touch ID is up. Under it, one pill with a waveform and a short caption.

## How it works

```
 ⌥Space, the menu bar, or a held call arriving
        │
   the orb listens (Apple speech recognition, on this Mac)
        │ your words, whole
        ▼
 ~/.memnox/memnox.sock  ── the Memnox daemon (memnox-runtime)
        │ ask                         │ subscribe
        ▼                             ▼
 your own Claude Code,          held calls, proposals, pauses,
 with only memnox-operator      and "settled" when you answered elsewhere
        │
   sentences stream back and are spoken as they arrive
```

- **Asking** sends what you said to the daemon's `ask`, which runs your own Claude Code with
  every built-in tool off and only the `memnox-operator` tools. Answers stream sentence by
  sentence into speech.
- **A held call** is said out loud ("claude-code wants to push to main. Allow it, or
  deny?") and the orb listens for your answer, in any words. A deny takes effect at once.
- **Anything that lets something happen** arrives as a proposal and needs Touch ID: a key in
  the Secure Enclave signs exactly that proposal, and the daemon verifies the signature. An
  agent running as you can raise the sheet, and never finish it.
- **The terminal, `memnox approve` and the workspace DM all keep working.** The voice is one
  more way to answer, and whichever answers first releases the agent.

## Running it

Needs macOS 14 or later, Xcode 16 or later, and the Memnox daemon running
(`memnox daemon`, or installed by `memnox setup`).

```sh
swift test               # the core, headless
./scripts/bundle.sh      # builds build/Memnox.app, signed ad hoc
open build/Memnox.app
```

The first run opens setup, the one ordinary window Memnox has: what to call you (your
first name, from your Mac account, to start with), permission to hear you, whether the
daemon is running, the Touch ID key, and a voice to pick and hear. It reopens from the
menu bar under Set Up Memnox. After that, press ⌥Space, or use the waveform in the menu
bar, and speak.

When an agent is held, Memnox says it the way a colleague would, with the facts the daemon
sent: "Moise, Claude in shop, working on add order cancellation, wants to push main.
Pushing to main needs a person. Allow it, or deny?" Answer in your own words.

## Not built yet

- "Hey Siri, talk to Memnox" (App Intents), which wants the Xcode 26 project.
- "Show me": bringing the agent's own window forward, or one closable card.
- Apple's newer `SpeechAnalyzer`, which needs the macOS 26 SDK; this uses on-device
  `SFSpeechRecognizer` until then.
- A chosen voice: this speaks with the best English system voice installed. Kokoro, run
  locally, is next, and a paid voice only later.
- Talking over it by voice: for now ⌥Space interrupts, which stops the voice and cancels the answer.

If the app says another key is registered, run `memnox voice forget-key` and open it again.
