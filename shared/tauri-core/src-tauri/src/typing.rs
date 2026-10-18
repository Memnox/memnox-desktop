//! Dictation typed where the person's cursor is, in whatever app is in front: what that app is, whether
//! its field is a password, typing and taking back characters, and the clipboard for when the app left.
//! What to type is decided in the island's core; this only types it, each platform its own way.

#[cfg(not(any(windows, target_os = "linux")))]
#[path = "typing/elsewhere.rs"]
mod platform;
#[cfg(target_os = "linux")]
#[path = "typing/linux.rs"]
mod platform;
#[cfg(windows)]
#[path = "typing/windows.rs"]
mod platform;
#[path = "typing/tools.rs"]
mod tools;

use serde::Serialize;

/// The app in front and its focused field, as the dictation rules read them.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Focus {
    /// The executable's name without its extension, lowercased, such as "slack" or "code".
    pub app: Option<String>,
    pub title: Option<String>,
    /// A password field is never typed into by voice.
    pub secure: bool,
    /// Text selected in the field, which turns what is said into an instruction about it.
    pub selection: Option<String>,
}

/// One keystroke to send: a UTF 16 unit typed as itself, or Enter for a line break.
#[cfg_attr(not(windows), allow(dead_code))]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Stroke {
    Unit(u16),
    Enter,
}

/// The keystrokes for some text: a line break as Enter, since a typed line feed is ignored by many fields,
/// a carriage return dropped so a Windows line ending is one break, and everything else as UTF 16 units,
/// two for a character outside the basic plane, which the receiving app puts back together.
#[cfg_attr(not(windows), allow(dead_code))]
pub fn strokes(text: &str) -> Vec<Stroke> {
    let mut strokes = Vec::with_capacity(text.len());
    for character in text.chars() {
        match character {
            '\r' => {}
            '\n' => strokes.push(Stroke::Enter),
            other => {
                let mut units = [0u16; 2];
                strokes.extend(other.encode_utf16(&mut units).iter().map(|unit| Stroke::Unit(*unit)));
            }
        }
    }
    strokes
}

async fn blocking<T: Send + 'static>(work: impl FnOnce() -> T + Send + 'static) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(work)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn focus_read() -> Focus {
    blocking(platform::focus).await.unwrap_or_default()
}

#[tauri::command]
pub async fn type_text(text: String) -> Result<(), String> {
    blocking(move || platform::type_text(&text)).await?
}

/// Takes back `remove` characters before the cursor, then types `add`, so a word the recognizer revised is fixed in place.
#[tauri::command]
pub async fn type_revise(remove: u32, add: String) -> Result<(), String> {
    blocking(move || {
        platform::backspace(remove)?;
        if add.is_empty() {
            Ok(())
        } else {
            platform::type_text(&add)
        }
    })
    .await?
}

#[tauri::command]
pub async fn clipboard_set(text: String) -> Result<(), String> {
    blocking(move || platform::clipboard(&text)).await?
}

#[cfg(test)]
mod tests {
    use super::{strokes, Stroke};

    #[test]
    fn types_breaks_as_enter_and_astral_characters_as_two_units() {
        assert_eq!(
            strokes("a\r\nb"),
            vec![Stroke::Unit(0x61), Stroke::Enter, Stroke::Unit(0x62)]
        );
        assert_eq!(
            strokes("\u{1F600}"),
            vec![Stroke::Unit(0xD83D), Stroke::Unit(0xDE00)]
        );
        assert_eq!(strokes("é"), vec![Stroke::Unit(0xE9)]);
    }
}
