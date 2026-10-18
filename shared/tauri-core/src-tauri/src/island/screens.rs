//! Which display the island hangs from, ported from the Mac's `IslandScreen` and `IslandScreens`: the
//! main display (Windows and Linux have no notch, so the notch choice means the primary display), the one
//! holding the pointer, or one display by name. The choice is kept in a file beside the voice's, so the
//! Settings window and the island read one copy of it.

use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde::Serialize;
use tauri::{AppHandle, Manager, Monitor, PhysicalPosition, WebviewWindow};

use super::HitAreas;

/// Often enough that the island is on the new screen before the pointer has settled there.
const LOOK_EVERY: Duration = Duration::from_millis(250);

const NOTCH: &str = "notch";
const POINTER: &str = "pointer";
const DISPLAY_PREFIX: &str = "display:";

/// The person's choice, as the Mac's `IslandScreen`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Choice {
    Notch,
    Pointer,
    Display(String),
}

impl Choice {
    /// The saved choice, or the main display when nothing or something unknown was saved.
    pub fn parse(stored: &str) -> Self {
        match stored.trim() {
            POINTER => Self::Pointer,
            value if value.len() > DISPLAY_PREFIX.len() && value.starts_with(DISPLAY_PREFIX) => {
                Self::Display(value[DISPLAY_PREFIX.len()..].to_owned())
            }
            _ => Self::Notch,
        }
    }

    pub fn stored(&self) -> String {
        match self {
            Self::Notch => NOTCH.to_owned(),
            Self::Pointer => POINTER.to_owned(),
            Self::Display(id) => format!("{DISPLAY_PREFIX}{id}"),
        }
    }
}

/// What choosing a screen needs to know about one, in the order the system lists them.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Facts {
    pub id: String,
    pub primary: bool,
    pub holds_pointer: bool,
}

/// Which of `screens` the island goes on, as the Mac's `islandScreenIndex`: `staying_on` is the screen it
/// is on while open, so following the pointer waits until it closes, and a display that is gone hands it
/// back to the main one.
pub fn screen_index(choice: &Choice, screens: &[Facts], staying_on: Option<&str>) -> Option<usize> {
    if screens.is_empty() {
        return None;
    }
    let main = screens.iter().position(|screen| screen.primary).unwrap_or(0);
    Some(match choice {
        Choice::Notch => main,
        Choice::Pointer => staying_on
            .and_then(|here| screens.iter().position(|screen| screen.id == here))
            .or_else(|| screens.iter().position(|screen| screen.holds_pointer))
            .unwrap_or(main),
        Choice::Display(id) => screens.iter().position(|screen| &screen.id == id).unwrap_or(main),
    })
}

/// The choice and where it is kept, and the display the island was last put on.
pub struct IslandScreens {
    path: PathBuf,
    choice: Mutex<Choice>,
    current: Mutex<Option<String>>,
}

impl IslandScreens {
    pub fn load(path: PathBuf) -> Self {
        let stored = std::fs::read_to_string(&path).unwrap_or_default();
        Self {
            path,
            choice: Mutex::new(Choice::parse(&stored)),
            current: Mutex::new(None),
        }
    }

    fn choice(&self) -> Choice {
        self.choice.lock().map(|choice| choice.clone()).unwrap_or(Choice::Notch)
    }

    fn current(&self) -> Option<String> {
        self.current.lock().ok().and_then(|current| current.clone())
    }
}

/// A display as Settings lists it.
#[derive(Clone, Serialize)]
pub struct Display {
    id: String,
    name: String,
}

#[derive(Serialize)]
pub struct Listed {
    chosen: String,
    displays: Vec<Display>,
}

/// A display's name stays the same across restarts where its place in the list may not.
fn id_of(monitor: &Monitor, index: usize) -> String {
    monitor.name().cloned().unwrap_or_else(|| format!("{}", index + 1))
}

/// How Settings names a display: its number, its size, and which one is the main display.
fn name_of(monitor: &Monitor, index: usize, primary: bool) -> String {
    let size = monitor.size();
    let main = if primary { ", the main display" } else { "" };
    format!("Display {}, {} by {}{main}", index + 1, size.width, size.height)
}

fn same(a: &Monitor, b: &Monitor) -> bool {
    a.position() == b.position() && a.size() == b.size()
}

fn facts(app: &AppHandle) -> (Vec<Monitor>, Vec<Facts>) {
    let monitors = app.available_monitors().unwrap_or_default();
    let primary = app.primary_monitor().ok().flatten();
    let pointer = app.cursor_position().ok();
    let facts = monitors
        .iter()
        .enumerate()
        .map(|(index, monitor)| Facts {
            id: id_of(monitor, index),
            primary: primary.as_ref().is_some_and(|main| same(main, monitor)),
            holds_pointer: pointer.is_some_and(|at| holds(monitor, at)),
        })
        .collect();
    (monitors, facts)
}

fn holds(monitor: &Monitor, at: PhysicalPosition<f64>) -> bool {
    let origin = monitor.position();
    let size = monitor.size();
    at.x >= f64::from(origin.x)
        && at.y >= f64::from(origin.y)
        && at.x <= f64::from(origin.x) + f64::from(size.width)
        && at.y <= f64::from(origin.y) + f64::from(size.height)
}

