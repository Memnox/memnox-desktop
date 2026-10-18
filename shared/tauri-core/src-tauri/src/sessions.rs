//! The session windows beside the island, as the Mac's `LiveSession`, `SidePanel`, `SwitcherPanel` and
//! `CardWall` keep them: each a borderless window drawn by `sessions.html`, made the first time it is
//! asked for and brought forward after that, so there is only ever one of each.

use tauri::{
    AppHandle, Emitter, LogicalPosition, LogicalSize, Manager, Monitor, WebviewUrl, WebviewWindow,
    WebviewWindowBuilder,
};

/// The live window on one session, by the label the capability names.
pub const LIVE: &str = "live";
/// The history and what is working, flush on the left edge.
pub const SIDE: &str = "side";
/// The shelf of sessions turning to the one asked for, over the whole screen.
pub const SWITCHER: &str = "switcher";
/// Every session lately as its own card, together.
pub const BOARD: &str = "board";

/// Told to an open live window when another session is asked for.
const LIVE_SESSION: &str = "live-session";

/// The Mac's live window: 620 wide, as tall as the screen allows up to 820, and never smaller than 420.
const LIVE_WIDTH: f64 = 620.0;
const LIVE_TALLEST: f64 = 820.0;
const LIVE_MIN: f64 = 420.0;
/// Room left above and below the live window, so it never meets the screen's edges.
const LIVE_MARGIN: f64 = 40.0;
/// The side panel: 330 wide, as tall as the screen allows up to 700.
const SIDE_WIDTH: f64 = 330.0;
const SIDE_TALLEST: f64 = 700.0;
const SIDE_MARGIN: f64 = 20.0;
/// Two columns of 440 cards with their 16 gap and the 40 margin either side for their shadows.
const BOARD_WIDTH: f64 = 2.0 * 440.0 + 16.0 + 2.0 * 40.0;

/// Opens the live window on a session, or turns the open one to it.
#[tauri::command]
pub fn open_live_session(app: AppHandle, session_id: String) -> Result<(), String> {
    if let Some(window) = app.get_webview_window(LIVE) {
        window
            .emit(LIVE_SESSION, &session_id)
            .map_err(|error| error.to_string())?;
        return bring_forward(&window).map_err(|error| error.to_string());
    }
    let screen = screen_of(&app);
    let height = LIVE_TALLEST.min(screen.height - LIVE_MARGIN).max(LIVE_MIN);
    let url = format!("sessions.html?view=live&session={}", encoded(&session_id));
    WebviewWindowBuilder::new(&app, LIVE, WebviewUrl::App(url.into()))
        .title("Memnox")
        .inner_size(LIVE_WIDTH, height)
        .min_inner_size(LIVE_MIN, LIVE_MIN)
        .position(
            screen.x + (screen.width - LIVE_WIDTH) / 2.0,
            screen.y + (screen.height - height) / 2.0,
        )
        .decorations(false)
        .transparent(true)
        .always_on_top(true)
        .skip_taskbar(true)
        .shadow(true)
        .build()
        .and_then(|window| bring_forward(&window))
        .map_err(|error| error.to_string())
}

/// Opens the side panel on the left edge, vertically centred, or closes it when it is up and `open` is false.
#[tauri::command]
pub fn open_side(app: AppHandle, open: bool) -> Result<(), String> {
    let existing = app.get_webview_window(SIDE);
    if !open {
        if let Some(window) = existing {
            window.close().map_err(|error| error.to_string())?;
        }
        return Ok(());
    }
    if let Some(window) = existing {
        return bring_forward(&window).map_err(|error| error.to_string());
    }
    let screen = screen_of(&app);
    let height = SIDE_TALLEST.min(screen.height - SIDE_MARGIN);
    WebviewWindowBuilder::new(&app, SIDE, WebviewUrl::App("sessions.html?view=side".into()))
        .title("Memnox")
        .inner_size(SIDE_WIDTH, height)
        .position(screen.x, screen.y + (screen.height - height) / 2.0)
        .resizable(false)
        .decorations(false)
        .transparent(true)
        .always_on_top(true)
        .skip_taskbar(true)
        .shadow(false)
        .build()
        .and_then(|window| bring_forward(&window))
        .map_err(|error| error.to_string())
}

/// Turns the shelf of sessions to the one asked for over the whole screen; it opens that session's live window as it goes.
#[tauri::command]
pub fn open_switcher(app: AppHandle, session_id: String) -> Result<(), String> {
    if let Some(window) = app.get_webview_window(SWITCHER) {
        window.close().map_err(|error| error.to_string())?;
    }
    let screen = screen_of(&app);
    let url = format!(
        "sessions.html?view=switcher&session={}",
        encoded(&session_id)
    );
    WebviewWindowBuilder::new(&app, SWITCHER, WebviewUrl::App(url.into()))
        .title("Memnox")
        .inner_size(screen.width, screen.height)
        .position(screen.x, screen.y)
        .resizable(false)
        .decorations(false)
        .transparent(true)
        .always_on_top(true)
        .skip_taskbar(true)
        .shadow(false)
        .focused(false)
        .build()
        .map(|_| ())
        .map_err(|error| error.to_string())
}

