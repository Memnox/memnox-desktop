//! The field that has the keyboard on Linux, from AT-SPI, which works the same on X11 and Wayland and on
//! GNOME and KDE: whether it is a password, what is selected in it, its text around the cursor, and the
//! app it belongs to. The bus only says which object took focus, so the last one is remembered from its
//! `object:state-changed:focused` events. GTK apps answer at once; Qt, Chromium and Electron apps only
//! once accessibility is switched on for the session, which this asks for. Where nothing answers, the
//! field counts as unknown: not secure and with no text, so dictation falls back to typing as it did.

use std::sync::{Mutex, OnceLock};
use std::time::Duration;

use atspi::events::object::StateChangedEvent;
use atspi::proxy::accessible::{AccessibleProxy, ObjectRefExt};
use atspi::proxy::text::TextProxy;
use atspi::{AccessibilityConnection, Event, ObjectEvents, ObjectRefOwned, Role, State};
use futures_util::StreamExt;

/// How long a read may take; the island's core gives the whole focus read about this much.
const PATIENCE: Duration = Duration::from_millis(120);
/// Past this a field is a document, not a message, and its whole text is not worth carrying around.
const LONGEST_VALUE: i32 = 20_000;

/// The focused field as AT-SPI describes it, offsets in UTF 16 units as the webview counts them.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Field {
    pub app: Option<String>,
    pub secure: bool,
    pub selection: Option<String>,
    pub value: Option<String>,
    pub caret: Option<u32>,
    pub selection_end: Option<u32>,
}

static FOCUSED: Mutex<Option<ObjectRefOwned>> = Mutex::new(None);
static BUS: OnceLock<zbus::Connection> = OnceLock::new();

/// Starts following focus for the life of the app; a session with no accessibility bus simply never answers.
pub fn watch() {
    tauri::async_runtime::spawn(async {
        // Qt, Chromium and Electron only expose their widgets once a client asks for accessibility.
        let _ = atspi::connection::set_session_accessibility(true).await;
        let Ok(connection) = AccessibilityConnection::new().await else {
            return;
        };
        if connection
            .register_event::<StateChangedEvent>()
            .await
            .is_err()
        {
            return;
        }
        let _ = BUS.set(connection.connection().clone());
        let mut events = std::pin::pin!(connection.event_stream());
        while let Some(event) = events.next().await {
            if let Ok(Event::Object(ObjectEvents::StateChanged(changed))) = event {
                if changed.state == State::Focused && changed.enabled {
                    if let Ok(mut focused) = FOCUSED.lock() {
                        *focused = Some(changed.item);
                    }
                }
            }
        }
    });
}

/// The field focused now, or None when AT-SPI has not said or the read took too long.
pub fn read() -> Option<Field> {
    let item = FOCUSED.lock().ok()?.clone()?;
    let bus = BUS.get()?.clone();
    tauri::async_runtime::block_on(async move {
        tokio::time::timeout(PATIENCE, field(&bus, &item))
            .await
            .ok()
            .flatten()
    })
}

async fn field(bus: &zbus::Connection, item: &ObjectRefOwned) -> Option<Field> {
    let accessible = item.as_accessible_proxy(bus).await.ok()?;
    // Focus moved somewhere AT-SPI did not report, such as an app without accessibility, so nothing is known.
    if !accessible.get_state().await.ok()?.contains(State::Focused) {
        return None;
    }
    let app = application(bus, &accessible).await;
    if accessible.get_role().await.ok()? == Role::PasswordText {
        return Some(Field {
            app,
            secure: true,
            ..Field::default()
        });
    }
    let mut field = Field {
        app,
        ..Field::default()
    };
    let Some(text) = text_of(bus, item).await else {
        return Some(field);
    };
    let count = text.character_count().await.unwrap_or(0);
    let caret = text.caret_offset().await.ok().filter(|caret| *caret >= 0);
    let selected = if text.get_n_selections().await.unwrap_or(0) > 0 {
        text.get_selection(0)
            .await
            .ok()
            .filter(|(start, end)| end > start)
    } else {
        None
    };
    if let Some((start, end)) = selected {
        field.selection = text
            .get_text(start, end)
            .await
            .ok()
            .filter(|chosen| !chosen.trim().is_empty());
    }
    if count <= LONGEST_VALUE {
        if let Ok(value) = text.get_text(0, count).await {
            let (from, to) = selected.unwrap_or((caret.unwrap_or(-1), caret.unwrap_or(-1)));
            if from >= 0 {
                field.caret = Some(utf16_offset(&value, from));
                field.selection_end = Some(utf16_offset(&value, to.max(from)));
            }
            field.value = Some(value);
        }
    }
    Some(field)
}

/// The app's name as its toolkit gives it, lowercased like an executable name, which Wayland gives no other way.
async fn application(bus: &zbus::Connection, accessible: &AccessibleProxy<'_>) -> Option<String> {
    let app = accessible.get_application().await.ok()?;
    let name = app.as_accessible_proxy(bus).await.ok()?.name().await.ok()?;
    let name = name.trim().to_lowercase();
    (!name.is_empty()).then_some(name)
}

async fn text_of<'a>(bus: &'a zbus::Connection, item: &'a ObjectRefOwned) -> Option<TextProxy<'a>> {
    TextProxy::builder(bus)
        .destination(item.name()?.clone())
        .ok()?
        .path(item.path().clone())
        .ok()?
        .cache_properties(zbus::proxy::CacheProperties::No)
        .build()
        .await
        .ok()
}

/// AT-SPI counts characters; the webview counts UTF 16 units, which differ past the basic plane.
fn utf16_offset(text: &str, characters: i32) -> u32 {
    text.chars()
        .take(usize::try_from(characters).unwrap_or(0))
        .map(|character| character.len_utf16() as u32)
        .sum()
}

#[cfg(test)]
mod tests {
    use super::utf16_offset;

    #[test]
    fn counts_offsets_as_the_webview_does() {
        assert_eq!(utf16_offset("hello", 3), 3);
        assert_eq!(utf16_offset("a\u{1F600}b", 2), 3);
        assert_eq!(utf16_offset("ab", 9), 2);
    }
}
