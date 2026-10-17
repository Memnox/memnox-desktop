# windows

The Windows layer of the Tauri app in `shared/tauri-core`. Only what Windows does differently
lives here.

- **The island:** a transparent window at the top of the main display that stays on top, never
  takes focus and lets clicks through where nothing is drawn (`WS_EX_NOACTIVATE`,
  `WS_EX_TOOLWINDOW`, and `WS_EX_TRANSPARENT` toggled).
- **The daemon:** reached over the named pipe `memnox-runtime` opens on Windows.
- **The confirm key:** a P-256 key in the TPM through the Platform Crypto Provider, used only
  after Windows Hello says yes. Its raw signature is converted to DER, the form the runtime checks.
- **Keeping awake:** `SetThreadExecutionState` while on power with a phone paired, so the phone can
  reach the computer from anywhere.
- **The installer:** NSIS and MSI, signed with Azure Trusted Signing from the first release.

Nothing here is built yet.
