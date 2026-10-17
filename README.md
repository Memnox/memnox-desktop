# Memnox for the desktop

The face, the voice and the signing key of [Memnox](VISION.md) on every desktop. The daemon in
[memnox-runtime](https://github.com/Memnox/memnox) decides what an agent may do; these apps show
what waits, speak and listen, and sign every yes that reaches outside a session.

| Folder | Holds | State |
|---|---|---|
| [`macos/`](macos) | Memnox for macOS: the notch island, the orb, the voice and Touch ID, in Swift 6 with Apple frameworks only. | shipping as a developer preview |
| [`windows/`](windows) | The Windows layer of one Tauri app: the island window, Windows Hello over a TPM key, the installer. | held calls answered with a signed yes, built in CI |
| [`linux/`](linux) | The Linux layer of the same Tauri app: layer shell on Wayland, the Secret Service key, the packages. | held calls answered with a signed yes, built in CI |
| [`shared/`](shared) | The Tauri app's core, the protocol vectors every desktop is tested against, and the design tokens. | the core, the island and the vectors |

The phone apps live in [memnox-mobile](https://github.com/Memnox/memnox-mobile).

## Install on a Mac

On an Apple silicon Mac with macOS 14 or later:

```sh
curl -fsSL https://raw.githubusercontent.com/Memnox/memnox-desktop/main/macos/scripts/install.sh | sh
```

[`macos/README.md`](macos/README.md) says what it does, how to build it from source and how it
is put together.

## Install on Linux or Windows

On x86_64 Linux, which installs the deb, the rpm or the AppImage, each checked against the release's
SHA256SUMS:

```sh
curl -fsSL https://raw.githubusercontent.com/Memnox/memnox-desktop/main/linux/scripts/install.sh | sh
```

On Windows, download the signed installer from the newest `app-v` release. Arch users can build
the PKGBUILD published beside it. A release is cut by pushing a tag `app-v<version>` that matches
`shared/tauri-core/src-tauri/tauri.conf.json`, and a Windows build is never published unsigned.

## License

The code is MIT, as [LICENSE](LICENSE) says. The Memnox name and artwork are not, as
[LICENSE-ASSETS.md](LICENSE-ASSETS.md) says. Report a vulnerability as [SECURITY.md](SECURITY.md)
asks, and see the [code of conduct](CODE_OF_CONDUCT.md).