/// The displays connected now and the one chosen, for the Appearance page.
#[tauri::command]
pub fn island_screens(app: AppHandle, screens: tauri::State<'_, IslandScreens>) -> Listed {
    let (monitors, facts) = facts(&app);
    Listed {
        chosen: screens.choice().stored(),
        displays: monitors
            .iter()
            .zip(&facts)
            .enumerate()
            .map(|(index, (monitor, fact))| Display {
                id: fact.id.clone(),
                name: name_of(monitor, index, fact.primary),
            })
            .collect(),
    }
}

/// Keeps the person's choice and moves the island there at once.
#[tauri::command]
pub fn island_screen_choose(
    app: AppHandle,
    stored: String,
    screens: tauri::State<'_, IslandScreens>,
) -> Result<(), String> {
    let choice = Choice::parse(&stored);
    if let Some(folder) = screens.path.parent() {
        std::fs::create_dir_all(folder).map_err(|error| error.to_string())?;
    }
    std::fs::write(&screens.path, choice.stored()).map_err(|error| error.to_string())?;
    if let Ok(mut kept) = screens.choice.lock() {
        *kept = choice;
    }
    if let Some(window) = app.get_webview_window(crate::ISLAND) {
        place(&window);
    }
    Ok(())
}

/// Puts the island at the top centre of the chosen display. While it is open it stays where it is, so it
/// never jumps away mid answer.
pub fn place(window: &WebviewWindow) {
    let app = window.app_handle();
    let resting = app
        .try_state::<Arc<HitAreas>>()
        .is_none_or(|areas| areas.resting(window.label()));
    let (choice, staying) = match app.try_state::<IslandScreens>() {
        Some(screens) => (screens.choice(), if resting { None } else { screens.current() }),
        None => (Choice::Notch, None),
    };
    let (monitors, facts) = facts(app);
    let Some(index) = screen_index(&choice, &facts, staying.as_deref()) else {
        return;
    };
    if let Some(screens) = app.try_state::<IslandScreens>() {
        if let Ok(mut current) = screens.current.lock() {
            *current = Some(facts[index].id.clone());
        }
    }
    #[cfg(target_os = "linux")]
    {
        // On Wayland nobody may read the pointer, so following it is left to the compositor's active output.
        let output = (choice != Choice::Pointer).then_some(index as i32);
        let target = window.clone();
        let _ = window.run_on_main_thread(move || {
            if let Ok(gtk) = target.gtk_window() {
                memnox_linux::set_monitor(&gtk, output);
            }
        });
    }
    let monitor = &monitors[index];
    let Ok(size) = window.outer_size() else {
        return;
    };
    let origin = monitor.position();
    let x = origin.x + (monitor.size().width as i32 - size.width as i32) / 2;
    let _ = window.set_position(PhysicalPosition::new(x, origin.y));
}

/// What changes when a display is plugged in, unplugged or rearranged.
fn layout(app: &AppHandle) -> Vec<(i32, i32, u32, u32)> {
    app.available_monitors()
        .unwrap_or_default()
        .iter()
        .map(|monitor| (monitor.position().x, monitor.position().y, monitor.size().width, monitor.size().height))
        .collect()
}

/// Moves the island to the display holding the pointer while it rests, when that is the choice, and
/// places it again whenever the displays change, so an unplugged one hands it back to the main display.
pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        let mut seen = layout(&app);
        loop {
            std::thread::sleep(LOOK_EVERY);
            let Some(window) = app.get_webview_window(crate::ISLAND) else {
                return;
            };
            let now = layout(&app);
            let changed = now != seen;
            seen = now;
            let follows = app
                .try_state::<IslandScreens>()
                .is_some_and(|screens| screens.choice() == Choice::Pointer)
                && app
                    .try_state::<Arc<HitAreas>>()
                    .is_some_and(|areas| areas.resting(window.label()));
            let moved = follows && {
                let (_, facts) = facts(&app);
                let here = app.try_state::<IslandScreens>().and_then(|screens| screens.current());
                facts
                    .iter()
                    .find(|screen| screen.holds_pointer)
                    .is_some_and(|screen| Some(&screen.id) != here.as_ref())
            };
            if changed || moved {
                let target = window.clone();
                let _ = window.run_on_main_thread(move || place(&target));
            }
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    fn screen(id: &str, primary: bool, holds_pointer: bool) -> Facts {
        Facts {
            id: id.to_owned(),
            primary,
            holds_pointer,
        }
    }

    #[test]
    fn reads_back_what_it_kept_and_falls_back_to_the_main_display() {
        for choice in [Choice::Notch, Choice::Pointer, Choice::Display("DP-1".into())] {
            assert_eq!(Choice::parse(&choice.stored()), choice);
        }
        assert_eq!(Choice::parse(""), Choice::Notch);
        assert_eq!(Choice::parse("display:"), Choice::Notch);
    }

    #[test]
    fn picks_the_main_display_the_pointer_or_a_chosen_one() {
        let screens = [screen("HDMI-1", false, true), screen("eDP-1", true, false)];
        assert_eq!(screen_index(&Choice::Notch, &screens, None), Some(1));
        assert_eq!(screen_index(&Choice::Pointer, &screens, None), Some(0));
        assert_eq!(screen_index(&Choice::Pointer, &screens, Some("eDP-1")), Some(1));
        assert_eq!(screen_index(&Choice::Display("HDMI-1".into()), &screens, None), Some(0));
        assert_eq!(screen_index(&Choice::Display("gone".into()), &screens, None), Some(1));
        assert_eq!(screen_index(&Choice::Notch, &[], None), None);
    }
}
