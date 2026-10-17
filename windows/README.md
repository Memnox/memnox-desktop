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

## What is built

`native/` is the `memnox-windows` crate the shared app depends on only on Windows: `TpmKey` (a P-256 key made inside the TPM through the Platform Crypto Provider, used only after Windows Hello says yes over the island's window), `KeepAwake` and `on_mains`, and `make_island`. The TPM key does not itself demand Hello, so a process of the same user calling NCrypt directly could sign without it; a paired phone stays the stronger place to say yes.

`.github/workflows/release-app.yml` builds the NSIS and MSI installers and signs them with Azure Trusted Signing; a tag never publishes one unsigned. It needs the secrets `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID`, `AZURE_SIGNING_ENDPOINT`, `AZURE_SIGNING_ACCOUNT` and `AZURE_SIGNING_PROFILE`.

The pipe's ACL and a service that restarts after a crash come next.
