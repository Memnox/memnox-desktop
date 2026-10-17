# memnox-desktop

Every desktop app of Memnox in one repo. The conventions in the workspace `CLAUDE.md` above this
repo (copy with no dashes, one-line commits, the author) apply here and this file only adds to
them. `VISION.md` is a verbatim copy of `memnox-runtime/VISION.md`.

## What every desktop app is allowed to be

**A face, a voice and a signing key over the daemon, and nothing else.** No policy, no model call
and no rule lives in any of them: the daemon decides, the person's own agent CLI thinks, and the
app shows, speaks, listens and signs. A change that needs an app to know what is allowed belongs
in `memnox-runtime`.

**What the person said goes whole to `ask`.** Nothing matches keywords on speech on any platform.

**Every allow that reaches outside the session is signed by a key the operating system guards:**
the Secure Enclave behind Touch ID on macOS, a TPM key behind Windows Hello on Windows, and a
Secret Service key behind a local check on Linux. Each signs the bytes the runtime's
`confirmationMessage` builds, as DER encoded ECDSA P-256, so the daemon verifies all of them alike.

## Layout

| Path | Holds |
|---|---|
| `macos/` | the Mac app, a Swift package; `macos/CLAUDE.md` adds its own rules. |
| `shared/` | the Tauri core shared by Windows and Linux, the protocol vectors from `memnox-runtime`, the design tokens. |
| `windows/` | only what differs on Windows: the island window, the confirm key, the installer and its signing. |
| `linux/` | only what differs on Linux: the island on each compositor, the confirm key, the packages. |

A feature for Windows and Linux is written once in `shared/`; a platform folder holds only what
that operating system does differently.

## Code

- `macos/` builds and tests from inside it: `cd macos && swift test`, which must pass at every commit.
- The wire format is `memnox-runtime/packages/core/src/daemon/protocol.ts`. The Mac mirrors it in
  `macos/Sources/MemnoxVoiceCore/Domain/SharedKernel/DaemonProtocol.swift`; the Tauri core imports
  it from `@memnox/core` rather than copying it. Change the runtime and every mirror together.
