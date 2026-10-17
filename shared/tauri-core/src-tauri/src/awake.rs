//! Keeping the computer awake while a phone is paired and it runs on the charger, so the phone reaches
//! it from anywhere. The core decides when; this only holds sleep off or lets it go.

use std::sync::Mutex;

#[cfg(target_os = "linux")]
use memnox_linux::{on_mains, KeepAwake};
#[cfg(windows)]
use memnox_windows::{on_mains, KeepAwake};

/// The hold on sleep, None while the computer may sleep.
#[derive(Default)]
pub struct Awake(Mutex<Option<Box<dyn Send>>>);

#[tauri::command]
pub fn keep_awake(awake: tauri::State<'_, Awake>, on: bool) {
    let mut held = awake
        .0
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    if !on {
        *held = None;
    } else if held.is_none() {
        *held = hold();
    }
}

/// Whether the computer runs on the charger, which is the only time it is kept awake.
#[tauri::command]
pub fn on_power() -> bool {
    #[cfg(any(windows, target_os = "linux"))]
    return on_mains();
    #[allow(unreachable_code)]
    true
}

fn hold() -> Option<Box<dyn Send>> {
    #[cfg(any(windows, target_os = "linux"))]
    return Some(Box::new(KeepAwake::start()));
    #[allow(unreachable_code)]
    None
}
