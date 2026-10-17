//! Keeping the computer awake while a phone is paired and it runs on mains power, so the phone can
//! reach it from anywhere. A held call that arrives while it sleeps waits until it wakes.

use std::sync::mpsc::{channel, Sender};
use std::thread;
use windows::Win32::System::Power::{
    GetSystemPowerStatus, SetThreadExecutionState, ES_CONTINUOUS, ES_SYSTEM_REQUIRED,
    SYSTEM_POWER_STATUS,
};

/// `ACLineStatus` when the charger is in.
const ON_MAINS: u8 = 1;

/// Whether the computer runs on the charger; a desktop with no battery always does.
pub fn on_mains() -> bool {
    let mut status = SYSTEM_POWER_STATUS::default();
    unsafe { GetSystemPowerStatus(&mut status) }.is_ok() && status.ACLineStatus == ON_MAINS
}

/// Sleep held off while this lives. `SetThreadExecutionState` belongs to the thread that calls it, so one
/// thread of its own holds it, and dropping this ends that thread and lets the computer sleep again.
pub struct KeepAwake {
    stop: Sender<()>,
}

impl KeepAwake {
    pub fn start() -> Self {
        let (stop, stopped) = channel::<()>();
        thread::spawn(move || {
            unsafe { SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED) };
            let _ = stopped.recv();
            unsafe { SetThreadExecutionState(ES_CONTINUOUS) };
        });
        Self { stop }
    }
}

impl Drop for KeepAwake {
    fn drop(&mut self) {
        let _ = self.stop.send(());
    }
}
