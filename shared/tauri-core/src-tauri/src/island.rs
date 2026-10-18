//! The island's window as the Mac's `IslandPanel` keeps it: pinned to the top centre of the screen, flush
//! with its top edge, and letting every click through except where the island, the pills under it and the
//! round buttons beside it are. The webview says where those are; this follows the pointer and decides.

use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use tauri::{Emitter, PhysicalPosition, WebviewWindow};

/// Sixty times a second, as the Mac polls, so the island takes a click the moment the pointer is over it.
const FOLLOW_EVERY: Duration = Duration::from_millis(16);

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
}

/// Where the island takes clicks right now, replaced whole each time the webview lays itself out.
#[derive(Default)]
pub struct HitAreas(Mutex<Vec<HitArea>>);

/// Told to the webview when the pointer reaches or leaves the island, since it hears no pointer while
/// the window lets clicks through and so never hears it leave.
#[derive(Clone, Serialize)]
struct Pointer {
    over: bool,
}

#[tauri::command]
pub fn island_hit_areas(areas: Vec<HitArea>, held: tauri::State<'_, Arc<HitAreas>>) {
    if let Ok(mut kept) = held.0.lock() {
        *kept = areas;
    }
}

/// Puts the window at the top centre of the screen it is on, flush with the top. A layer shell on Linux
/// anchors it to the top already and ignores this.
pub fn place(window: &WebviewWindow) {
    let monitor = window
        .current_monitor()
        .ok()
        .flatten()
        .or_else(|| window.primary_monitor().ok().flatten());
    let (Some(monitor), Ok(size)) = (monitor, window.outer_size()) else {
        return;
    };
    let origin = monitor.position();
    let x = origin.x + (monitor.size().width as i32 - size.width as i32) / 2;
    let _ = window.set_position(PhysicalPosition::new(x, origin.y));
}

/// Follows the pointer on its own thread and lets clicks through wherever the island is not. Where the
/// system cannot say where the pointer is, as on some Wayland compositors, the window keeps every click
/// rather than lose the island's.
pub fn follow(window: WebviewWindow, areas: Arc<HitAreas>) {
    std::thread::spawn(move || {
        let mut over: Option<bool> = None;
        loop {
            std::thread::sleep(FOLLOW_EVERY);
            let now = pointer_over(&window, &areas).unwrap_or(true);
            if over == Some(now) {
                continue;
            }
            over = Some(now);
            if window.set_ignore_cursor_events(!now).is_err() {
                // The window is gone, so there is nothing left to follow.
                return;
            }
            let _ = window.emit_to(window.label(), "island-pointer", Pointer { over: now });
        }
    });
}

/// Whether the pointer is over a place the island takes clicks, or None when it cannot be told.
fn pointer_over(window: &WebviewWindow, areas: &HitAreas) -> Option<bool> {
    let pointer = window.cursor_position().ok()?;
    let origin = window.outer_position().ok()?;
    let scale = window.scale_factor().ok()?;
    let x = (pointer.x - f64::from(origin.x)) / scale;
    let y = (pointer.y - f64::from(origin.y)) / scale;
    let held = areas.0.lock().ok()?;
    Some(held.iter().any(|area| area.holds(x, y)))
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
}
