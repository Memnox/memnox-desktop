# Contributing

Thank you for helping. This page is what you need to change the code and have the change
accepted. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) first: it says which layer your change
belongs in. Everyone taking part follows the [Code of Conduct](../CODE_OF_CONDUCT.md).

## How a change gets in

1. **Start from an issue.** Open a bug report or an idea from the forms, or comment on an existing
   one to say you are taking it. For anything bigger than a small fix, agree the approach in the
   issue first, so no one's work is wasted.
2. **Open a pull request.** The template asks how you checked it and walks you through the
   rules below. A draft pull request is a fine way to ask for early feedback.
3. **CI runs on every pull request.** It builds the Noise framework from `memnox-runtime`, builds
   the core, the app and the tests on a macOS 26 runner, runs `swift test`, builds the app bundle,
   and checks the copy rules. It has to be green
   before a review.
4. **A maintainer reviews it.** Expect questions about which layer a change belongs in and how it
   is tested; that is the review working, not a judgement of you.

## Set up

You need macOS 14 or later, Xcode 26 or later, and a checkout of
[memnox-runtime](https://github.com/Memnox/memnox-runtime) beside this one, with its daemon running
(`memnox daemon`). The app uses no Swift package, and none may be added: everything is Apple's own
frameworks, plus the one Noise build the runtime makes, which `scripts/vendor-noise.sh` copies in
(or builds with `rustup` and `cargo` when there is no build to copy).

```sh
scripts/signing-setup.sh   # once: a local signing identity, so macOS keeps its permissions across builds
scripts/vendor-noise.sh    # once: the Noise framework Package.swift needs, which git never holds
swift test                 # the core, headless; must pass before every commit
./scripts/bundle.sh        # builds and signs build/Memnox.app
```

## The rules a review checks

### Layers

- A rule about what to say or when is pure Domain code with a test, never a branch in a view.
- The core imports no AppKit, SwiftUI, Metal, AVFoundation or Speech. What it needs from the Mac
  is a protocol in `Application/Ports` with an adapter in Infrastructure or the app's Platform.
- Core code takes the clock, the OS version and anything read from disk through `init`, so tests
  decide them. Never call `Date()` in the core outside `Diary.swift`.
- A field or method the daemon speaks changes `DaemonProtocol.swift` and the runtime's
  `protocol.ts` in the same piece of work.

### No magic values

- A number in code is a named constant, unless it is 0, 1, or a 2 that halves or doubles.
- Design values come from `Presentation/DesignSystem.swift` when the role matches: `Memnox.TextSize`,
  `Spacing`, `Stroke`, `Ink`, `Motion`, `radius`. Anything specific to one view is a `private static let`
  on that view, named for its role (`rowSpacing`, never `spacing7`).
- Identifiers are named constants or enums: defaults keys, SF Symbol names, bundle identifiers,
  protocol values, file names. A value the daemon defines uses the core enum for it.
- Text a person reads or hears stays inline, because SwiftUI treats it as a localization key.

### Swift

- A `switch` over this app's own enums lists every case and has no `default`, so a new case is a
  compile error everywhere it has to be decided.
- No `Any` values, no `as!`, no `try!`, no `fatalError`. Where an Apple API is untyped, convert it
  in one private function. A force unwrap needs a comment saying why the system guarantees it.
- `final class` for stateful objects, `struct` and `String` enums for data, `private` by default.
- Anything touching AppKit is `@MainActor`. The core uses async/await, never Dispatch or Combine.
- Log with `diary.note(...)`, never `print`.

### Comments and copy

- A comment says why, in one or two lines. A comment that repeats the code is deleted.
- No dash ever stands in text: not an em dash, an en dash or a spaced hyphen. Write the word it
  stood for (because, so, which) or two sentences. A hyphen inside a word or a flag is fine.

### Tests

- XCTest in `Tests/MemnoxVoiceCoreTests`, laid out like the source: the tests for
  `Sources/MemnoxVoiceCore/Domain/Speech/Echo.swift` are in `Domain/Speech/EchoTests.swift`.
- One test class per source file, and one test per behaviour, named for it:
  `testSaysNothingExtraWhenTheAnswerIsQuick`.
- Fake only the ports (daemon, speaker, face, key, owner, presenter, chimes), with the doubles in
  `Support/TestDoubles.swift` and JSON helpers in `Support/Fixtures.swift`. No socket, no audio.

## Commits

A commit message is one line in the repository's conventional form (`feat:`, `fix:`, `refactor:`,
`docs:`, `chore:`), saying what the commit does, under 80 characters, with no body. Keep a pull
request to one change.

## Reporting a security issue

Please do not open a public issue. See [SECURITY.md](../SECURITY.md).
