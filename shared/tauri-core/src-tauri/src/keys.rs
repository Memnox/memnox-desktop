//! The keys held from anywhere: right Alt to dictate and Ctrl with left Alt to say a rule. Each platform
//! reports which modifiers are down and that another key went down as the `keys` event; the island's
//! core decides what a hold means, so the timing is the Mac's and is tested in one place.

mod event;
#[cfg(target_os = "linux")]
#[path = "keys/linux.rs"]
mod on_linux;
#[cfg(target_os = "linux")]
#[path = "keys/portal.rs"]
mod portal;
#[cfg(target_os = "linux")]
#[path = "keys/evdev.rs"]
mod evdev_keys;
#[cfg(windows)]
#[path = "keys/windows.rs"]
mod on_windows;

use std::sync::Mutex;

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager};

use event::Sink;

/// Why the keys cannot be seen, kept so the island can say it; None while they are watched.
#[derive(Default)]
pub struct KeyWatch(Mutex<Option<String>>);

#[derive(Serialize)]
pub struct KeysWatching {
    watching: bool,
    why: Option<String>,
}

/// Starts watching for the life of the app; a failure is kept rather than stopping the app, since talking still works.
pub fn start(app: &AppHandle) {
    let handle = app.clone();
    let sink: Sink = Box::new(move |event| {
        let _ = match event {
            event::KeyEvent::Talk => handle.emit("talk", ()),
            other => handle.emit("keys", other),
        };
    });
    // The field with the keyboard is followed from launch, where the platform only reports it by events.
    crate::typing::watch_focus();
    let why = platform_watch(sink).err();
    if let Some(why) = &why {
        eprintln!("Memnox: the hold keys cannot be seen: {why}");
    }
    app.manage(KeyWatch(Mutex::new(why)));
}

#[cfg(windows)]
fn platform_watch(sink: Sink) -> Result<(), String> {
    on_windows::watch(sink)
}

#[cfg(target_os = "linux")]
fn platform_watch(sink: Sink) -> Result<(), String> {
    on_linux::watch(sink)
}

#[cfg(not(any(windows, target_os = "linux")))]
fn platform_watch(sink: Sink) -> Result<(), String> {
    drop(sink);
    Err("not on this system".into())
}

/// Whether the keyboard's layout types with AltGr, so right Alt would collide with typing; None when unread.
#[tauri::command]
pub fn keyboard_has_altgr() -> Option<bool> {
    #[cfg(windows)]
    return on_windows::has_altgr();
    #[cfg(target_os = "linux")]
    return on_linux::has_altgr();
    #[cfg(not(any(windows, target_os = "linux")))]
    None
}

#[tauri::command]
pub fn keys_watching(watch: tauri::State<'_, KeyWatch>) -> KeysWatching {
    let why = watch.0.lock().ok().and_then(|why| why.clone());
    KeysWatching {
        watching: why.is_none(),
        why,
    }
}
