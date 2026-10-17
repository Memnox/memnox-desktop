//! The tray: bring the island back, start Memnox when the person signs in, and quit. Starting at sign in
//! is on unless the person turns it off, since a held call that arrives with Memnox closed waits unseen.

use tauri::menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{App, AppHandle, Manager};
use tauri_plugin_autostart::ManagerExt;

const SHOW: &str = "show";
const AT_SIGN_IN: &str = "at-sign-in";
const QUIT: &str = "quit";

pub fn build(app: &App) -> tauri::Result<()> {
    let starts = app.autolaunch().is_enabled().unwrap_or(false);
    let show = MenuItem::with_id(app, SHOW, "Show Memnox", true, None::<&str>)?;
    let at_sign_in = CheckMenuItem::with_id(
        app,
        AT_SIGN_IN,
        "Start when you sign in",
        true,
        starts,
        None::<&str>,
    )?;
    let quit = MenuItem::with_id(app, QUIT, "Quit Memnox", true, None::<&str>)?;
    let menu = Menu::with_items(
        app,
        &[
            &show,
            &at_sign_in,
            &PredefinedMenuItem::separator(app)?,
            &quit,
        ],
    )?;
    let mut tray = TrayIconBuilder::with_id("memnox")
        .tooltip("Memnox")
        .menu(&menu);
    if let Some(icon) = app.default_window_icon() {
        tray = tray.icon(icon.clone());
    }
    tray.on_menu_event(move |app, event| match event.id().as_ref() {
        SHOW => show_island(app),
        AT_SIGN_IN => toggle_at_sign_in(app, &at_sign_in),
        QUIT => app.exit(0),
        _ => {}
    })
    .build(app)?;
    Ok(())
}

pub fn show_island(app: &AppHandle) {
    if let Some(window) = app.get_webview_window(crate::ISLAND) {
        let _ = window.show();
    }
}

fn toggle_at_sign_in(app: &AppHandle, item: &CheckMenuItem<tauri::Wry>) {
    let autolaunch = app.autolaunch();
    let on = !autolaunch.is_enabled().unwrap_or(false);
    let changed = if on {
        autolaunch.enable()
    } else {
        autolaunch.disable()
    };
    let _ = item.set_checked(changed.is_ok() == on);
}

/// The first run turns starting at sign in on; afterwards the person's choice in the tray stands.
pub fn start_at_sign_in_once(app: &App) {
    // A development build, such as `pnpm tauri dev` on a Mac, never adds itself to the login items.
    if cfg!(debug_assertions) {
        return;
    }
    let marker = app
        .path()
        .app_config_dir()
        .map(|dir| dir.join("asked-to-start-at-sign-in"));
    let Ok(marker) = marker else { return };
    if marker.exists() {
        return;
    }
    let _ = app.autolaunch().enable();
    if let Some(dir) = marker.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::write(marker, b"");
}
