//! The windows that float beside the island: the summary, walk and trace cards in the top left of the
//! screen, as the Mac's `CardPanel`, and the scan over the whole screen, as its `ScanPanel`. Each is made
//! the first time it is asked for and hidden after, and its page draws whatever the island sends it.

use tauri::{
    AppHandle, Manager, PhysicalPosition, PhysicalSize, WebviewUrl, WebviewWindow,
    WebviewWindowBuilder,
};

/// The windows, as the capability names them.
pub(crate) const CARDS: &str = "cards";
pub(crate) const SCAN: &str = "scan";

/// The card is 440 wide, 20 in from the top left of the work area, drawn inside a 40 margin for its shadow.
const CARD_WIDTH: f64 = 440.0;
const CARD_INSET: f64 = 20.0;
const CARD_MARGIN: f64 = 40.0;
const CARD_FIRST_HEIGHT: f64 = 600.0;

fn made(
    app: &AppHandle,
    label: &str,
    page: &str,
    size: (f64, f64),
    focused: bool,
) -> tauri::Result<WebviewWindow> {
    if let Some(window) = app.get_webview_window(label) {
        return Ok(window);
    }
    WebviewWindowBuilder::new(app, label, WebviewUrl::App(page.into()))
        .title("Memnox")
        .inner_size(size.0, size.1)
        .decorations(false)
        .transparent(true)
        .resizable(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .shadow(false)
        .focused(focused)
        .visible(false)
        .build()
}

/// The monitor the pointer is on, else the main one, so a card or the scan opens where the person looks.
fn screen(app: &AppHandle) -> Option<tauri::Monitor> {
    app.cursor_position()
        .ok()
        .and_then(|at| app.monitor_from_point(at.x, at.y).ok().flatten())
        .or_else(|| app.primary_monitor().ok().flatten())
}

/// The card panel, shown in the top left of the screen the pointer is on, without taking the keyboard.
#[tauri::command]
pub fn cards_show(app: AppHandle) -> Result<(), String> {
    let window = made(
        &app,
        CARDS,
        "cards.html",
        (CARD_WIDTH + 2.0 * CARD_MARGIN, CARD_FIRST_HEIGHT),
        false,
    )
    .map_err(|error| error.to_string())?;
    if let Some(monitor) = screen(&app) {
        let work = monitor.work_area();
        let scale = monitor.scale_factor();
        let offset = ((CARD_INSET - CARD_MARGIN) * scale).round() as i32;
        window
            .set_position(PhysicalPosition::new(
                work.position.x + offset,
                work.position.y + offset,
            ))
            .map_err(|error| error.to_string())?;
    }
    window.show().map_err(|error| error.to_string())
}

#[tauri::command]
pub fn cards_hide(app: AppHandle) -> Result<(), String> {
    if let Some(window) = app.get_webview_window(CARDS) {
        window.hide().map_err(|error| error.to_string())?;
    }
    Ok(())
}

/// The card's page fits the window to the card, so nothing outside it catches a click.
#[tauri::command]
pub fn cards_fit(app: AppHandle, height: f64) -> Result<(), String> {
    let Some(window) = app.get_webview_window(CARDS) else {
        return Ok(());
    };
    window
        .set_size(tauri::LogicalSize::new(
            CARD_WIDTH + 2.0 * CARD_MARGIN,
            height.max(1.0),
        ))
        .map_err(|error| error.to_string())
}

/// The scan over the whole of the screen the pointer is on, taking the keyboard so Escape closes it.
#[tauri::command]
pub fn scan_show(app: AppHandle) -> Result<(), String> {
    let window =
        made(&app, SCAN, "scan.html", (1280.0, 800.0), true).map_err(|error| error.to_string())?;
    if let Some(monitor) = screen(&app) {
        let at = monitor.position();
        let size = monitor.size();
        window
            .set_position(PhysicalPosition::new(at.x, at.y))
            .map_err(|error| error.to_string())?;
        window
            .set_size(PhysicalSize::new(size.width, size.height))
            .map_err(|error| error.to_string())?;
    }
    window.show().map_err(|error| error.to_string())?;
    window.set_focus().map_err(|error| error.to_string())
}

#[tauri::command]
pub fn scan_hide(app: AppHandle) -> Result<(), String> {
    if let Some(window) = app.get_webview_window(SCAN) {
        window.hide().map_err(|error| error.to_string())?;
    }
    Ok(())
}