/// Puts every session up as its own card in the top left of the screen.
#[tauri::command]
pub fn open_board(app: AppHandle, title: String) -> Result<(), String> {
    if let Some(window) = app.get_webview_window(BOARD) {
        window.close().map_err(|error| error.to_string())?;
    }
    let screen = screen_of(&app);
    let url = format!("sessions.html?view=board&title={}", encoded(&title));
    WebviewWindowBuilder::new(&app, BOARD, WebviewUrl::App(url.into()))
        .title("Memnox")
        .inner_size(BOARD_WIDTH.min(screen.width), screen.height)
        .position(screen.x, screen.y)
        .resizable(false)
        .decorations(false)
        .transparent(true)
        .always_on_top(true)
        .skip_taskbar(true)
        .shadow(false)
        .build()
        .and_then(|window| bring_forward(&window))
        .map_err(|error| error.to_string())
}

/// Takes every session window off the screen, as the daemon's dismiss does; no session is touched.
#[tauri::command]
pub fn dismiss_session_windows(app: AppHandle) {
    for label in [LIVE, SIDE, SWITCHER, BOARD] {
        if let Some(window) = app.get_webview_window(label) {
            let _ = window.close();
        }
    }
}

/// Closes the session window that asked, for its close button and Escape.
#[tauri::command]
pub fn close_session_window(window: WebviewWindow) -> Result<(), String> {
    window.close().map_err(|error| error.to_string())
}

/// Opens a folder the person named in the system's file manager; only a folder that is there is opened.
#[tauri::command]
pub fn open_folder(path: String) -> Result<(), String> {
    if !std::path::Path::new(&path).is_dir() {
        return Err(format!("{path} is not a folder"));
    }
    opener(if cfg!(windows) { "explorer" } else { "xdg-open" }, &path)
}

/// Opens a web page in the person's own browser; only http and https are opened, so a link never starts an app.
#[tauri::command]
pub fn open_link(url: String) -> Result<(), String> {
    if !is_web_link(&url) {
        return Err("only a web page is opened".to_owned());
    }
    if cfg!(windows) {
        // rundll32 takes the link whole, where cmd's start would read an ampersand in it as a second command.
        return std::process::Command::new("rundll32")
            .args(["url.dll,FileProtocolHandler", &url])
            .spawn()
            .map(|_| ())
            .map_err(|error| error.to_string());
    }
    opener("xdg-open", &url)
}

fn opener(program: &str, target: &str) -> Result<(), String> {
    std::process::Command::new(program)
        .arg(target)
        .spawn()
        .map(|_| ())
        .map_err(|error| error.to_string())
}

/// An http or https address with a host and no name or password in it.
fn is_web_link(url: &str) -> bool {
    let Some((scheme, rest)) = url.split_once("://") else {
        return false;
    };
    let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
    matches!(scheme.to_ascii_lowercase().as_str(), "http" | "https")
        && !authority.is_empty()
        && !authority.contains('@')
        && !url.chars().any(char::is_whitespace)
}

/// A query value with everything but letters, digits and `-_.~` written as `%XX`.
fn encoded(value: &str) -> String {
    value
        .bytes()
        .map(|byte| match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                (byte as char).to_string()
            }
            _ => format!("%{byte:02X}"),
        })
        .collect()
}

/// The screen the island is on, in logical points, so the windows open beside it.
struct Screen {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}

fn screen_of(app: &AppHandle) -> Screen {
    let monitor: Option<Monitor> = app
        .get_webview_window(crate::ISLAND)
        .and_then(|window| window.current_monitor().ok().flatten())
        .or_else(|| app.primary_monitor().ok().flatten());
    match monitor {
        Some(monitor) => {
            let scale = monitor.scale_factor();
            let position: LogicalPosition<f64> = monitor.position().to_logical(scale);
            let size: LogicalSize<f64> = monitor.size().to_logical(scale);
            Screen {
                x: position.x,
                y: position.y,
                width: size.width,
                height: size.height,
            }
        }
        // Somewhere sensible when no screen answers, as on a headless start.
        None => Screen {
            x: 0.0,
            y: 0.0,
            width: 1280.0,
            height: 800.0,
        },
    }
}

fn bring_forward(window: &WebviewWindow) -> tauri::Result<()> {
    window.unminimize()?;
    window.show()?;
    window.set_focus()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_a_web_page_is_opened() {
        assert!(is_web_link("https://memnox.com/docs?a=1&b=2"));
        assert!(is_web_link("http://localhost:3000"));
        assert!(!is_web_link("file:///etc/passwd"));
        assert!(!is_web_link("https://user:secret@example.com"));
        assert!(!is_web_link("javascript:alert(1)"));
        assert!(!is_web_link("https://"));
    }

    #[test]
    fn a_query_value_is_written_safely() {
        assert_eq!(encoded("ses_1-a.b~c"), "ses_1-a.b~c");
        assert_eq!(encoded("Your sessions & more"), "Your%20sessions%20%26%20more");
    }
}
