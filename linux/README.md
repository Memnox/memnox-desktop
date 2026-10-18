<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../macos/Support/Logo/memnox-mark-white.png">
  <img src="../macos/Support/Logo/memnox-mark-template.png" alt="Memnox" width="72">
</picture>

# Memnox for Linux

### The island on your compositor, the voice on your computer, and polkit on every yes.

[![Linux x86_64](https://img.shields.io/badge/Linux-x86__64-FCC624?logo=linux&logoColor=black)](#requirements)
[![Wayland and X11](https://img.shields.io/badge/session-Wayland%20%7C%20X11-6E56CF)](#on-each-desktop)
[![Packages](https://img.shields.io/badge/packages-deb%20%7C%20rpm%20%7C%20AppImage%20%7C%20AUR%20PKGBUILD-555555)](#install)
[![Tauri 2](https://img.shields.io/badge/Tauri-2-24C8DB?logo=tauri&logoColor=white)](../shared)
[![License MIT](https://img.shields.io/badge/license-MIT-37CD8F)](../LICENSE)

[Install](#install) · [On each desktop](#on-each-desktop) · [What Linux does differently](#what-linux-does-differently) · [Build](#build-from-source) · [Test](#test) · [Known limits](#known-limits)

<br>

<table>
<tr>
<td width="62%" valign="top">
<img src="../docs/images/tauri-island-sessions.png" width="100%" alt="The Memnox island showing Sessions with two working: Claude Code porting the island session screen with its latest steps, and a list of sessions from Claude Code, Codex, Cursor and Gemini.">
<br><br>
<img src="../docs/images/tauri-island-voice.png" width="100%" alt="The island open on the orb, a sphere of blue points rippling while it listens, with the words heard so far under it: push the fix to main and tell the team.">
</td>
<td width="38%" valign="top">
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../docs/images/tauri-tray-panel-dark.png">
  <img src="../docs/images/tauri-tray-panel-light.png" width="100%" alt="The tray panel: the Memnox wordmark with Ctrl Alt Space, the connected agents and apps, and the rows Talk to Memnox, Say a rule, Copy what happened, Mute voice, Settings and Quit Memnox.">
</picture>
</td>
</tr>
</table>

</div>

---

Memnox for Linux is the Tauri app in [`shared/tauri-core`](../shared), the same one Windows runs.
This folder holds only what Linux does differently: the `memnox-linux` crate in [`native/`](native),
the polkit policy and the Arch PKGBUILD in [`packaging/`](packaging), and the installer in
[`scripts/install.sh`](scripts/install.sh).

## Requirements

- **x86_64**, on Ubuntu 22.04 or later, Debian, Fedora, openSUSE, Arch, or any distribution the
  AppImage runs on. The release does not build for arm64.
- **A Secret Service**, such as GNOME Keyring or KWallet, to keep the confirm key.
- **A polkit agent**, which GNOME Shell and KDE carry and most other desktops run, to ask before
  each signature. With fprintd set up it asks for a fingerprint, otherwise for your password.
- **A microphone.** Linux asks nothing before an app hears, so Memnox only checks there is one.

No Node and no terminal are needed: the first run finds `memnox` or installs it, fetching its own
Node into `~/.memnox/node` checked against the release's SHASUMS256 when the computer has none.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/Memnox/memnox-desktop/main/linux/scripts/install.sh | sh
```

It finds the newest `app-v` release, checks the download against its `SHA256SUMS` and installs
nothing that does not match. It picks:

| Where | It installs |
|---|---|
| `apt` | the deb, which puts the polkit policy in place itself |
| `dnf` or `zypper` | the rpm, which does the same |
| anywhere else | the AppImage as `~/.local/bin/memnox-desktop.AppImage`, and the checked polkit policy in `/usr/share/polkit-1/actions` |

On Arch, build the `PKGBUILD` published beside each release, which installs that release's deb as
`memnox-desktop-bin`.

## On each desktop

| | KDE Plasma | GNOME | Sway, Hyprland, COSMIC | X11 |
|---|---|---|---|---|
| **The island** | layer shell | a window kept on top, since GNOME has no layer shell | layer shell | a window kept on top |
| **Clicks through it** | the input region | the input region | the input region | the XShape input shape |
| **A click outside closes it** | no, Escape and the idle close do | no | no | yes |
| **Choosing its display** | yes | no | yes | yes |
| **The keys** | the GlobalShortcuts portal (5.27 and later) | the portal (GNOME 48 and later) | the portal on Hyprland, none on sway | the keymap, with no permission |
| **Typing for you** | `wtype` or `ydotool` | the RemoteDesktop portal, which asks once | `wtype` or `ydotool` | `xdotool` |
| **The tray panel on a left click** | yes | with the AppIndicator extension | where a StatusNotifierItem host runs | where a StatusNotifierItem host runs |
| **Glass under the panel** | KWin blur | a near solid wash | a near solid wash | KWin blur on KDE |

Where you have added yourself to the `input` group, Memnox reads the keyboards' own event devices
instead, which sees the bare modifiers in every app on Wayland too. That access is the opt in: without
it, that path is never taken, and it only looks.

## What Linux does differently

| | How |
|---|---|
| **The island** | A gtk-layer-shell surface anchored to the top edge where the compositor has layer shell, which stays above windows and never takes the keyboard; the side panel and the card wall hang from their own edges the same way. Each takes clicks only inside its input region, so the compositor routes them and no pointer is read. |
| **The confirm key** | A P-256 key kept in the login keyring through the Secret Service and used only after polkit asks, through the action in [`packaging/org.memnox.desktop.policy`](packaging/org.memnox.desktop.policy), with no grace period. |
| **The daemon** | The unix socket `~/.memnox/memnox.sock`, refused unless the process listening on it runs as the same user, checked with `SO_PEERCRED`. |
| **The keys** | Ctrl Alt Space to talk, Ctrl with left Alt held to say a rule, and right Alt held to dictate, or right Ctrl where right Alt is AltGr. On Wayland the portal binds a chord for each and shows its own dialog the first time. |
| **Typing for you** | The session's own tools, with the focused field read through AT-SPI on X11 and Wayland alike, so a password field is never typed into. Qt, Chromium and Electron apps answer once accessibility is switched on for the session, which Memnox asks for. The clipboard goes through `wl-copy`, `xclip` or `xsel`. |
| **Bringing a session forward** | WezTerm through `wezterm cli`, kitty through its remote control where you turned it on, and VS Code, Cursor, Windsurf, VSCodium and the Flatpak VS Code through their own command line. |
| **The tray** | A StatusNotifierItem through `ksni`, which hears a left click as appindicator never does, so the panel opens beside the icon. The Tauri tray stands in where no StatusNotifierItem host runs. |
| **Coming back** | logind's `LockedHint`, which GNOME, KDE and lockers driven by `xss-lock` all set, so Catch me up knows when you left. |
| **Keeping awake** | `systemd-inhibit` while on power with a phone paired. |
| **The packages** | AppImage, deb and rpm built on Ubuntu 22.04 so older glibc runs them, with SHA256SUMS, the polkit policy and a PKGBUILD beside them. |

## Build from source

On Ubuntu or Debian:

```sh
sudo apt install -y build-essential curl git libwebkit2gtk-4.1-dev libgtk-3-dev \
  libayatana-appindicator3-dev librsvg2-dev libgtk-layer-shell-dev libasound2-dev
sudo install -m 644 linux/packaging/org.memnox.desktop.policy /usr/share/polkit-1/actions/
```

Then, with Node 22, pnpm 9.15.4, stable Rust, and a
[memnox-runtime](https://github.com/Memnox/memnox) checkout beside this repo or named by
`MEMNOX_RUNTIME`:

```sh
cd shared/tauri-core
pnpm wire                 # builds memnox-runtime's core and copies its wire into .runtime
pnpm install
pnpm typecheck && pnpm test
cargo test --workspace    # from the repo root
pnpm tauri dev
```

The layer shell island needs GTK, so `memnox-linux` keeps it behind its default `island` feature;
`cargo check -p memnox-linux --no-default-features` checks the rest without a GTK sysroot.

<details>
<summary><b>Optional tools, by session</b></summary>

| For | Install |
|---|---|
| Typing on X11 | `xdotool` |
| Typing on Wayland, outside GNOME | `wtype`, or `ydotool` with its daemon |
| The clipboard | `wl-clipboard` on Wayland, `xclip` or `xsel` on X11 |
| The tray panel on GNOME | the AppIndicator and KStatusNotifierItem extension |
| A fingerprint rather than a password | `fprintd`, enrolled |

Memnox says out loud which one it is missing when it needs it.

</details>

## Test

CI typechecks, tests and builds the app on Ubuntu 24.04 for every pull request. To try it on a real
machine, including an arm64 virtual machine on an Apple silicon Mac, follow the Linux steps in
[TESTING.md](../TESTING.md#linux), and try both GNOME and KDE.

## Known limits

- **The keyring is the weakest desktop key.** It is open to every process of the same user while the
  session is unlocked, so a process that reads it directly could sign without polkit. A paired phone
  stays the stronger place to say yes on Linux.
- **GNOME has no layer shell**, so there the island is a window kept on top, and it cannot be pinned
  to a chosen display.
- **Older GNOME and sway have no GlobalShortcuts portal**, so without the `input` group the keys are
  not seen there, and Memnox says so; the talk button and the wake word still work.
- **A teammate's proposal answered by voice** asks polkit twice, where the Mac asks once.
- **x86_64 only** in releases; arm64 builds from source.
- **Not proven on hardware yet.** polkit with the Secret Service key, the island on each compositor,
  the portals and typing have been compiled and unit tested, and
  [TESTING.md](../TESTING.md#what-none-of-this-has-proven-yet) lists what a first real run should check.
