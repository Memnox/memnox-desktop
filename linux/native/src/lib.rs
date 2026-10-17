//! What Memnox does differently on Linux, and nothing else: the shared Tauri app in
//! `shared/tauri-core` calls these where Windows calls `memnox-windows`. Every item compiles to
//! nothing off Linux, so the app's one crate builds on every desktop.

#[cfg(all(target_os = "linux", feature = "island"))]
mod island;
#[cfg(target_os = "linux")]
mod power;
#[cfg(target_os = "linux")]
mod secret_key;

#[cfg(all(target_os = "linux", feature = "island"))]
pub use island::{island_keyboard, make_island};
#[cfg(target_os = "linux")]
pub use power::{on_mains, KeepAwake};
#[cfg(target_os = "linux")]
pub use secret_key::SecretKey;
