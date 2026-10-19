//! Keys read straight from the keyboards' event devices, the one way on Wayland to see a bare modifier
//! held in any app. It needs read access to `/dev/input`, which the person grants by joining the `input`
//! group or installing the package's udev rule, so having that access is the opt in: without it this
//! path is never taken. It only looks, and every key still reaches the app it was meant for.

use std::sync::{Arc, Mutex};
use std::thread;

use evdev::{Device, EventSummary, KeyCode};

use super::event::{Modifier, Pressed, Reporter, Sink};

/// A key the person's hold rules care about, by side.
fn modifier(code: KeyCode) -> Option<Modifier> {
    use Modifier::*;
    Some(match code {
        KeyCode::KEY_LEFTCTRL => LeftCtrl,
        KeyCode::KEY_RIGHTCTRL => RightCtrl,
        KeyCode::KEY_LEFTALT => LeftAlt,
        KeyCode::KEY_RIGHTALT => RightAlt,
        KeyCode::KEY_LEFTSHIFT => LeftShift,
        KeyCode::KEY_RIGHTSHIFT => RightShift,
        KeyCode::KEY_LEFTMETA => LeftMeta,
        KeyCode::KEY_RIGHTMETA => RightMeta,
        _ => return None,
    })
}

/// A key going down, rather than up or repeating.
const DOWN: i32 = 1;
const UP: i32 = 0;

/// Every keyboard this person may read, one with letters and Ctrl, since a mouse or a power button is no keyboard.
fn keyboards() -> Vec<Device> {
    evdev::enumerate()
        .map(|(_, device)| device)
        .filter(|device| {
            device.supported_keys().is_some_and(|keys| {
                keys.contains(KeyCode::KEY_A) && keys.contains(KeyCode::KEY_LEFTCTRL)
            })
        })
        .collect()
}

/// Watches each keyboard on a thread of its own; Err when none can be read, which is the usual case.
pub fn watch(sink: Sink) -> Result<(), String> {
    let found = keyboards();
    if found.is_empty() {
        return Err("no keyboard can be read from /dev/input".into());
    }
    let shared = Arc::new(Mutex::new((Reporter::new(sink), Vec::<Pressed>::new())));
    for (index, mut device) in found.into_iter().enumerate() {
        let shared = shared.clone();
        if let Ok(mut held) = shared.lock() {
            held.1.push(Pressed::default());
        }
        thread::Builder::new()
            .name("memnox-keys-evdev".into())
            .spawn(move || loop {
                let Ok(events) = device.fetch_events() else {
                    // Unplugged: this keyboard is done, and the others carry on.
                    return;
                };
                for event in events {
                    let EventSummary::Key(_, code, value) = event.destructure() else {
                        continue;
                    };
                    let Ok(mut held) = shared.lock() else {
                        return;
                    };
                    let (reporter, boards) = &mut *held;
                    match (modifier(code), value) {
                        (Some(modifier), DOWN | UP) => {
                            boards[index].set(modifier, value == DOWN);
                            // Two keyboards count as one, so Ctrl on one and Alt on another is still the chord.
                            let mut all = Pressed::default();
                            for board in boards.iter() {
                                for each in ALL {
                                    if board.has(each) {
                                        all.set(each, true);
                                    }
                                }
                            }
                            reporter.modifiers(all);
                        }
                        (None, DOWN) => reporter.key(),
                        _ => {}
                    }
                }
            })
            .map_err(|error| error.to_string())?;
    }
    Ok(())
}

const ALL: [Modifier; 8] = [
    Modifier::LeftCtrl,
    Modifier::RightCtrl,
    Modifier::LeftAlt,
    Modifier::RightAlt,
    Modifier::LeftShift,
    Modifier::RightShift,
    Modifier::LeftMeta,
    Modifier::RightMeta,
];
