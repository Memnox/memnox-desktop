//! What the key watcher reports and nothing more: which modifiers are down and that some other key went
//! down. The Mac's hold rules run in the TypeScript core on these, so every platform reports the same way
//! and the timing lives in one tested place.

// Built on a Mac only to be checked, where no watcher runs.
#![cfg_attr(not(any(windows, target_os = "linux")), allow(dead_code))]

use serde::Serialize;

/// One key that matters on its own, by side, since right Alt dictates and left Alt with Ctrl says a rule.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Modifier {
    LeftCtrl,
    RightCtrl,
    LeftAlt,
    RightAlt,
    LeftShift,
    RightShift,
    LeftMeta,
    RightMeta,
}

/// Every modifier down now, one bit each, so letting go of one Ctrl while the other is held keeps Ctrl down.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Pressed(u8);

impl Pressed {
    fn bit(modifier: Modifier) -> u8 {
        1 << modifier as u8
    }

    pub fn set(&mut self, modifier: Modifier, down: bool) {
        if down {
            self.0 |= Self::bit(modifier);
        } else {
            self.0 &= !Self::bit(modifier);
        }
    }

    pub fn has(self, modifier: Modifier) -> bool {
        self.0 & Self::bit(modifier) != 0
    }
}

/// The payload of the `keys` event, as the island's key rules read it.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum KeyEvent {
    #[serde(rename_all = "camelCase")]
    Modifiers {
        ctrl: bool,
        left_alt: bool,
        right_alt: bool,
        shift: bool,
        meta: bool,
    },
    Key,
}

impl From<Pressed> for KeyEvent {
    fn from(pressed: Pressed) -> Self {
        use Modifier::*;
        KeyEvent::Modifiers {
            ctrl: pressed.has(LeftCtrl) || pressed.has(RightCtrl),
            left_alt: pressed.has(LeftAlt),
            right_alt: pressed.has(RightAlt),
            shift: pressed.has(LeftShift) || pressed.has(RightShift),
            meta: pressed.has(LeftMeta) || pressed.has(RightMeta),
        }
    }
}

/// Where a watcher sends what it saw; the Tauri side turns it into the `keys` event.
pub type Sink = Box<dyn Fn(KeyEvent) + Send + Sync>;

/// Sends the modifiers only when what they say changed, since a held key repeats and the island needs one event.
pub struct Reporter {
    said: Option<KeyEvent>,
    sink: Sink,
}

impl Reporter {
    pub fn new(sink: Sink) -> Self {
        Self { said: None, sink }
    }

    pub fn modifiers(&mut self, pressed: Pressed) {
        let event = KeyEvent::from(pressed);
        if self.said.as_ref() != Some(&event) {
            self.said = Some(event.clone());
            (self.sink)(event);
        }
    }

    pub fn key(&self) {
        (self.sink)(KeyEvent::Key);
    }
}

/// What one Windows key event is, by its virtual key, scan code and extended flag.
#[cfg_attr(not(windows), allow(dead_code))]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Seen {
    Modifier(Modifier),
    /// The left Ctrl Windows makes up alongside AltGr, which the person never pressed.
    Ignored,
    Other,
}

/// The scan code Windows gives the left Ctrl it sends with AltGr on international layouts.
const FAKE_CTRL_SCAN: u32 = 0x21D;

