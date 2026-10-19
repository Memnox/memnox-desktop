//! The tray: Memnox's own panel beside the icon, as the Mac's menu bar panel, and a native menu with the
//! same rows for a right click, and for Linux desktops whose tray only ever shows a menu. Starting at sign
//! in is on unless the person turns it off, since a held call that arrives with Memnox closed waits unseen.
//!
//! On Linux the icon is a StatusNotifierItem, since appindicator never tells the app of a left click; the
//! Tauri tray stands in only where no StatusNotifierItem host runs.
//!
//! The panel asks; the island does. Every row but Quit is sent to the island as `menu-action`, so talking,
//! a rule, mute, Settings and copying what happened each stay with whoever owns them.

use tauri::menu::{CheckMenuItem, IsMenuItem, Menu, MenuItem, PredefinedMenuItem};
use tauri::tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent};
use tauri::{
    App, AppHandle, Emitter, Manager, PhysicalPosition, PhysicalSize, WebviewUrl, WebviewWindow,
    WebviewWindowBuilder, WindowEvent, Wry,
};
use tauri_plugin_autostart::ManagerExt;

/// The panel's window, as the capability names it.
pub(crate) const PANEL: &str = "tray";
/// Told to the island for each row pressed, and to the panel each time it opens.
const MENU_ACTION: &str = "menu-action";
const MENU_OPENED: &str = "menu-opened";

const SHOW: &str = "show";
const PANEL_ITEM: &str = "panel";
const AT_SIGN_IN: &str = "at-sign-in";
const QUIT: &str = "quit";
/// The one row that keeps the panel open, so the change is seen.
const MUTE: &str = "mute";
/// The rows the island carries out, by the action it is told and the words on the native menu.
const ACTIONS: [(&str, &str); 6] = [
    ("talk", "Talk to Memnox"),
    ("rule", "Say a rule"),
    ("copy", "Copy what happened"),
    (MUTE, "Mute or unmute voice"),
    ("settings", "Settings"),
    ("tools", "Connected tools"),
];

/// The panel's first size, which its page changes to fit what it holds: 300 wide and a 12 margin each side.
const FIRST_SIZE: (f64, f64) = (324.0, 440.0);
/// How far from the icon, and how far inside the screen's work area, the panel stays.
const GAP: f64 = 6.0;
const INSET: f64 = 8.0;

pub fn build(app: &App) -> tauri::Result<()> {
    make_panel(app.handle())?;
    #[cfg(target_os = "linux")]
    if status_item(app.handle()) {
        return Ok(());
    }
    let starts = app.autolaunch().is_enabled().unwrap_or(false);
    let open = MenuItem::with_id(app, PANEL_ITEM, "Open Memnox", true, None::<&str>)?;
    let rows = ACTIONS
        .iter()
        .map(|(id, title)| MenuItem::with_id(app, *id, *title, true, None::<&str>))
        .collect::<tauri::Result<Vec<_>>>()?;
    let show = MenuItem::with_id(app, SHOW, "Show the island", true, None::<&str>)?;
    let at_sign_in = CheckMenuItem::with_id(
        app,
        AT_SIGN_IN,
        "Start when you sign in",
        true,
        starts,
        None::<&str>,
    )?;
    let quit = MenuItem::with_id(app, QUIT, "Quit Memnox", true, None::<&str>)?;
    let first = PredefinedMenuItem::separator(app)?;
    let second = PredefinedMenuItem::separator(app)?;
    let mut items: Vec<&dyn IsMenuItem<Wry>> = vec![&open, &first];
    for row in &rows {
        items.push(row);
    }
    items.extend([&second as &dyn IsMenuItem<Wry>, &show, &at_sign_in, &quit]);
    let menu = Menu::with_items(app, &items)?;
    let mut tray = TrayIconBuilder::with_id("memnox")
        .tooltip("Memnox")
        .menu(&menu)
        // A left click opens the panel, as the Mac's status item does; the menu waits for a right click.
        .show_menu_on_left_click(false);
    if let Some(icon) = app.default_window_icon() {
        tray = tray.icon(icon.clone());
    }
    tray.on_menu_event(move |app, event| match event.id().as_ref() {
        AT_SIGN_IN => {
            let _ = at_sign_in.set_checked(flip_at_sign_in(app));
        }
        row => pressed(app, row),
    })
    .on_tray_icon_event(|tray, event| {
        if let TrayIconEvent::Click {
            button: MouseButton::Left,
            button_state: MouseButtonState::Up,
            rect,
            ..
        } = event
        {
            let app = tray.app_handle();
            let scale = panel(app)
                .and_then(|window| window.scale_factor().ok())
                .unwrap_or(1.0);
            let at: PhysicalPosition<f64> = rect.position.to_physical(scale);
            let size: PhysicalSize<f64> = rect.size.to_physical(scale);
            toggle_panel(
                app,
                Some(Area {
                    x: at.x,
                    y: at.y,
                    width: size.width,
                    height: size.height,
                }),
            );
        }
    })
    .build(app)?;
    Ok(())
}

