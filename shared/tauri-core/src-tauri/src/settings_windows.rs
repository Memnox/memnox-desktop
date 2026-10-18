//! The two ordinary windows beside the island, as the Mac's `SettingsWindow` and `OnboardingWindow` keep
//! them: Settings at a fixed 940 by 720 with its sidebar, and the first run at 1000 by 660. Each is made
//! the first time it is asked for and brought forward after that, so there is only ever one of each.

use tauri::{AppHandle, Emitter, Manager, Theme, WebviewUrl, WebviewWindow, WebviewWindowBuilder};
use tauri_plugin_autostart::ManagerExt;

/// The Settings window, by the label the capability names.
pub const SETTINGS: &str = "settings";
/// The first run's window, by the label the capability names.
pub const ONBOARDING: &str = "onboarding";

/// The Mac's `SettingsWindow` size, fixed, since its pages are laid out for that width.
const SETTINGS_SIZE: (f64, f64) = (940.0, 720.0);
/// The Mac's onboarding window, and the smallest it may be made.
const ONBOARDING_SIZE: (f64, f64) = (1000.0, 660.0);
const ONBOARDING_MIN: (f64, f64) = (860.0, 560.0);

/// Told to an open Settings window when the island or the tray asks for one page of it.
const SHOW_PAGE: &str = "settings-page";

/// Opens Settings on a page, or brings it forward on that page when it is already open.
#[tauri::command]
pub fn open_settings(app: AppHandle, page: Option<String>) -> Result<(), String> {
    show_settings(&app, page.as_deref()).map_err(|error| error.to_string())
}

/// Settings from Rust as from the webview, so the tray can open it too.
pub fn show_settings(app: &AppHandle, page: Option<&str>) -> tauri::Result<()> {
    if let Some(window) = app.get_webview_window(SETTINGS) {
        if let Some(page) = page {
            window.emit(SHOW_PAGE, page)?;
        }
        return bring_forward(&window);
    }
    let path = match page {
        Some(page) => format!("settings.html?page={page}"),
        None => "settings.html".to_owned(),
    };
    let window = WebviewWindowBuilder::new(app, SETTINGS, WebviewUrl::App(path.into()))
        .title("Memnox")
        .inner_size(SETTINGS_SIZE.0, SETTINGS_SIZE.1)
        .resizable(false)
        .maximizable(false)
        .center()
        .theme(chosen_theme(app))
        .build()?;
    bring_forward(&window)
}

/// Opens the first run, or brings it forward when it is already up.
#[tauri::command]
pub fn open_onboarding(app: AppHandle) -> Result<(), String> {
    if let Some(window) = app.get_webview_window(ONBOARDING) {
        return bring_forward(&window).map_err(|error| error.to_string());
    }
    WebviewWindowBuilder::new(&app, ONBOARDING, WebviewUrl::App("onboarding.html".into()))
        .title("Welcome to Memnox")
        .inner_size(ONBOARDING_SIZE.0, ONBOARDING_SIZE.1)
        .min_inner_size(ONBOARDING_MIN.0, ONBOARDING_MIN.1)
        .center()
        .theme(chosen_theme(&app))
        .build()
        .and_then(|window| bring_forward(&window))
        .map_err(|error| error.to_string())
}

/// Closes the window that asked, for Escape in Settings and the last button of the first run.
#[tauri::command]
pub fn close_window(window: WebviewWindow) -> Result<(), String> {
    window.close().map_err(|error| error.to_string())
}

/// The look the person picked, applied to the frame of every window but the island, which stays dark
/// as the Mac's notch does. The pages repaint themselves from the same choice.
#[tauri::command]
pub fn apply_appearance(app: AppHandle, look: String) -> Result<(), String> {
    let theme = theme_of(&look);
    remember_look(&app, &look);
    for (label, window) in app.webview_windows() {
        if label == crate::ISLAND {
            continue;
        }
        window.set_theme(theme).map_err(|error| error.to_string())?;
    }
    Ok(())
}

/// Whether Memnox starts when the person signs in, which the tray also switches.
#[tauri::command]
pub fn start_at_sign_in(app: AppHandle) -> bool {
    app.autolaunch().is_enabled().unwrap_or(false)
}

/// Turns starting at sign in on or off, answering where it stands after.
#[tauri::command]
pub fn set_start_at_sign_in(app: AppHandle, on: bool) -> bool {
    let autolaunch = app.autolaunch();
    let _ = if on {
        autolaunch.enable()
    } else {
        autolaunch.disable()
    };
    autolaunch.is_enabled().unwrap_or(false)
}

/// Starts Memnox again, for a grant the system hands over only to a fresh start.
#[tauri::command]
pub fn restart_memnox(app: AppHandle) {
    app.restart();
}

/// Opens a page in the person's browser, such as the console's sign in page; only https is opened.
#[tauri::command]
pub fn open_page(url: String) -> Result<(), String> {
    if !url.starts_with("https://") {
        return Err("only an https page is opened".to_owned());
    }
    crate::permissions::open_with_system(&url)
}

fn bring_forward(window: &WebviewWindow) -> tauri::Result<()> {
    window.unminimize()?;
    window.show()?;
    window.set_focus()
}

/// Light and Dark set the frame; System leaves it to the computer.
fn theme_of(look: &str) -> Option<Theme> {
    match look {
        "light" => Some(Theme::Light),
        "dark" => Some(Theme::Dark),
        _ => None,
    }
}

/// The look is kept beside the app's settings, so a window made later opens in it rather than flashing.
fn look_file(app: &AppHandle) -> Option<std::path::PathBuf> {
    app.path()
        .app_config_dir()
        .ok()
        .map(|dir| dir.join("appearance.txt"))
}

fn remember_look(app: &AppHandle, look: &str) {
    if let Some(file) = look_file(app) {
        if let Some(dir) = file.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let _ = std::fs::write(file, look);
    }
}

fn chosen_theme(app: &AppHandle) -> Option<Theme> {
    let look = look_file(app).and_then(|file| std::fs::read_to_string(file).ok())?;
    theme_of(look.trim())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn system_leaves_the_frame_to_the_computer() {
        assert_eq!(theme_of("light"), Some(Theme::Light));
        assert_eq!(theme_of("dark"), Some(Theme::Dark));
        assert_eq!(theme_of("system"), None);
        assert_eq!(theme_of("anything"), None);
    }
}
