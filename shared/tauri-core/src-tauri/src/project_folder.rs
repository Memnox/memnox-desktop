//! The folder a person picks in the system's own dialog to add as a project, as the Mac's Finder panel does. The
//! dialog runs here, so the Memnox window holds no dialog permission and names only the folder the person chose.

use tauri::{AppHandle, WebviewWindow};
use tauri_plugin_dialog::DialogExt;

/// The dialog's title, the words the Mac's panel puts on its button.
const PICK_TITLE: &str = "Add as a project";

/// Asks for one folder and answers its path, or nothing when the person cancelled.
#[tauri::command]
pub async fn pick_project_folder(
    app: AppHandle,
    window: WebviewWindow,
) -> Result<Option<String>, String> {
    if !crate::settings_windows::is_memnox_window(window.label()) {
        return Err("only the Memnox window adds a project".to_owned());
    }
    let (sent, chosen) = tokio::sync::oneshot::channel();
    app.dialog()
        .file()
        .set_parent(&window)
        .set_title(PICK_TITLE)
        .pick_folder(move |path| {
            let _ = sent.send(path);
        });
    let Some(path) = chosen.await.map_err(|error| error.to_string())? else {
        return Ok(None);
    };
    let path = path.into_path().map_err(|error| error.to_string())?;
    Ok(Some(path.to_string_lossy().into_owned()))
}
