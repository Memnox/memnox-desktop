//! The one Noise layer the Memnox runtime, the phones, the Mac and this app share. `core.rs` and the
//! vectors test are copied whole from memnox-runtime's `native/noise` by `scripts/sync-noise.sh`, and never
//! edited here, so every cipher, hash, DH and nonce is snow's and the same build the runtime answers with.

pub mod core;
