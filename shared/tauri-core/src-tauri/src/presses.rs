//! A press in the Memnox window, carried to the island alone, so a proposal the press raised is confirmed
//! there as asked for rather than declined. Only the window's own labels may tell of one, and only the
//! island may hear them, over a channel no other window can write to; the daemon's socket, which any
//! process on this computer reaches, has no part in it.

use std::sync::Mutex;

use serde::{Deserialize, Serialize};
use tauri::{ipc::Channel, State, WebviewWindow};

use crate::settings_windows::{ONBOARDING, SETTINGS};
use crate::ISLAND;

/// A page raises a handful at once at most; a longer list is not a press of ours.
const MOST_RAISED: usize = 64;
/// A request token or a proposal id is far shorter than this.
const LONGEST_ID: usize = 200;

/// One press, as `Press` in `core/application/presses.ts`: no `raised` while it waits on the daemon.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Press {
    token: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    raised: Option<Vec<String>>,
}

/// The island's end of the route, replaced when the island loads again.
#[derive(Default)]
pub struct PressRoute(Mutex<Option<Channel<Press>>>);

/// The island hands over the channel it hears presses on.
#[tauri::command]
pub fn presses_listen(
    window: WebviewWindow,
    route: State<'_, PressRoute>,
    presses: Channel<Press>,
) -> Result<(), String> {
    if window.label() != ISLAND {
        return Err("only the island hears presses".into());
    }
    *route.0.lock().map_err(|error| error.to_string())? = Some(presses);
    Ok(())
}

/// The Memnox window or the first run tells of a press, and the island hears of it if it is up.
#[tauri::command]
pub fn window_press(
    window: WebviewWindow,
    route: State<'_, PressRoute>,
    press: Press,
) -> Result<(), String> {
    if !pressed_in_window(window.label()) {
        return Err("only the Memnox window tells of a press".into());
    }
    if !well_formed(&press) {
        return Err("that is not a press".into());
    }
    let route = route.0.lock().map_err(|error| error.to_string())?;
    match route.as_ref() {
        Some(island) => island.send(press).map_err(|error| error.to_string()),
        None => Ok(()),
    }
}

/// The windows a person presses in, by the labels `settings_windows` gives them.
fn pressed_in_window(label: &str) -> bool {
    label == SETTINGS || label == ONBOARDING
}

fn well_formed(press: &Press) -> bool {
    let fits = |id: &String| !id.is_empty() && id.len() <= LONGEST_ID;
    fits(&press.token)
        && press
            .raised
            .as_ref()
            .is_none_or(|raised| raised.len() <= MOST_RAISED && raised.iter().all(fits))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn press(raised: Option<Vec<&str>>) -> Press {
        Press {
            token: "tok".into(),
            raised: raised.map(|ids| ids.into_iter().map(String::from).collect()),
        }
    }

    #[test]
    fn only_the_memnox_window_and_the_first_run_tell_of_a_press() {
        assert!(pressed_in_window(SETTINGS));
        assert!(pressed_in_window(ONBOARDING));
        assert!(!pressed_in_window(ISLAND));
        assert!(!pressed_in_window("live"));
        assert!(!pressed_in_window("cards"));
    }

    #[test]
    fn a_press_is_short_and_names_a_handful() {
        assert!(well_formed(&press(None)));
        assert!(well_formed(&press(Some(vec!["prp_1", "prp_2"]))));
        assert!(!well_formed(&press(Some(vec![""]))));
        let long = "p".repeat(LONGEST_ID + 1);
        assert!(!well_formed(&press(Some(vec![long.as_str()]))));
        assert!(!well_formed(&press(Some(vec!["prp"; MOST_RAISED + 1]))));
    }

    #[test]
    fn reads_the_press_the_window_sends() {
        let read: Press = serde_json::from_str(r#"{"token":"t","raised":["prp_1"]}"#).unwrap();
        assert_eq!(read, press(Some(vec!["prp_1"])).with_token("t"));
        let waiting: Press = serde_json::from_str(r#"{"token":"t"}"#).unwrap();
        assert_eq!(waiting.raised, None);
        assert_eq!(serde_json::to_string(&waiting).unwrap(), r#"{"token":"t"}"#);
    }

    impl Press {
        fn with_token(mut self, token: &str) -> Self {
            self.token = token.into();
            self
        }
    }
}
