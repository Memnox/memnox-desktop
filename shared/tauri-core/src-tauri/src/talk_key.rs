//! The key that starts talking from anywhere, so the person never has to find the island first. The
//! island hears it as a `talk` event and does what the Talk button does.

use tauri::{App, Emitter};
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};

/// Control and Alt with Space: free on Windows and the common Linux desktops, and reachable with one hand.
pub fn talk_shortcut() -> Shortcut {
    Shortcut::new(Some(Modifiers::CONTROL | Modifiers::ALT), Code::Space)
}

pub fn register(app: &App) -> Result<(), String> {
    let handle = app.handle().clone();
    app.global_shortcut()
        .on_shortcut(talk_shortcut(), move |_, _, event| {
            if event.state() == ShortcutState::Pressed {
                crate::tray::show_island(&handle);
                let _ = handle.emit("talk", ());
            }
        })
        .map_err(|error| error.to_string())
}
