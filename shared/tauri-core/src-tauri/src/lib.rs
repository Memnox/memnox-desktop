//! Memnox on Windows and Linux: a face and a signing key over the daemon, and nothing else. The
//! webview draws the island from the core in `src/core`; this crate gives it the daemon, the key and
//! the window, and the platform crates in `windows/` and `linux/` hold what each system does its own way.

mod awake;
mod daemon;
mod key;

use tauri::Manager;

/// The island's window, as `tauri.conf.json` names it.
const ISLAND: &str = "island";

pub fn run() {
    tauri::Builder::default()
        .manage(awake::Awake::default())
        .setup(|app| {
            let window = app
                .get_webview_window(ISLAND)
                .ok_or("the island window is missing")?;
            app.manage(key::Key::for_platform(&window));
            make_island(&window);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            daemon::daemon_stream,
            key::confirm_key_point,
            key::confirm_key_sign,
            awake::keep_awake,
            awake::on_power,
        ])
        .run(tauri::generate_context!())
        .expect("Memnox could not start its window");
}

/// The platform's own island: no focus and no taskbar on Windows, a layer shell surface on Linux.
#[allow(unused_variables)]
fn make_island(window: &tauri::WebviewWindow) {
    #[cfg(windows)]
    if let Ok(hwnd) = window.hwnd() {
        memnox_windows::make_island(hwnd.0 as isize);
    }
    #[cfg(target_os = "linux")]
    if let Ok(gtk) = window.gtk_window() {
        memnox_linux::make_island(&gtk);
    }
}
