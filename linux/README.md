# linux

The Linux layer of the Tauri app in `shared/tauri-core`. Only what Linux does differently lives
here.

- **The island:** a gtk-layer-shell surface anchored to the top edge on KDE, Sway, Hyprland and
  COSMIC, and a dock window through XWayland on GNOME, which has no layer shell.
- **The daemon:** reached over the unix socket `memnox-runtime` opens, checked to belong to the
  same user with `SO_PEERCRED`.
- **The confirm key:** a P-256 key kept in the Secret Service, released only after a local polkit
  or fprintd check. A paired phone stays the stronger place to say yes on Linux.
- **Keeping awake:** `systemd-inhibit` while on power with a phone paired.
- **The packages:** AppImage, deb, rpm and a PKGBUILD, with SHA256SUMS published beside them.

## What is built

`native/` is the `memnox-linux` crate the shared app depends on only on Linux: `SecretKey` (a P-256 key kept in the login keyring and used only after polkit asks, through `packaging/org.memnox.desktop.policy`), `KeepAwake` and `on_mains`, and `make_island` on layer shell, which needs GTK and so sits behind the `island` feature. The keyring is open to every process of the same user while the session is unlocked, which makes this the weakest desktop key.

The XWayland dock on GNOME and the AppImage, deb, rpm and PKGBUILD releases come next; the deb and rpm already install the polkit policy.
