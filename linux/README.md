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

Nothing here is built yet.
