# Architecture

Memnox for macOS is a face, a voice and a Touch ID button over the Memnox daemon. The daemon
decides what is allowed and the person's own agent CLI does the thinking; this app shows, speaks,
listens and signs. That boundary shapes everything below: no policy, no rule and no model call
lives here, and anything that needs one belongs in `memnox-runtime`.

## Two targets, five layers

The package has two targets. `MemnoxVoiceCore` holds every decision about what to say and when,
imports no AppKit, and is tested headless. `MemnoxVoice` is the Mac app around it.

```
MemnoxVoice (the app)
  App/            composition root: builds every adapter and hands it to the core
  Presentation/   the notch island, cards, live window, switcher, menu bar, setup, design system
  Platform/       microphone, recognizer, speaker, Kokoro, typing into other apps, hotkey, sounds
        |
        v  uses
MemnoxVoiceCore (the core)
  Application/    Conversation, the use cases, and the Ports it needs from the outside world
  Domain/         rules and words with no I/O: sessions, notices, speech, the owner's question
  Infrastructure/ adapters behind the ports: the daemon socket, the Secure Enclave key, files
```

### The dependency rule

Each layer may only depend on the layers named under it here:

| Layer | May use |
|---|---|
| Domain | Foundation, and the shared kernel inside Domain |
| Application | Domain, and its own Ports |
| Infrastructure | Domain, and the Ports it implements |
| Platform and Presentation | the core's public API, Apple frameworks |
| App | everything: it is where adapters are chosen and wired |

Two things cross every layer by design. The `diary` notes what happened so Copy What Happened can
hand it over, and it logs through `os.Logger`. The shared kernel is the vocabulary every layer
speaks.

### The shared kernel

`Domain/SharedKernel/DaemonProtocol.swift` mirrors `memnox-runtime/packages/core/src/daemon/protocol.ts`
field for field. It is a shared kernel in the DDD sense: one model owned jointly by two bounded
contexts, changed in both repositories in the same piece of work. Values the runtime names as
constants (`NOTICE_KIND`, `SESSION_STATE`, `EVENT_SURFACE`) are Swift enums here
(`NoticeKind`, `SessionState`, `StepSurface`). The wire keeps the raw string and each type offers
a typed view, so a value a newer daemon adds reads as nil instead of failing the whole event.

`confirmationMessage(subject:answer:)` also lives there. It builds the exact string a Touch ID
signature covers, so it must stay byte for byte what the runtime verifies.

## Ports and adapters

The application layer declares what it needs as protocols in `Application/Ports`. Tests fake
every one of them, and the app wires the real ones in `App/AppDelegate.swift`.

| Port | Real adapter | Test fake |
|---|---|---|
| `DaemonLink` | `TargetLink` (Application) over `UnixSocketLink` (Infrastructure/Daemon) for this Mac, and a `NoiseRelayLink` (Infrastructure/Relay) per paired server | `ScriptedLink`, `StepLink`, `SlowLink` |
| `PairedStore` | `KeychainPairedServers` (Infrastructure/Persistence) | `MemoryPairedServers` |
| `Pairer` | `RelayPairer` (Infrastructure/Relay), introducing this Mac as a desktop | a scripted pairer in `ServerPairingTests` |
| `WorkspaceInbox` | `HttpWorkspaceInbox` (Infrastructure/Cloud) over an `HttpTransport`, `URLSessionTransport` in the app | `ScriptedTransport` |
| `PersonCredentialStore` | `KeychainPersonCredential` (Infrastructure/Persistence), its own Keychain service apart from the servers | `MemoryPersonCredential` |
| `ConfirmKey` | `SecureEnclaveConfirmKey` (Infrastructure/Security), or `RefusingKey` when none can be made | `PersonKey`, `SoftwareConfirmKey` |
| `OwnerStore` | `DefaultsOwner` (Infrastructure/Persistence) | `MemoryOwner` |
| `Speaker` | `Voice`, Kokoro or the system voice (Platform/Audio) | `RecordingSpeaker` |
| `Face` | `IslandPanel` (Presentation/Island) | `RecordingFace` |
| `Presenter` | `SessionPresenter` (Presentation/Cards) | `RecordingPresenter` |
| `Chimes` | `SystemChimes` (Platform/Sounds) | `RecordingChimes` |

The relay client (`Infrastructure/Relay`, `Infrastructure/Noise`, `Domain/Relay` and the pairing
records in `Domain/Pairing`) is copied from memnox-ios by `scripts/sync-relay.sh`, which names the
two small edits the copies carry. The app subscribes to this Mac's daemon and to every paired server at once, and
`MachineEvents` decides what each brings: all of it from the machine picked, and from the rest what
waits on the person. `TargetLink` remembers which machine raised each subject, so an answer goes back
through the link its call came from while the voice keeps talking to the machine picked. It sends a
server only what `RemoteReach` allows, so a key, learnt words and pairing stay with this Mac's own daemon, and `TargetPresenter` shows a
server's sessions without ever typing into, opening or focusing them. Every request takes its id
from the one `RequestIds`, since a relay session refuses an id already in flight.

