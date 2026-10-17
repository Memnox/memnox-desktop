//! What Memnox does differently on Windows, and nothing else: the shared Tauri app in
//! `shared/tauri-core` calls these where Linux calls `memnox-linux`. Every item compiles to
//! nothing off Windows, so the app's one crate builds on every desktop.

#[cfg(windows)]
mod island;
#[cfg(windows)]
mod power;
#[cfg(windows)]
mod tpm_key;

#[cfg(windows)]
pub use island::make_island;
#[cfg(windows)]
pub use power::{on_mains, KeepAwake};
#[cfg(windows)]
pub use tpm_key::TpmKey;
