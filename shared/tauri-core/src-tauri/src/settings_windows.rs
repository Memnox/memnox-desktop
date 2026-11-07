//! The two ordinary windows beside the island: the Memnox window, which any size from a phone's width
//! to the whole screen lays out for, and the first run at 1000 by 660. Each is made the first time it is
//! asked for and brought forward after that, so there is only ever one of each.

use tauri::{AppHandle, Emitter, Manager, Theme, WebviewUrl, WebviewWindow, WebviewWindowBuilder};
use tauri_plugin_autostart::ManagerExt;

/// The Settings window, by the label the capability names.
pub const SETTINGS: &str = "settings";
/// The first run's window, by the label the capability names.
pub const ONBOARDING: &str = "onboarding";

/// The Memnox window opens wide enough for the inspector beside a page, and folds down to one column.
const SETTINGS_SIZE: (f64, f64) = (1240.0, 780.0);
const SETTINGS_MIN: (f64, f64) = (420.0, 520.0);
/// The Mac's onboarding window, and the smallest it may be made.
const ONBOARDING_SIZE: (f64, f64) = (1000.0, 660.0);
const ONBOARDING_MIN: (f64, f64) = (860.0, 560.0);

/// Told to an open Settings window when the island or the tray asks for one page of it.
const SHOW_PAGE: &str = "settings-page";

/// A popped out inspector's label starts with this, which the settings capability names with a wildcard.
const INSPECTOR_PREFIX: &str = "inspector-";
/// Wide enough for the details at their widest, tall enough for a server's tools.
const INSPECTOR_SIZE: (f64, f64) = (460.0, 640.0);
const INSPECTOR_MIN: (f64, f64) = (320.0, 360.0);
/// Each popped out inspector is its own window, so each gets a label of its own.
static INSPECTORS: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);

/// Governance on Approvals, where a held call's notification lands; an open window is told the destination by name.
const APPROVALS_PAGE: &str = "governance";
const APPROVALS_QUERY: &str = "dest=governance&tab=approvals";

/// The Memnox window and its popped out inspectors, the windows that draw the destinations.
pub fn is_memnox_window(label: &str) -> bool {
    label == SETTINGS || label.starts_with(INSPECTOR_PREFIX)
}

/// Opens the Memnox window on Approvals, or brings it forward there.
pub fn show_approvals(app: &AppHandle) -> tauri::Result<()> {
    if app.get_webview_window(SETTINGS).is_some() {
        return show_settings(app, Some(APPROVALS_PAGE));
    }
    let window = settings_builder(app, format!("settings.html?{APPROVALS_QUERY}")).build()?;
    bring_forward(&window)
}

/// Pops the selected item's details out into a window of their own, on the link the page names for that item.
#[tauri::command]
pub fn open_inspector(
    app: AppHandle,
    window: WebviewWindow,
    search: String,
    title: String,
) -> Result<(), String> {
    if !is_memnox_window(window.label()) {
        return Err("only the Memnox window pops out its details".to_owned());
    }
    if !search.starts_with('?') {
        return Err("the details are opened on a link of the Memnox window".to_owned());
    }
    let count = INSPECTORS.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    let label = format!("{INSPECTOR_PREFIX}{count}");
    let path = format!("settings.html{search}");
    WebviewWindowBuilder::new(&app, label, WebviewUrl::App(path.into()))
        .title(title)
        .inner_size(INSPECTOR_SIZE.0, INSPECTOR_SIZE.1)
        .min_inner_size(INSPECTOR_MIN.0, INSPECTOR_MIN.1)
        .resizable(true)
        .theme(chosen_theme(&app))
        .build()
        .and_then(|window| bring_forward(&window))
        .map_err(|error| error.to_string())
}

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
    let window = settings_builder(app, path).build()?;
    bring_forward(&window)
}

fn settings_builder(
    app: &AppHandle,
    path: String,
) -> WebviewWindowBuilder<'_, tauri::Wry, AppHandle> {
    WebviewWindowBuilder::new(app, SETTINGS, WebviewUrl::App(path.into()))
        .title("Memnox")
        .inner_size(SETTINGS_SIZE.0, SETTINGS_SIZE.1)
        .min_inner_size(SETTINGS_MIN.0, SETTINGS_MIN.1)
        .resizable(true)
        .center()
        .theme(chosen_theme(app))
}

/// Opens the first run, or brings it forward when it is already up. It opens as the Mac's veil, over the
/// whole screen with no frame and above the rest, since it starts on the wordmark; the page shrinks it to
/// the steps window through `onboarding_veil` once the opening is done.
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
        .decorations(false)
        .always_on_top(true)
        .fullscreen(true)
        .theme(chosen_theme(&app))
        .build()
        .and_then(|window| bring_forward(&window))
        .map_err(|error| error.to_string())
}

/// The first run's two shapes: the veil over the whole screen for the opening and the name, and the
/// ordinary 1000 by 660 window for the steps. Wayland fullscreens on the output the compositor picks,
/// which on GNOME and KDE is the one with the pointer or focus.
#[tauri::command]
pub fn onboarding_veil(window: WebviewWindow, on: bool) -> Result<(), String> {
    let shape = || -> tauri::Result<()> {
        if on {
            window.set_decorations(false)?;
            window.set_always_on_top(true)?;
            window.set_fullscreen(true)?;
        } else {
            window.set_fullscreen(false)?;
            window.set_always_on_top(false)?;
            window.set_decorations(true)?;
            window.set_size(tauri::LogicalSize::new(
                ONBOARDING_SIZE.0,
                ONBOARDING_SIZE.1,
            ))?;
            window.center()?;
        }
        window.set_focus()
    };
    shape().map_err(|error| error.to_string())
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
    fn only_the_memnox_window_and_its_inspectors_draw_destinations() {
        assert!(is_memnox_window("settings"));
        assert!(is_memnox_window("inspector-3"));
        assert!(!is_memnox_window("island"));
        assert!(!is_memnox_window("onboarding"));
    }

    #[test]
    fn system_leaves_the_frame_to_the_computer() {
        assert_eq!(theme_of("light"), Some(Theme::Light));
        assert_eq!(theme_of("dark"), Some(Theme::Dark));
        assert_eq!(theme_of("system"), None);
        assert_eq!(theme_of("anything"), None);
    }
}
