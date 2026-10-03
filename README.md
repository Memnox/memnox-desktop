# Memnox for macOS

The voice of Memnox. An orb you talk to about your agents, and that talks back: what they
are doing, what they changed, whether one can be left running, and what is waiting on you.
It answers with your own agent subscription, never a Memnox key, and nothing you say is
matched against keywords: your words go whole to your own Claude Code, which reads the
machine through Memnox's tools and can only ever propose.

## What is on screen

An island that grows out of the notch, laid out after Coucou's open source notch companion with
the orb in place of its character. At rest the orb sits just left of the notch, breathing. While
sessions work, the island widens and shows one dot per working session, in its agent's colour.
Rest the pointer on it and it opens: the session in focus with its last steps rolling up as they
happen, and every other session as a pill with its agent's logo. Click the session card to see
the code it is changing, line by line, and click again to bring its own window forward. A click
anywhere else puts the island away, and so does a minute untouched, with a thin line counting
down the last ten seconds.

The orb is one piece throughout: it travels and grows with the island from beside the notch into
whichever card is open. When you talk to Memnox it grows largest of all, about 150 points across in
the middle of the island with a soft blue light behind it, and what was heard or said is written
under it; when the conversation ends it shrinks back beside the notch. It breathes when idle, moves with your voice while it listens, swirls
while it reads, moves with its own voice while it speaks, and holds still while Touch ID is up.

When an agent is held, the island opens on it with who is waiting, the command, and three answers:
Deny, Allow this session and Allow once. Both allows ask for Touch ID first, and a deny needs
none, the same as answering by voice. A session that finishes opens the island on its summary
for a few seconds, and a pause makes it shake. On a Mac without a notch the same island hangs
from the top centre of the screen.

To see every state without any agents running, start it with
`open -n build/Memnox.app --args --island-preview`.

## How it works

