//! The island's window as the Mac's `IslandPanel` keeps it: pinned to the top centre of the display the
//! person chose, flush with its top edge, and letting every click through except where the island, the
//! pills under it and the round buttons beside it are. The webview says where those are. On Windows and
//! macOS this follows the pointer and decides; on Linux the boxes become the window's input region, so
//! the compositor routes the clicks itself, which is the one way that works on Wayland. The side panel
//! and the card wall are followed the same way.

mod pointer;
pub mod screens;

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, PhysicalPosition, WebviewWindow};

pub use screens::IslandScreens;

/// Sixty times a second, as the Mac polls, so the island takes a click the moment the pointer is over it.
const FOLLOW_EVERY: Duration = Duration::from_millis(16);
/// Told to a followed window when the pointer reaches or leaves what it draws.
const POINTER_EVENT: &str = "island-pointer";
/// Told to a followed window when a press lands outside every window of this app, as the Mac's global
/// click monitor hears one, so the island puts itself away and the side panel folds.
const OUTSIDE_EVENT: &str = "island-outside";

/// A box in the window's own CSS pixels, as the webview lays itself out.
#[derive(Clone, Copy, Debug, Deserialize, PartialEq)]
pub struct HitArea {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}

impl HitArea {
    fn holds(&self, x: f64, y: f64) -> bool {
        x >= self.x && x <= self.x + self.width && y >= self.y && y <= self.y + self.height
    }

    /// The box grown out to whole pixels, so a fraction never leaves a sliver that drops a click.
    #[cfg_attr(not(target_os = "linux"), allow(dead_code))]
    fn whole(&self) -> (i32, i32, i32, i32) {
        let left = self.x.floor();
        let top = self.y.floor();
        let right = (self.x + self.width).ceil();
        let bottom = (self.y + self.height).ceil();
        (
            left as i32,
            top as i32,
            (right - left) as i32,
            (bottom - top) as i32,
        )
    }
}

/// What one followed window takes clicks on, and whether it is resting, which only the island says.
#[derive(Clone, Default)]
struct Taken {
    areas: Vec<HitArea>,
    resting: bool,
}

/// Where each followed window takes clicks right now, by its label, each replaced whole when its webview
/// lays itself out.
#[derive(Default)]
pub struct HitAreas(Mutex<HashMap<String, Taken>>);

impl HitAreas {
    fn of(&self, label: &str) -> Option<Taken> {
        self.0.lock().ok()?.get(label).cloned()
    }

    /// Whether the island rests beside the notch, so following the pointer may move it.
    pub fn resting(&self, label: &str) -> bool {
        self.of(label).is_none_or(|taken| taken.resting)
    }
}

/// Told to the webview when the pointer reaches or leaves the island, since it hears no pointer while
/// the window lets clicks through and so never hears it leave.
#[derive(Clone, Serialize)]
struct Pointer {
    over: bool,
}

/// Where the window that asked takes clicks, and for the island whether it rests closed beside the notch.
#[tauri::command]
pub fn island_hit_areas(
    window: WebviewWindow,
    areas: Vec<HitArea>,
    resting: Option<bool>,
    held: tauri::State<'_, Arc<HitAreas>>,
) {
    if let Ok(mut kept) = held.0.lock() {
        let taken = kept.entry(window.label().to_owned()).or_default();
        taken.areas.clone_from(&areas);
        if let Some(resting) = resting {
            taken.resting = resting;
        }
    }
    #[cfg(target_os = "linux")]
    input_region(&window, &areas);
}

/// The boxes as the window's input region, set on GTK's own thread.
#[cfg(target_os = "linux")]
fn input_region(window: &WebviewWindow, areas: &[HitArea]) {
    let boxes: Vec<(i32, i32, i32, i32)> = areas.iter().map(HitArea::whole).collect();
    let target = window.clone();
    let _ = window.run_on_main_thread(move || {
        if let Ok(gtk) = target.gtk_window() {
            memnox_linux::set_input_region(&gtk, &boxes);
        }
    });
}

/// Puts the window at the top centre of the display the person chose, flush with the top. A layer
/// shell on Linux anchors it to the top already and is told the output instead.
pub fn place(window: &WebviewWindow) {
    screens::place(window);
}

