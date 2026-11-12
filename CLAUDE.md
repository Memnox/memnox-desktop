# memnox-desktop

Every desktop app of Memnox in one repo. The conventions in the workspace `CLAUDE.md` above this
repo (copy with no dashes, one-line commits, the author) apply here and this file only adds to
them. `VISION.md` is a verbatim copy of `memnox-runtime/VISION.md`.

## What every desktop app is allowed to be

**A face, a voice and a signing key over the daemon, and over Memnox Cloud when the person signs in,
and nothing else.** The daemon reaches the agents on this computer; the cloud reaches the ones
hosted elsewhere, inside SaaS products or built in no code tools. No policy, no model call
and no rule lives in any of them: the daemon or the cloud decides, the person's own agent thinks, and the
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
  it as `@memnox/core/wire` from `shared/wire`, the runtime's own build kept in this repo and never
  written by hand. Change the runtime and every mirror together.

## This repo builds alone

**A pull request is built from this repo and nothing else.** What the runtime owns is kept here as
copies: `VISION.md`, `shared/vectors`, `shared/ux/contract.json`, the Noise layer in
`shared/tauri-core/crates/desktop-noise`, and the built wire in `shared/wire`. A change that needs a
newer one refreshes that copy in the same pull request, with `pnpm wire` for the wire, so the pull
request passes or fails on what it holds and never on where the runtime's `main` stands.

Whether the copies still match the runtime's `main` is a separate question, answered apart from pull
requests: the Runtime copies workflow runs `scripts/check-runtime-copies.sh` on `main` and every
morning, and a release runs it before it builds. The Mac's Noise framework is the one thing CI still
builds from a runtime checkout, since it is 55 MB of static libraries no repo holds.
