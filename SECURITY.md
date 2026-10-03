# Security

Memnox for macOS can speak, type into other apps and sign approvals with Touch ID, so its
security model is worth stating plainly.

## Reporting a vulnerability

Please report privately through GitHub's **Report a vulnerability** button on this repository's
Security tab, not in a public issue. Include what you did, what happened, and the macOS and app
versions. We will acknowledge the report and keep you informed while it is fixed.

## What the app trusts, and why

| Boundary | What protects it |
|---|---|
| The daemon socket, `~/.memnox/memnox.sock` | The app connects only to a peer running as the same user (`getpeereid`), so another account cannot pose as the daemon. |
| An approval | Signed by a P-256 key created inside the Secure Enclave, usable only while the Mac is unlocked and only after Touch ID or the password, for each signature. The key never leaves the chip. Only an allow is signed; a deny or a decline is sent unsigned, because saying no can do no harm. |
| The signed message | Built in one place, `confirmationMessage(subject:answer:)`, byte for byte what the runtime verifies, so a signature cannot be replayed onto another request. |
| Text placed into AppleScript | Escaped by `AppleScriptText.quoted`, and terminal names admitted only when they match a real device, through `AppleScriptText.device`. Both are covered by injection tests. |
| Typing into another app | Only into the agent's own tab, checked to be the frontmost tab before a key is pressed, and stopped if the person clicks elsewhere. It needs the person's Accessibility grant. |
| What the person said | Sent whole to their own agent through the daemon. The app never acts on a keyword, so nothing said can trigger an action directly. |
| The speech server (Kokoro) | Listens on `127.0.0.1` only, so nothing off the Mac can reach it. |

The app holds no secrets and makes no network calls of its own beyond the loopback speech server.
The confirmation key lives in the Secure Enclave and the login keychain, never in code or on disk.

## Known limitations

- Any process of the same user can talk to the daemon socket, as it can to every file the user
  owns. The daemon, not this app, decides what is allowed.
- Any local process, or a web page posting to localhost, can ask the speech server to synthesize
  text. The audio goes back to the caller and is not played, so the cost is CPU time. A per launch
  token on the server would close this.
- `scripts/kokoro-setup.sh` downloads the speech model and the `uv` installer over HTTPS without
  pinning their checksums. Pinning SHA-256 hashes would close this.
- A local build is signed with a local identity or ad hoc and is not notarized. Notarizing is a
  release step.
