//! Keys seen from anywhere on Linux by looking at the X11 keymap many times a second, which needs no
//! permission. A Wayland session without XWayland allows no such look, so the watcher says so instead.

use std::os::raw::c_char;
use std::sync::mpsc::channel;
use std::thread;
use std::time::Duration;

use x11_dl::keysym;
use x11_dl::xlib::{Display, Xlib};

use super::event::{keymap_down, other_key_went_down, Modifier, Pressed, Reporter, Sink};

/// Often enough that a tap and a double tap are both seen, rarely enough to cost nothing.
const LOOK_EVERY: Duration = Duration::from_millis(15);

/// The display pointer is only used on the watcher's own thread once handed over.
struct OnlyHere(*mut Display);
// SAFETY: the display is opened on one thread and used only by the watcher thread after that.
unsafe impl Send for OnlyHere {}

pub fn watch(sink: Sink) -> Result<(), String> {
    let (ready, opened) = channel();
    thread::Builder::new()
        .name("memnox-keys".into())
        .spawn(move || {
            let xlib = match Xlib::open() {
                Ok(xlib) => xlib,
                Err(error) => {
                    let _ = ready.send(Err(format!("X11 is not installed here, so keys held in other apps cannot be seen: {error}")));
                    return;
                }
            };
            // SAFETY: a null name opens the display named by DISPLAY.
            let display = OnlyHere(unsafe { (xlib.XOpenDisplay)(std::ptr::null()) });
            if display.0.is_null() {
                let _ = ready.send(Err("there is no X11 display, as on a Wayland session without XWayland, so keys held in other apps cannot be seen".into()));
                return;
            }
            let _ = ready.send(Ok(()));
            look(&xlib, display, Reporter::new(sink));
        })
        .map_err(|error| error.to_string())?;
    opened
        .recv()
        .map_err(|_| "the key watcher stopped before it started".to_string())?
}

/// The key codes of each modifier on this keyboard, which depend on its layout.
fn codes(xlib: &Xlib, display: *mut Display) -> Vec<(u8, Modifier)> {
    use Modifier::*;
    let wanted = [
        (keysym::XK_Control_L, LeftCtrl),
        (keysym::XK_Control_R, RightCtrl),
        (keysym::XK_Alt_L, LeftAlt),
        (keysym::XK_Alt_R, RightAlt),
        (keysym::XK_ISO_Level3_Shift, RightAlt),
        (keysym::XK_Shift_L, LeftShift),
        (keysym::XK_Shift_R, RightShift),
        (keysym::XK_Super_L, LeftMeta),
        (keysym::XK_Super_R, RightMeta),
    ];
    wanted
        .iter()
        // SAFETY: the display is open and the keysym is a plain number.
        .map(|(sym, modifier)| (unsafe { (xlib.XKeysymToKeycode)(display, u64::from(*sym) as _) }, *modifier))
        .filter(|(code, _)| *code != 0)
        .collect()
}

fn look(xlib: &Xlib, display: OnlyHere, mut reporter: Reporter) {
    let display = display.0;
    let codes = codes(xlib, display);
    let modifier_codes: Vec<u8> = codes.iter().map(|(code, _)| *code).collect();
    let mut before = [0u8; 32];
    loop {
        let mut keys = [0 as c_char; 32];
        // SAFETY: XQueryKeymap fills exactly 32 bytes.
        unsafe { (xlib.XQueryKeymap)(display, keys.as_mut_ptr()) };
        let now = keys.map(|byte| byte as u8);
        let mut pressed = Pressed::default();
        for (code, modifier) in &codes {
            if keymap_down(&now, *code) {
                pressed.set(*modifier, true);
            }
        }
        reporter.modifiers(pressed);
        if other_key_went_down(&before, &now, &modifier_codes) {
            reporter.key();
        }
        before = now;
        thread::sleep(LOOK_EVERY);
    }
}