```
 ⌥Space, "Memnox", the menu bar, or a held call arriving
        │
   the orb listens (Apple's SpeechAnalyzer on this Mac, the older recognizer before macOS 26)
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

Needs macOS 14 or later (26 or later for SpeechAnalyzer), Xcode 26 or later, and the Memnox daemon running
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

To wake it by name, click the waveform in the menu bar and turn on **Wake when I say "Memnox"** in the glass panel that opens. While the orb is
idle it then listens for its name, on this Mac only, and "Memnox, what's going on?" is
answered straight away. It is off until you turn it on, because it keeps the microphone open
whenever the orb is idle, and a Mac that cannot recognise speech on device never listens for
it at all.

It talks like a colleague who has been watching your sessions:

- **When an agent is held**, your own Claude Code looks at what that session has been doing
  and tells you: "Moise, Claude has been on order cancellation in shop for twenty minutes,
  four files and the tests pass. Now it wants to push to main. Should I let it?" If it
  cannot, the facts alone are said. Answer in your own words.
- **When you come back** after ten minutes or more with the screen locked, it catches you up
  on what finished, what got stuck and what is waiting, then listens. Turn it off in setup.
- **When a session is paused** for going nowhere, it says where it got stuck.
- **An allow only ever follows your own words.** A proposal that arrives when you have not
  spoken is left alone and never put to Touch ID.

## Showing you a session

- **"Open the one fixing checkout"** brings that session's own window forward: the exact tab
  in iTerm or Terminal, found by its terminal device, or the editor window on its folder in
  VS Code and Cursor. macOS asks once before Memnox may drive a terminal.
- **"Give me a summary of it"** puts a glass card in the top left corner with the summary
  while the voice reads it. A click closes it, and it goes on its own after a while.
- **"Which one is working"** counts only sessions where something happened in the last few
  minutes, never a paused one, an ended one or this Mac's own git checks.

Neither changes anything an agent can do, so neither waits on Touch ID.

## Its voice

Pick it under **Voice** in the menu bar panel:

- **Kokoro**, the default: a natural voice run on this Mac by an open model, free, and nothing it
  says leaves the machine. George, a calm British voice, unless you pick another with
  `defaults write com.memnox.voice kokoroVoice bm_lewis` (also `bm_daniel`, `bm_fable`).
  The app installs it itself on first launch, about 340 MB into `~/.memnox/voice/kokoro`, and
  the Mac voice speaks until it is ready; setup shows how far it got, and Try again if it could
  not. It needs nothing installed first: it uses `uv` when the Mac has one and fetches its own
  into that folder when not. `./scripts/kokoro-setup.sh` does the same from a terminal.

  Memnox starts it at launch and stops it when it quits.
- **Mac**: the best English voice installed.

Whichever is chosen, a sentence it cannot voice is said by the Mac's own voice, so it never
goes quiet.

It speaks in the manner of J.A.R.V.I.S.: complete sentences with no contractions or fillers,
the status first, one calm tone whether the news is good or not, and a dry line only now and
then. The words come from the runtime's voice prompt; only the fixed lines, like the greeting
and "Very well. It is done.", live in this app.

## Like an assistant at the next desk

- **It stays quiet until you call it.** Once a conversation ends it says nothing more unless
  something needs you: a held call, an agent asking you something, a paused session, a command
  that failed, or what you asked to be told about. Only a question keeps the microphone open
  after. Turn on **Speak up on its own** in the menu bar panel to also hear when a session
  finishes, commits or pushes.
- **You can talk over it.** Start speaking while it talks and it stops and listens. Its own
  voice coming back through the microphone is told apart by the words it just said, which works
  best with headphones. Turn it off with **Talk over it**.
- **It chimes.** A quiet Mac system sound marks the orb opening and closing, a question sent, an
  agent waiting on you, an allow taken, something left as it was, words typed in, a question
  answered elsewhere and a turn that broke, so you hear what happened before it is said. Turn
  it off with **Sounds**.
- **It answers to its name.** "Memnox" alone gets a "Yes?"; "Memnox, which one is working?"
  gets the answer.
- **It acts on sessions.** "Pause that one" happens at once, because it only holds an agent
  back. "Resume it" waits for Touch ID, because it lets one carry on.
- **It passes on what you want done.** "Tell Claude Code to commit this in separate commits" is
  read back to you, and after your yes it brings the agent's own iTerm or Terminal tab, or its
  VS Code conversation, to the front and types your words into its prompt a key at a time,
  then sends them. Click into another app while it types and it stops and leaves the words on
  the clipboard. Typing needs Memnox allowed under **Privacy & Security > Accessibility**, called
  **Device Control and Data Access** from macOS 27; the Mac asks once. A build signed ad hoc is a
  new app to macOS, so the switch can show on and still refuse: switch it off and on again, or
  run `scripts/signing-setup.sh` once so later builds keep it. The voice only says the agent has started once the Mac reports that the words
  landed.
- **It tells you when.** "Tell me when the tests pass", "let me know if it gets stuck" or "shout
  when Claude is done" sets a one-time watch, and it speaks up when it happens, even with
  **Speak up on its own** turned off, because you asked.
- **It puts things back.** "That broke the UI, put it back" reads back which repository goes back,
  to when, and how many files, then waits for Touch ID. Your files as they were are kept first,
  so "bring it back" undoes the undo.
- **It starts sessions.** "Start Claude in memnox cloud on the failing auth test" is read back,
  and after your yes a new iTerm tab, or Terminal when iTerm is not installed, opens in that
  repository and types `memnox run -- claude '<your task>'` a key at a time, so the session is
  governed from its first step. Only Claude Code and Codex can be started this way.
- **It hands work between agents.** "Have Codex review what Claude just changed" sends Codex your
  words plus the files Claude changed.
- **It shows you every agent.** "Scan my computer" or "show me all my agents" fills the screen:
  Memnox in the middle, a sweep that finds each agent in turn, and every one set in a ring with
  its own logo, its MCP servers, what else it reaches and its sessions right now. Click or press
  Escape to close it.
- **It runs any memnox command.** "What's the status", "show me the timeline for the last
  hour" or "run the doctor" runs at once and it tells you what came back. "Switch to autonomous
  mode", "freeze everything" or "lock the billing folder" changes something, so it reads it back
  and waits for Touch ID first. A few never run by voice and it says why: answering a held call
  has its own Touch ID question, signing in needs a browser, and uninstalling would remove the
  voice itself.
- **It shows you why it was slow.** "Why did that take so long?" or "trace that session" puts a
  waterfall on screen, the way Logfire draws one: hearing you finish, reading the sessions, the
  brain thinking and each tool it called, then speaking, or every turn and action of an agent's
  session with its decision and time. `memnox traces --otlp` sends one to Logfire itself.
- **It walks you through a change.** "Walk me through it" puts a card in the corner that turns a
  page per file, with that file's changed lines, while the voice says what each change does.
  Back and Next take the pages over.

## Not built yet

- "Hey Siri, talk to Memnox" (App Intents), which wants the Xcode 26 project.

Run `scripts/signing-setup.sh` once before your first build. It makes a local signing identity in
your keychain, so every build is the same app to macOS and Accessibility is asked for only once;
signed ad hoc, each build is a new app and the permission sheet comes back after every rebuild.

If the app says another key is registered, run `memnox voice forget-key` and open it again.