/// A row of either tray's menu, except starting at sign in, whose tick each tray keeps its own way.
fn pressed(app: &AppHandle, row: &str) {
    match row {
        SHOW => show_island(app),
        PANEL_ITEM => show_panel(app, None),
        QUIT => app.exit(0),
        action => tell_island(app, action),
    }
}

/// The icon in a StatusNotifierItem host, KDE Plasma's own tray or GNOME's AppIndicator extension; false
/// when none runs, so the caller puts up the Tauri tray instead.
#[cfg(target_os = "linux")]
fn status_item(app: &AppHandle) -> bool {
    use memnox_linux::{StatusItem, StatusPress, StatusRow};
    use std::sync::{Arc, OnceLock};

    let Some(icon) = app.default_window_icon() else {
        return false;
    };
    let row = |id: &str, title: &str| StatusRow::Press {
        id: id.into(),
        title: title.into(),
    };
    let mut rows = vec![row(PANEL_ITEM, "Open Memnox"), StatusRow::Separator];
    rows.extend(ACTIONS.iter().map(|(id, title)| row(id, title)));
    rows.extend([
        StatusRow::Separator,
        row(SHOW, "Show the island"),
        StatusRow::Tick {
            id: AT_SIGN_IN.into(),
            title: "Start when you sign in".into(),
        },
        row(QUIT, "Quit Memnox"),
    ]);
    let starts = app.autolaunch().is_enabled().unwrap_or(false);
    let item: Arc<OnceLock<StatusItem>> = Arc::default();
    let (told, kept) = (app.clone(), item.clone());
    let started = StatusItem::start(
        icon.rgba(),
        icon.width(),
        icon.height(),
        rows,
        starts,
        move |press| match press {
            // GNOME's extension often gives 0, 0, so the panel opens by the pointer instead.
            StatusPress::Open { x: 0, y: 0 } => toggle_panel(&told, None),
            StatusPress::Open { x, y } => toggle_panel(
                &told,
                Some(Area {
                    x: f64::from(x),
                    y: f64::from(y),
                    width: 1.0,
                    height: 1.0,
                }),
            ),
            StatusPress::Row(id) if id == AT_SIGN_IN => {
                let on = flip_at_sign_in(&told);
                let kept = kept.clone();
                // The tick is set from another thread, since this runs inside the item's own service.
                std::thread::spawn(move || {
                    if let Some(item) = kept.get() {
                        item.set_ticked(on);
                    }
                });
            }
            StatusPress::Row(id) => pressed(&told, &id),
        },
    );
    match started {
        Ok(started) => {
            let _ = item.set(started);
            app.manage(item);
            true
        }
        Err(why) => {
            eprintln!(
                "Memnox: no StatusNotifierItem host, so the tray falls back to appindicator: {why}"
            );
            false
        }
    }
}

