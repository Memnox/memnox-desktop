# Testing the desktop apps

## macOS

The Mac app builds and runs as `macos/README.md` says. It is the one desktop already shipping.

The Windows and Linux app also runs on a Mac for its screens and its voice, with no key, so it signs
nothing: `cd shared/tauri-core && pnpm wire && pnpm install && pnpm tauri dev`. A debug build never adds
itself to the login items. Quit the Mac app first, since both would answer the same daemon, and note
that the talk key, Ctrl Alt Space, is taken while it runs.

## Windows

A Windows 11 PC, or a Windows 11 virtual machine; on an Apple silicon Mac, Parallels or UTM runs the x64
build through Windows' own emulation. The machine needs a TPM, which both give a virtual one of, and
Windows Hello set up, where a PIN is enough.

1. **Get the installer:** on GitHub, Actions, Release the Windows and Linux app, Run workflow on `main`.
   A run without a tag builds unsigned installers; download `installers-windows-latest`. Windows warns
   about an unsigned app: More info, Run anyway. A tagged release is signed and never warns.
2. **Install Node.js LTS** first, since setup installs `memnox` from npm the first time.
3. **Open Memnox.** It installs the runtime, wires the agents it finds, starts the service and installs its
   voice when you press Install the voice. Watch the setup row for anything it could not do.
4. **Answer a held call:** have an agent on that machine do something a rule holds. Allow once raises
   Windows Hello naming the call; `memnox explain <id>` then shows the signature verified.

## Linux

Ubuntu 24.04, Fedora or Arch on x86_64 installs the release packages with
`curl -fsSL https://raw.githubusercontent.com/Memnox/memnox-desktop/main/linux/scripts/install.sh | sh`
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

Allow once raises polkit's prompt naming the call. Try both GNOME and KDE: the island is a layer shell
surface on KDE, Sway and Hyprland, and an ordinary window kept on top on GNOME.

## What none of this has proven yet

Every Windows and Linux path has only been compiled and unit tested: Windows Hello over the TPM key, the
named pipe, polkit with the Secret Service key, the island on each compositor, the microphone, and setup's
real npm install. Expect the first runs to find things.
