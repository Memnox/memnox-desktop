//! The keys on a Wayland session through the GlobalShortcuts portal, since Wayland lets no app watch the
//! keyboard: three shortcuts are bound, to talk, to say a rule and to dictate, and the portal says when
//! each goes down and comes up again, which gives a hold. The desktop shows its own dialog the first time
//! and the person may choose other keys there; what it settled on is kept to be shown. KDE Plasma 5.27
//! and later, GNOME 48 and later and Hyprland have the portal; older GNOME and sway do not.

use std::sync::Mutex;
use std::time::Duration;

use ashpd::desktop::global_shortcuts::{GlobalShortcuts, NewShortcut};
use futures_util::StreamExt;

use super::event::{KeyEvent, Sink};

/// The shortcuts, by id, with what the person reads in the dialog and the chord asked for.
const SHORTCUTS: [(&str, &str, &str); 3] = [
    (TALK, "Talk to Memnox", "CTRL+ALT+space"),
    (RULE, "Hold to say a rule to Memnox", "CTRL+ALT+R"),
    (DICTATE, "Hold to dictate, or tap twice to dictate hands free", "CTRL+ALT+D"),
];
const TALK: &str = "talk";
const RULE: &str = "rule";
const DICTATE: &str = "dictate";
/// How long the portal may take to open a session before the desktop counts as having none.
const SESSION_WAIT: Duration = Duration::from_secs(3);

/// The chord the desktop settled on for each shortcut, as it describes it, for the island to show.
pub static CHORDS: Mutex<Vec<(String, String)>> = Mutex::new(Vec::new());

/// What each shortcut going down or up means to the island's key rules.
pub fn meaning(id: &str, down: bool) -> Option<KeyEvent> {
    match id {
        TALK if down => Some(KeyEvent::Talk),
        RULE => Some(KeyEvent::Rule { down }),
        DICTATE => Some(KeyEvent::Dictate { down }),
        _ => None,
    }
}

/// Opens a session and binds the shortcuts; returns once the portal answered, or why it could not.
pub fn watch(sink: Sink) -> Result<(), String> {
    let (ready, opened) = std::sync::mpsc::channel();
    tauri::async_runtime::spawn(async move {
        let portal = match GlobalShortcuts::new().await {
            Ok(portal) => portal,
            Err(error) => {
                let _ = ready.send(Err(format!("this desktop has no shortcuts portal: {error}")));
                return;
            }
        };
        let session = match portal.create_session(Default::default()).await {
            Ok(session) => session,
            Err(error) => {
                let _ = ready.send(Err(format!("the shortcuts portal would not open a session: {error}")));
                return;
            }
        };
        let (Ok(activated), Ok(deactivated)) = (portal.receive_activated().await, portal.receive_deactivated().await) else {
            let _ = ready.send(Err("the shortcuts portal does not report its keys".to_string()));
            return;
        };
        let _ = ready.send(Ok(()));
        let shortcuts: Vec<NewShortcut> = SHORTCUTS
            .iter()
            .map(|(id, description, chord)| NewShortcut::new(*id, *description).preferred_trigger(*chord))
            .collect();
        if let Ok(bound) = portal.bind_shortcuts(&session, &shortcuts, None, Default::default()).await.and_then(|request| request.response()) {
            if let Ok(mut chords) = CHORDS.lock() {
                *chords = bound
                    .shortcuts()
                    .iter()
                    .map(|shortcut| (shortcut.id().to_string(), shortcut.trigger_description().to_string()))
                    .collect();
            }
        }
        let downs = activated.map(|down| meaning(down.shortcut_id(), true));
        let ups = deactivated.map(|up| meaning(up.shortcut_id(), false));
        let mut both = std::pin::pin!(futures_util::stream::select(downs, ups));
        while let Some(seen) = both.next().await {
            if let Some(event) = seen {
                sink(event);
            }
        }
        // Kept open for as long as the shortcuts are wanted, which is the life of the app.
        drop(session);
    });
    opened
        .recv_timeout(SESSION_WAIT)
        .map_err(|_| "the shortcuts portal did not answer".to_string())?
}

#[cfg(test)]
mod tests {
    use super::{meaning, KeyEvent};

    #[test]
    fn holds_the_rule_and_dictation_shortcuts_and_talks_on_a_press() {
        assert_eq!(meaning("talk", true), Some(KeyEvent::Talk));
        assert_eq!(meaning("talk", false), None);
        assert_eq!(meaning("rule", true), Some(KeyEvent::Rule { down: true }));
        assert_eq!(meaning("dictate", false), Some(KeyEvent::Dictate { down: false }));
        assert_eq!(meaning("other", true), None);
    }
}
