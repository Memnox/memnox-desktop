//! A press on a held call's system notification opens the Memnox window on Approvals. The notification itself is
//! posted by the island, which knows which call it is already showing; this only answers the press.

use tauri::AppHandle;
use tauri_plugin_notification::NotificationExt;

/// A press on the notification itself, rather than one of its buttons, which these never carry.
const TAP: &str = "tap";

pub fn answer_presses(app: &AppHandle) {
    let handle = app.clone();
    let _ = app.notification().on_action(move |action| {
        if action.action_id() != TAP {
            return;
        }
        let opening = handle.clone();
        // The window is made on the main thread, and the press arrives on the notification's own.
        let _ = handle.run_on_main_thread(move || {
            if let Err(why) = crate::settings_windows::show_approvals(&opening) {
                eprintln!("Memnox: Approvals could not open: {why}");
            }
        });
    });
}
