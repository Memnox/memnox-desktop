# Testing the desktop apps

How to try each app on a real machine. For the unit tests every pull request runs, see
[Build and test](README.md#build-and-test) in the README.

| | Unit tests | On a real machine |
|---|---|---|
| **macOS** | `cd macos && swift test` | [below](#macos) |
| **Windows and Linux** | `cd shared/tauri-core && pnpm typecheck && pnpm test`, and `cargo test --workspace` from the root | [Windows](#windows) and [Linux](#linux) |
| **Every screen, with no daemon** | `cd shared/tauri-core && pnpm dev`, then `http://localhost:1420/preview.html` | |

## macOS

The Mac app builds and runs as [`macos/README.md`](macos/README.md) says.

The Windows and Linux app also runs on a Mac for its screens and its voice, with no key, so it signs
nothing: `cd shared/tauri-core && pnpm wire && pnpm install && pnpm tauri dev`. A debug build never adds
itself to the login items. Quit the Mac app first, since both would answer the same daemon, and note
that the talk key, Ctrl Alt Space, is taken while it runs.

## Windows

A Windows 11 PC, or a Windows 11 virtual machine; on an Apple silicon Mac, Parallels or UTM runs the x64
build through Windows' own emulation. The machine needs a TPM, which both give a virtual one of, and
Windows Hello set up, where a PIN is enough.

1. **Get the installer.** On GitHub, Actions, Release the Windows and Linux app, Run workflow on `main`.
   A run without a tag builds unsigned installers; download `installers-windows-latest`. Windows warns
   about an unsigned app: More info, Run anyway. A tagged release is signed and never warns.
2. **Open Memnox.** The first run installs the runtime, fetching its own Node when the machine has none,
   wires the agents it finds, starts the service, registers the confirm key and installs the voice. Watch
   the setup list in Settings, Overview, for anything it could not do.
3. **Answer a held call.** Have an agent on that machine do something a rule holds. Allow once raises
   Windows Hello naming the call; `memnox explain <id>` then shows the signature verified.
4. **Talk and dictate.** Press Ctrl Alt Space and ask what your agents are doing. Hold right Alt in
   Notepad and speak, and check nothing is typed into a password field.
5. **Bring a session forward.** Start a session in WezTerm or in VS Code and open it from the island.
   From Windows Terminal, Memnox should say it cannot switch tabs rather than doing anything else.

## Linux

Ubuntu 24.04, Fedora or Arch on x86_64 installs the release packages with
`curl -fsSL https://memnox.com/install | sh`
once a release exists, or the `installers-ubuntu-22.04` artifact from the same workflow run as Windows.

On an Apple silicon Mac the virtual machine is arm64, which the release does not build, so build it there:

```sh
sudo apt install -y build-essential curl git libwebkit2gtk-4.1-dev libgtk-3-dev \
  libayatana-appindicator3-dev librsvg2-dev libgtk-layer-shell-dev libasound2-dev
# Node 22 or newer, which the runtime needs and Ubuntu's own package is older than.
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash && . ~/.nvm/nvm.sh && nvm install 22
curl https://sh.rustup.rs -sSf | sh && npm install -g pnpm@9.15.4
git clone git@github.com:Memnox/memnox.git memnox-runtime
git clone git@github.com:Memnox/memnox-desktop.git
sudo install -m 644 memnox-desktop/linux/packaging/org.memnox.desktop.policy /usr/share/polkit-1/actions/
cd memnox-desktop/shared/tauri-core && pnpm wire && pnpm install && pnpm tauri dev
```

Allow once raises polkit's prompt naming the call. Try both GNOME and KDE, on Wayland and on X11:

- **The island** is a layer shell surface on KDE, Sway and Hyprland, and a window kept on top on GNOME.
  Clicks beside it should reach the window underneath.
- **The keys** go through the GlobalShortcuts portal on Wayland, which shows its own dialog once.
- **Typing** asks once through the RemoteDesktop portal on GNOME, and needs `wtype` or `ydotool` on
  other Wayland desktops and `xdotool` on X11.
- **The tray** should open the panel on a left click on KDE, and on GNOME with the AppIndicator extension.

## What none of this has proven yet

Every Windows and Linux path has only been compiled and unit tested, and the preview pages drawn in a
browser. None has yet been run end to end on real hardware:

- Windows Hello over the TPM key, and polkit with the Secret Service key;
- the named pipe and the unix socket against a live daemon;
- the island on each compositor, its input region and the display it is pinned to;
- the keyboard hook, the portals and evdev, and typing on each session;
- the microphone, the voice models' download and the echo cancelling;
- focus through WezTerm, kitty, Windows Terminal and the editors;
- pairing a phone and a server over the relay, and the team's calls;
- the first run's real install of the runtime and its Node.

Expect the first runs to find things.