The person can also sign in to their Memnox Cloud workspace (`WorkspaceSignIn`, a device code approved
in the console), which registers this Mac's confirmation key with the workspace. `WorkspaceAnswering`
then reads the held calls the workspace routed to them, which the app polls while it runs and again on
wake, and shows them on the island as "codex on build-box, from Ana's team". Their subjects are remembered in `TargetLink`
as the workspace's, which refuses to carry them to any daemon, and `Conversation.answerHeld` answers them
through the inbox: a yes signed with Touch ID over `memnox-confirm:v1:<id>:<answer>`, a deny unsigned.
`Conversation.announceTeam` says each one aloud like a call on this Mac and the microphone opens after it.
Every ask names the open calls to the daemon the voice talks to as `teamCalls`, an empty list included, so a
spoken answer comes back as a proposal carrying `teamAnswer`. The Mac carries that out with the workspace
first, then confirms the proposal to the daemon that raised it: a yes is one Touch ID over both
`memnox-confirm:v1:<callId>:<answer>` and `memnox-confirm:v1:<proposal>:confirmed`, a deny goes unsigned
both ways, and a cancelled touch declines the proposal and sends the workspace nothing. The contract is the
runtime's `docs/remote-contract.md`, "Answering a team's question by voice".
The inbox is read with `include=recent`, so a call settled by somebody else leaves its card saying who and
where. Somebody who only answers for their team can do it from the first run's "Join your team", with nothing
else on this Mac set up. The contract is `memnox-cloud/docs/person-inbox.md`.

Every held call, from this Mac, a server or the workspace, is named by `CallLabel` (`Domain/Held`) in one
shape on the card, the Touch ID sheet, the caption and the voice: "Claude Code on your Mac", "codex on
build-box", and ", from Ana's team" after a workspace call. `WaitingCalls` queues them, so a second call joins
the first rather than replacing it, and gives the island its "3 waiting: 2 on build-box, 1 on your Mac"
header; `SettledLine` words the moment a card says who answered it elsewhere, from only what was reported.

Anything else from the outside world arrives as a closure in `Conversation.init`, with a default
that is safe in tests: the clock (`now`), the macOS version (`macOSMajorVersion`) and the person's
chosen address (`address`).

## How a turn flows

1. The hotkey, the menu bar or the wake word opens the island, and the recognizer (Platform)
   hears the person. With Live words on, each word goes to the island the moment the
   recognizer has it, so the person sees what is heard while they are still saying it.
2. `Conversation` (Application) sends the words whole to the daemon's `ask`. Nothing in the app
   acts on a word, which is why `Conversation.swift` may not lowercase or search text.
3. The daemon streams the answer back as chunks over the Unix socket, one JSON line each.
4. `SentenceSplitter` (Domain) cuts the stream into sentences, `pronounced` and `speakable` make
   them sayable, and the `Speaker` says each one as it arrives. The same chunks reach the `Face`
   as written, markdown and all, through `asked`, `replying` and `replied`; the island lays them
   out in an answer card and keeps the exchange in `History` (Domain), saved by `HistoryFile`.
   A brief or a held call never reaches the card, only an answer to something the person asked.
   The side panel (`Presentation/Side`), opened from the left of the notch, lists that history by
   day beside what needs the person and what is working, and keeps a failed question with its
   reason so it can be asked again whole.
5. A `draft` show event puts a message from the person's connected mail on the island, read
   whole. Nothing on the Mac edits it, so Send signs exactly what the runtime drafted.
   Holding Control and Option (`HoldKeys`, Platform) takes down a rule: the recognizer listens for
   exactly as long as the keys are down, and the words go whole to `ask` with the `rule` intent,
   which the keys chose and no word did. The runtime proposes the rule with the places it could
   hold, and the island's rule card lets the person pick one; that place's id is the answer Touch
   ID signs, so the reach of a rule is never chosen by anyone but them.
6. Events the daemon pushes (a held call, a notice, a card to show) go through the domain rules
   in `Announcing.swift` to decide whether they are said and whether the microphone stays open.
7. An allow is signed by the Secure Enclave key after Touch ID; a deny or a decline goes unsigned,
   since saying no can do no harm.

## Where to put new code

| You are adding | Put it in |
|---|---|
| A rule about what to say, or when | `Domain/`, as a pure function or type, with a test |
| A field or method the daemon speaks | `Domain/SharedKernel/DaemonProtocol.swift` and `protocol.ts`, together |
| A new step in a conversation | `Application/Conversation.swift` |
| Something the core needs from the Mac | a protocol in `Application/Ports`, an adapter in Infrastructure or Platform |
| A screen or a view | `Presentation/`, using the tokens in `DesignSystem.swift` |
| Microphone, speaker, keyboard or another app | `Platform/` |
| Wiring | `App/AppDelegate.swift` |
