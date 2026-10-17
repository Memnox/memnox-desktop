# Memnox for the desktop

The face, the voice and the signing key of [Memnox](VISION.md) on every desktop. The daemon in
[memnox-runtime](https://github.com/Memnox/memnox) decides what an agent may do; these apps show
what waits, speak and listen, and sign every yes that reaches outside a session.

| Folder | Holds | State |
|---|---|---|
| [`macos/`](macos) | Memnox for macOS: the notch island, the orb, the voice and Touch ID, in Swift 6 with Apple frameworks only. | shipping as a developer preview |
| [`windows/`](windows) | The Windows layer of one Tauri app: the island window, Windows Hello over a TPM key, the installer. | planned |
| [`linux/`](linux) | The Linux layer of the same Tauri app: layer shell on Wayland, the Secret Service key, the packages. | planned |
| [`shared/`](shared) | The Tauri app's core, the protocol vectors every desktop is tested against, and the design tokens. | planned |

The phone apps live in [memnox-mobile](https://github.com/Memnox/memnox-mobile).

## Install on a Mac

On an Apple silicon Mac with macOS 14 or later:

```sh
curl -fsSL https://raw.githubusercontent.com/Memnox/memnox-desktop/main/macos/scripts/install.sh | sh
```

[`macos/README.md`](macos/README.md) says what it does, how to build it from source and how it
is put together.

## License

The code is MIT, as [LICENSE](LICENSE) says. The Memnox name and artwork are not, as
[LICENSE-ASSETS.md](LICENSE-ASSETS.md) says. Report a vulnerability as [SECURITY.md](SECURITY.md)
asks, and see the [code of conduct](CODE_OF_CONDUCT.md).