/// The panel's window, made once and hidden: borderless, transparent, above the rest and out of the taskbar.
fn make_panel(app: &AppHandle) -> tauri::Result<()> {
    let window = WebviewWindowBuilder::new(app, PANEL, WebviewUrl::App("tray.html".into()))
        .title("Memnox")
        .inner_size(FIRST_SIZE.0, FIRST_SIZE.1)
        .decorations(false)
        .transparent(true)
        .resizable(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .shadow(false)
        .visible(false)
        .build()?;
    crate::glass::panel(&window);
    // A click anywhere else closes it, as the Mac's transient panel closes.
    let hide = window.clone();
    window.on_window_event(move |event| {
        if let WindowEvent::Focused(false) = event {
            let _ = hide.hide();
        }
    });
    Ok(())
}

fn panel(app: &AppHandle) -> Option<WebviewWindow> {
    app.get_webview_window(PANEL)
}

fn toggle_panel(app: &AppHandle, icon: Option<Area>) {
    match panel(app) {
        Some(window) if window.is_visible().unwrap_or(false) => {
            let _ = window.hide();
        }
        _ => show_panel(app, icon),
    }
}

/// Shows the panel beside the icon, or near the pointer when the tray gave no place, and tells it it opened.
fn show_panel(app: &AppHandle, icon: Option<Area>) {
    let Some(window) = panel(app) else { return };
    let icon = icon.or_else(|| {
        app.cursor_position().ok().map(|at| Area {
            x: at.x,
            y: at.y,
            width: 1.0,
            height: 1.0,
        })
    });
    if let Some(icon) = icon {
        let monitor = app
            .monitor_from_point(icon.x, icon.y)
            .ok()
            .flatten()
            .or_else(|| app.primary_monitor().ok().flatten());
        if let (Some(monitor), Ok(size)) = (monitor, window.outer_size()) {
            let work = monitor.work_area();
            let screen = Area {
                x: f64::from(work.position.x),
                y: f64::from(work.position.y),
                width: f64::from(work.size.width),
                height: f64::from(work.size.height),
            };
            let (x, y) = place(
                icon,
                screen,
                (f64::from(size.width), f64::from(size.height)),
                monitor.scale_factor(),
            );
            let _ = window.set_position(PhysicalPosition::new(x, y));
        }
    }
    let _ = window.show();
    let _ = window.set_focus();
    crate::glass::reshape_panel(&window);
    let _ = app.emit(MENU_OPENED, ());
}

/// A rectangle on screen in physical pixels.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Area {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}

/// Where the panel goes, as the core's `menuPanelPlace`: centred on the icon, 6 from it on the side away
/// from the nearer screen edge, clamped 8 inside the work area. Windows' tray is at the bottom, most Linux
/// trays at the top, so the panel opens up from one and down from the other.
fn place(icon: Area, screen: Area, size: (f64, f64), scale: f64) -> (i32, i32) {
    let (gap, inset) = (GAP * scale, INSET * scale);
    let below = icon.y + icon.height / 2.0 < screen.y + screen.height / 2.0;
    let x = icon.x + icon.width / 2.0 - size.0 / 2.0;
    let y = if below {
        icon.y + icon.height + gap
    } else {
        icon.y - gap - size.1
    };
    let clamp = |value: f64, low: f64, high: f64| value.min(high.max(low)).max(low);
    let x = clamp(
        x,
        screen.x + inset,
        screen.x + screen.width - inset - size.0,
    );
    let y = clamp(
        y,
        screen.y + inset,
        screen.y + screen.height - inset - size.1,
    );
    (x.round() as i32, y.round() as i32)
}

/// Sends a row to the island, which carries it out.
fn tell_island(app: &AppHandle, action: &str) {
    if ACTIONS.iter().any(|(id, _)| *id == action) {
        let _ = app.emit_to(crate::ISLAND, MENU_ACTION, action);
    }
}

/// A row pressed in the panel: Quit ends the app, mute keeps the panel open to show the change, and
/// every other row closes it and goes to the island.
#[tauri::command]
pub fn tray_action(app: AppHandle, action: String) -> Result<(), String> {
    if action == QUIT {
        app.exit(0);
        return Ok(());
    }
    if !ACTIONS.iter().any(|(id, _)| *id == action) {
        return Err(format!("no tray row does {action}"));
    }
    if action != MUTE {
        if let Some(window) = panel(&app) {
            let _ = window.hide();
        }
    }
    tell_island(&app, &action);
    Ok(())
}

/// Escape from the panel's page.
#[tauri::command]
pub fn tray_panel_hide(app: AppHandle) -> Result<(), String> {
    if let Some(window) = panel(&app) {
        window.hide().map_err(|error| error.to_string())?;
    }
    Ok(())
}

/// The panel's page fits the window to what it holds, keeping the edge nearest the icon where it was.
#[tauri::command]
pub fn tray_panel_fit(app: AppHandle, width: f64, height: f64) -> Result<(), String> {
    let Some(window) = panel(&app) else {
        return Ok(());
    };
    let scale = window.scale_factor().map_err(|error| error.to_string())?;
    let before = window.outer_size().map_err(|error| error.to_string())?;
    let at = window.outer_position().map_err(|error| error.to_string())?;
    let size = tauri::LogicalSize::new(width, height).to_physical::<u32>(scale);
    if size == before {
        return Ok(());
    }
    window.set_size(size).map_err(|error| error.to_string())?;
    crate::glass::reshape_panel(&window);
    // Opened upward from a tray at the bottom, its bottom edge stays by the icon as it grows.
    let opened_up = window
        .current_monitor()
        .ok()
        .flatten()
        .map(|monitor| {
            f64::from(at.y)
                > f64::from(monitor.position().y) + f64::from(monitor.size().height) / 2.0
        })
        .unwrap_or(false);
    if opened_up {
        let grown = i64::from(size.height) - i64::from(before.height);
        let lifted = i64::from(at.y) - grown;
        window
            .set_position(PhysicalPosition::new(
                at.x,
                i32::try_from(lifted).unwrap_or(at.y),
            ))
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

pub fn show_island(app: &AppHandle) {
    if let Some(window) = app.get_webview_window(crate::ISLAND) {
        let _ = window.show();
    }
}

/// Turns starting at sign in over, and says whether it is now on, for the row's tick.
fn flip_at_sign_in(app: &AppHandle) -> bool {
    let autolaunch = app.autolaunch();
    let on = !autolaunch.is_enabled().unwrap_or(false);
    let changed = if on {
        autolaunch.enable()
    } else {
        autolaunch.disable()
    };
    changed.is_ok() == on
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

#[cfg(test)]
mod tests {
    use super::{place, Area};

    const SIZE: (f64, f64) = (300.0, 400.0);

    fn area(x: f64, y: f64, width: f64, height: f64) -> Area {
        Area {
            x,
            y,
            width,
            height,
        }
    }

    #[test]
    fn opens_above_a_tray_at_the_bottom() {
        let screen = area(0.0, 0.0, 1920.0, 1080.0);
        assert_eq!(
            place(area(1800.0, 1050.0, 24.0, 24.0), screen, SIZE, 1.0),
            (1612, 644)
        );
    }

    #[test]
    fn opens_below_a_tray_at_the_top() {
        let screen = area(0.0, 0.0, 1920.0, 1040.0);
        assert_eq!(
            place(area(900.0, 4.0, 24.0, 24.0), screen, SIZE, 1.0),
            (762, 34)
        );
    }

    #[test]
    fn stays_inside_the_screen_and_scales_its_margins() {
        let screen = area(0.0, 0.0, 1920.0, 1040.0);
        assert_eq!(place(area(2.0, 4.0, 24.0, 24.0), screen, SIZE, 2.0).0, 16);
    }
}
