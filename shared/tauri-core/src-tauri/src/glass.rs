//! Glass behind the tray panel, where the Mac draws its menu panel on `regularMaterial`. Windows 11 lays
//! the acrylic backdrop under the whole window, with the system's rounded corners and shadow, so the page
//! draws the panel edge to edge. KDE blurs under the panel's rounded shape inside the window's margin.
//! GNOME and Windows 10 give no blur, so there the page keeps its near solid wash.

use std::collections::HashMap;
use std::sync::Mutex;

use serde::Serialize;
use tauri::{Manager, WebviewWindow};

/// What a window got behind it, which its page asks so it drops the solid wash only when glass is there.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
#[cfg_attr(not(any(windows, target_os = "linux")), allow(dead_code))]
pub enum Glass {
    /// Nothing: the page keeps its near solid wash.
    None,
    /// The whole window is the glass, with the system's corners and shadow, so the page needs no margin.
    Backdrop,
    /// The compositor blurs under the panel's shape, inside the margin the page keeps for its shadow.
    Blur,
}

/// The glass each window got, by its label.
#[derive(Default)]
pub struct Glassed(Mutex<HashMap<String, Glass>>);

/// The tray panel's shape inside its window: the 12 margin the page keeps and the Mac's 22 radius.
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
const PANEL_MARGIN: f64 = 12.0;
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
const PANEL_RADIUS: f64 = 22.0;

/// Lays glass behind the tray panel where this system offers it, once, and remembers what it got.
pub fn panel(window: &WebviewWindow) -> Glass {
    let glass = panel_glass(window);
    if let Some(glassed) = window.try_state::<Glassed>() {
        if let Ok(mut kept) = glassed.0.lock() {
            kept.insert(window.label().to_owned(), glass);
        }
    }
    glass
}

#[cfg(windows)]
fn panel_glass(window: &WebviewWindow) -> Glass {
    if !memnox_windows::is_windows_11() {
        return Glass::None;
    }
    // The transient window backdrop, the acrylic Windows 11 gives its own menus and flyouts.
    if window_vibrancy::apply_acrylic(window, None).is_err() {
        return Glass::None;
    }
    let _ = window.set_shadow(true);
    if let Ok(hwnd) = window.hwnd() {
        memnox_windows::round_corners(hwnd.0 as isize);
    }
    Glass::Backdrop
}

#[cfg(target_os = "linux")]
fn panel_glass(_: &WebviewWindow) -> Glass {
    // The blur itself is asked each time the panel shows, since a hidden Wayland window loses its surface.
    if memnox_linux::blur_offered() {
        Glass::Blur
    } else {
        Glass::None
    }
}

#[cfg(not(any(windows, target_os = "linux")))]
fn panel_glass(_: &WebviewWindow) -> Glass {
    Glass::None
}

/// Asks KDE again to blur under the panel's shape, after it is shown or resized; nothing elsewhere.
#[cfg_attr(not(target_os = "linux"), allow(unused_variables))]
pub fn reshape_panel(window: &WebviewWindow) {
    #[cfg(target_os = "linux")]
    {
        if glass_of(window) != Glass::Blur {
            return;
        }
        let Ok(size) = window.inner_size() else {
            return;
        };
        let scale = window.scale_factor().unwrap_or(1.0);
        let size = size.to_logical::<f64>(scale);
        let shape = memnox_linux::Rounded {
            x: PANEL_MARGIN as i32,
            y: PANEL_MARGIN as i32,
            width: (size.width - 2.0 * PANEL_MARGIN).round() as i32,
            height: (size.height - 2.0 * PANEL_MARGIN).round() as i32,
            radius: PANEL_RADIUS as i32,
        };
        let panel = window.clone();
        let _ = window.run_on_main_thread(move || {
            if let Ok(gtk) = panel.gtk_window() {
                memnox_linux::blur_behind(&gtk, shape);
            }
        });
    }
}

fn glass_of(window: &WebviewWindow) -> Glass {
    window
        .try_state::<Glassed>()
        .and_then(|glassed| glassed.0.lock().ok()?.get(window.label()).copied())
        .unwrap_or(Glass::None)
}

/// What the asking window got behind it, so its page keeps the solid wash unless glass is there.
#[tauri::command]
pub fn glass_applied(window: WebviewWindow) -> Glass {
    glass_of(&window)
}