/// Classifies a key from a low level keyboard hook, so AltGr reads as right Alt alone rather than Ctrl with Alt.
#[cfg_attr(not(windows), allow(dead_code))]
pub fn windows_key(vk: u32, scan: u32, extended: bool) -> Seen {
    use Modifier::*;
    match vk {
        0x11 | 0xA2 | 0xA3 if scan == FAKE_CTRL_SCAN => Seen::Ignored,
        0xA2 => Seen::Modifier(LeftCtrl),
        0xA3 => Seen::Modifier(RightCtrl),
        0x11 => Seen::Modifier(if extended { RightCtrl } else { LeftCtrl }),
        0xA4 => Seen::Modifier(LeftAlt),
        0xA5 => Seen::Modifier(RightAlt),
        0x12 => Seen::Modifier(if extended { RightAlt } else { LeftAlt }),
        0xA0 => Seen::Modifier(LeftShift),
        0xA1 => Seen::Modifier(RightShift),
        0x10 => Seen::Modifier(if scan == 0x36 { RightShift } else { LeftShift }),
        0x5B => Seen::Modifier(LeftMeta),
        0x5C => Seen::Modifier(RightMeta),
        _ => Seen::Other,
    }
}

/// Whether a key code is down in an X11 keymap, 32 bytes with one bit per key code.
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub fn keymap_down(keymap: &[u8; 32], code: u8) -> bool {
    keymap[usize::from(code / 8)] & (1 << (code % 8)) != 0
}

/// Whether any key that is not one of the modifiers went down since the last look.
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub fn other_key_went_down(before: &[u8; 32], now: &[u8; 32], modifiers: &[u8]) -> bool {
    (8..=255u8).any(|code| {
        !modifiers.contains(&code) && keymap_down(now, code) && !keymap_down(before, code)
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    #[test]
    fn serialises_as_the_island_reads_it() {
        let mut pressed = Pressed::default();
        pressed.set(Modifier::RightAlt, true);
        let json = serde_json::to_string(&KeyEvent::from(pressed)).unwrap();
        assert_eq!(
            json,
            r#"{"kind":"modifiers","ctrl":false,"leftAlt":false,"rightAlt":true,"shift":false,"meta":false}"#
        );
        assert_eq!(
            serde_json::to_string(&KeyEvent::Key).unwrap(),
            r#"{"kind":"key"}"#
        );
    }

    #[test]
    fn keeps_ctrl_down_while_either_side_is_held() {
        let mut pressed = Pressed::default();
        pressed.set(Modifier::LeftCtrl, true);
        pressed.set(Modifier::RightCtrl, true);
        pressed.set(Modifier::LeftCtrl, false);
        assert!(matches!(KeyEvent::from(pressed), KeyEvent::Modifiers { ctrl: true, .. }));
    }

    #[test]
    fn reports_modifiers_only_when_they_change() {
        let seen = Arc::new(Mutex::new(Vec::new()));
        let into = seen.clone();
        let mut reporter = Reporter::new(Box::new(move |event| into.lock().unwrap().push(event)));
        let mut pressed = Pressed::default();
        pressed.set(Modifier::LeftAlt, true);
        reporter.modifiers(pressed);
        reporter.modifiers(pressed);
        reporter.key();
        assert_eq!(seen.lock().unwrap().len(), 2);
    }

    #[test]
    fn reads_altgr_as_right_alt_alone() {
        assert_eq!(windows_key(0xA2, FAKE_CTRL_SCAN, false), Seen::Ignored);
        assert_eq!(windows_key(0xA2, 0x1D, false), Seen::Modifier(Modifier::LeftCtrl));
        assert_eq!(windows_key(0xA5, 0x38, true), Seen::Modifier(Modifier::RightAlt));
        assert_eq!(windows_key(0x12, 0x38, true), Seen::Modifier(Modifier::RightAlt));
        assert_eq!(windows_key(0x41, 0x1E, false), Seen::Other);
    }

    #[test]
    fn finds_a_new_key_in_an_x11_keymap() {
        let before = [0u8; 32];
        let mut now = [0u8; 32];
        now[4] |= 1 << 5; // key code 37, the usual Control_L
        assert!(keymap_down(&now, 37));
        assert!(!other_key_went_down(&before, &now, &[37]));
        now[3] |= 1 << 6; // key code 30, a letter
        assert!(other_key_went_down(&before, &now, &[37]));
        assert!(!other_key_went_down(&now, &now, &[37]));
    }
}
