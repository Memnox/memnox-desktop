//! A rule pack read from and saved to a file the person picks in the system's own dialog. The dialog and the
//! file are both handled here, so the Memnox window names no path itself and can reach no file the person did
//! not pick. Nothing here decides a rule: the TOML goes to the daemon, which proposes each rule to be signed.

use std::path::PathBuf;

use tauri::{AppHandle, WebviewWindow};
use tauri_plugin_dialog::DialogExt;

const PACK_FILTER: &str = "Rule pack";
const PACK_EXTENSIONS: &[&str] = &["toml"];
const SAVED_NAME: &str = "memnox-rules.toml";
/// A pack is a short text file; anything larger is not one, and is refused before it is read whole.
const LARGEST_PACK: u64 = 1024 * 1024;

/// Asks for a pack in the open dialog and answers its text, or nothing when the person cancelled.
#[tauri::command]
pub async fn pick_rule_pack(
    app: AppHandle,
    window: WebviewWindow,
) -> Result<Option<String>, String> {
    allowed(&window)?;
    let (sent, chosen) = tokio::sync::oneshot::channel();
    app.dialog()
        .file()
        .set_parent(&window)
        .add_filter(PACK_FILTER, PACK_EXTENSIONS)
        .pick_file(move |path| {
            let _ = sent.send(path);
        });
    let Some(path) = chosen.await.map_err(|error| error.to_string())? else {
        return Ok(None);
    };
    let path = path.into_path().map_err(|error| error.to_string())?;
    read_pack(&path).map(Some)
}

/// Asks where to save the pack in the save dialog and writes it there; false when the person cancelled.
#[tauri::command]
pub async fn save_rule_pack(
    app: AppHandle,
    window: WebviewWindow,
    toml: String,
) -> Result<bool, String> {
    allowed(&window)?;
    let (sent, chosen) = tokio::sync::oneshot::channel();
    app.dialog()
        .file()
        .set_parent(&window)
        .add_filter(PACK_FILTER, PACK_EXTENSIONS)
        .set_file_name(SAVED_NAME)
        .save_file(move |path| {
            let _ = sent.send(path);
        });
    let Some(path) = chosen.await.map_err(|error| error.to_string())? else {
        return Ok(false);
    };
    let path = path.into_path().map_err(|error| error.to_string())?;
    std::fs::write(&path, toml).map_err(|error| error.to_string())?;
    Ok(true)
}

/// Only the Memnox window and its popped out inspectors carry Policies, so only they ask.
fn allowed(window: &WebviewWindow) -> Result<(), String> {
    if crate::settings_windows::is_memnox_window(window.label()) {
        Ok(())
    } else {
        Err("only the Memnox window reads or saves a rule pack".to_owned())
    }
}

fn read_pack(path: &PathBuf) -> Result<String, String> {
    let facts = std::fs::metadata(path).map_err(|error| error.to_string())?;
    if !facts.is_file() {
        return Err(format!("{} is not a file", path.display()));
    }
    if facts.len() > LARGEST_PACK {
        return Err(format!("{} is too large to be a rule pack", path.display()));
    }
    std::fs::read_to_string(path)
        .map_err(|_| format!("{} could not be read as text", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn folder(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("memnox-pack-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("a temporary folder");
        dir
    }

    #[test]
    fn reads_a_pack_as_text() {
        let pack = folder("read").join("rules.toml");
        std::fs::write(&pack, "[[rules]]\nname = \"ask before push\"\n").unwrap();
        assert!(read_pack(&pack).unwrap().contains("ask before push"));
    }

    #[test]
    fn refuses_a_folder_and_a_file_too_large_to_be_a_pack() {
        let dir = folder("refuse");
        assert!(read_pack(&dir).is_err());
        let large = dir.join("large.toml");
        std::fs::write(&large, vec![b'a'; (LARGEST_PACK + 1) as usize]).unwrap();
        assert!(read_pack(&large).is_err());
    }
}
