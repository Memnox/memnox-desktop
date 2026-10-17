//! The confirm key as the webview reaches it: the public point to register, and a signature over
//! exactly the words the core built, made only after the operating system asked the person.

use memnox_desktop_key::{point_base64, signature_base64, ConfirmKey, NoKey, Signed};
use std::sync::Arc;

/// This computer's key, chosen once at start up.
pub struct Key(pub Arc<dyn ConfirmKey>);

impl Key {
    /// macOS has its own app, so a development build there has no key and signs nothing.
    #[allow(unused_variables)]
    pub fn for_platform(window: &tauri::WebviewWindow) -> Self {
        #[cfg(windows)]
        if let Ok(hwnd) = window.hwnd() {
            return Self(Arc::new(memnox_windows::TpmKey::new(hwnd.0 as isize)));
        }
        #[cfg(target_os = "linux")]
        return Self(Arc::new(memnox_linux::SecretKey::new()));
        #[allow(unreachable_code)]
        Self(Arc::new(NoKey))
    }
}

/// The base64 X9.63 point, or None where this computer holds no key.
#[tauri::command]
pub async fn confirm_key_point(key: tauri::State<'_, Key>) -> Result<Option<String>, String> {
    let key = key.0.clone();
    let point = tauri::async_runtime::spawn_blocking(move || key.public_point())
        .await
        .map_err(|error| error.to_string())?
        .map_err(|error| error.to_string())?;
    Ok(point.as_ref().map(point_base64))
}

/// A base64 DER signature, or None when the person declined. Blocks on the prompt, so off the main thread.
#[tauri::command]
pub async fn confirm_key_sign(
    key: tauri::State<'_, Key>,
    message: String,
    reason: String,
) -> Result<Option<String>, String> {
    let key = key.0.clone();
    let signed =
        tauri::async_runtime::spawn_blocking(move || key.sign(message.as_bytes(), &reason))
            .await
            .map_err(|error| error.to_string())?
            .map_err(|error| error.to_string())?;
    Ok(match signed {
        Signed::Signature(der) => Some(signature_base64(&der)),
        Signed::Declined => None,
    })
}