/// Follows the pointer on its own thread for one window of this app: lets clicks through wherever it
/// draws nothing, tells it when the pointer leaves, and tells it of a press outside every window here.
pub fn follow(window: WebviewWindow, areas: Arc<HitAreas>) {
    // On Linux nothing is taken until the webview says where it draws, rather than the whole window.
    #[cfg(target_os = "linux")]
    input_region(&window, &[]);
    std::thread::spawn(move || {
        let Some(mut reader) = pointer::Reader::open() else {
            // Wayland gives no app the pointer; the input region alone lets clicks through there.
            return;
        };
        let mut over: Option<bool> = None;
        let mut was_pressed = false;
        loop {
            std::thread::sleep(FOLLOW_EVERY);
            if window.outer_position().is_err() {
                // The window is gone, so there is nothing left to follow.
                return;
            }
            let reading = reader.read(&window);
            let Some(at) = reading.at else { continue };
            // Where the read fails the window keeps every click rather than lose the island's.
            let now = over_areas(&window, &areas, at).unwrap_or(true);
            if over != Some(now) {
                over = Some(now);
                if !cfg!(target_os = "linux") && window.set_ignore_cursor_events(!now).is_err() {
                    return;
                }
                let _ = window.emit_to(window.label(), POINTER_EVENT, Pointer { over: now });
            }
            if reading.pressed && !was_pressed && !now && !over_any_other(&window, &areas, at) {
                let _ = window.emit_to(window.label(), OUTSIDE_EVENT, ());
            }
            was_pressed = reading.pressed;
        }
    });
}

/// Whether a point on the screen, in physical pixels, is over a place this window takes clicks, or None
/// when it cannot be told.
fn over_areas(window: &WebviewWindow, areas: &HitAreas, at: PhysicalPosition<f64>) -> Option<bool> {
    let origin = window.outer_position().ok()?;
    let scale = window.scale_factor().ok()?;
    let x = (at.x - f64::from(origin.x)) / scale;
    let y = (at.y - f64::from(origin.y)) / scale;
    let taken = areas.of(window.label())?;
    Some(taken.areas.iter().any(|area| area.holds(x, y)))
}

/// Whether the point is over another window of this app, so a press in the live window or Settings is
/// never taken for one elsewhere, as a global monitor on the Mac never hears its own app's clicks.
fn over_any_other(window: &WebviewWindow, areas: &HitAreas, at: PhysicalPosition<f64>) -> bool {
    window
        .app_handle()
        .webview_windows()
        .into_values()
        .filter(|other| other.label() != window.label() && other.is_visible().unwrap_or(false))
        .any(|other| match over_areas(&other, areas, at) {
            Some(over) => over,
            None => over_frame(&other, at),
        })
}

fn over_frame(window: &WebviewWindow, at: PhysicalPosition<f64>) -> bool {
    let (Ok(origin), Ok(size)) = (window.outer_position(), window.outer_size()) else {
        return false;
    };
    at.x >= f64::from(origin.x)
        && at.y >= f64::from(origin.y)
        && at.x <= f64::from(origin.x) + f64::from(size.width)
        && at.y <= f64::from(origin.y) + f64::from(size.height)
}

/// Lets a window of this app take the keyboard, for the island's question, held call and draft, and the
/// side panel's search, and gives it back to where the person was typing when it is done.
pub fn keyboard(window: &WebviewWindow, on: bool) -> Result<(), String> {
    #[cfg(windows)]
    if let Ok(hwnd) = window.hwnd() {
        let hwnd = hwnd.0 as isize;
        if on {
            pointer::remember_foreground(hwnd);
        }
        memnox_windows::island_keyboard(hwnd, on);
        if !on {
            pointer::give_back_foreground(hwnd);
        }
    }
    #[cfg(target_os = "linux")]
    {
        if on {
            pointer::remember_foreground(0);
        }
        let target = window.clone();
        window
            .run_on_main_thread(move || {
                if let Ok(gtk) = target.gtk_window() {
                    memnox_linux::island_keyboard(&gtk, on);
                }
            })
            .map_err(|error| error.to_string())?;
        if !on {
            pointer::give_back_foreground(0);
        }
    }
    if on {
        window.set_focus().map_err(|error| error.to_string())?;
    }
    Ok(())
}

/// Starts following the island's display choice: the pointer while it rests, and screens coming and going.
pub fn watch_screens(app: &AppHandle) {
    screens::watch(app.clone());
}

#[cfg(test)]
mod tests {
    use super::HitArea;

    #[test]
    fn holds_a_point_inside_its_box_and_on_its_edge_only() {
        let area = HitArea {
            x: 10.0,
            y: 0.0,
            width: 100.0,
            height: 30.0,
        };
        assert!(area.holds(10.0, 0.0));
        assert!(area.holds(110.0, 30.0));
        assert!(!area.holds(9.0, 10.0));
        assert!(!area.holds(50.0, 31.0));
    }

    #[test]
    fn grows_a_box_out_to_whole_pixels() {
        let area = HitArea {
            x: 10.4,
            y: 0.0,
            width: 100.2,
            height: 30.5,
        };
        assert_eq!(area.whole(), (10, 0, 101, 31));
    }
}
