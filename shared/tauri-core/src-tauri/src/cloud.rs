//! Memnox Cloud for the person signed in on this computer: one HTTPS exchange at a time to the cloud's own
//! host, and the person's credential in the system's credential store through `keyring`. The core holds every
//! rule of the sign in and the inbox; this is the transport and the store, as the Mac's `URLSessionTransport`
//! and `KeychainPersonCredential` are. Only the cloud's host is reached, so the webview cannot use this to
//! send a request anywhere else.

use serde::Serialize;

/// Where Memnox Cloud answers; another deployment is named with MEMNOX_CLOUD_URL.
const DEFAULT_BASE: &str = "https://api.memnox.com/";
/// Long enough for a slow network, short enough that a poll never stacks behind a dead one.
const TIMEOUT: std::time::Duration = std::time::Duration::from_secs(20);
/// Its own service, so reading or forgetting the paired servers never touches the person's credential.
const SERVICE: &str = "com.memnox.desktop.person";
const ACCOUNT: &str = "workspace";

#[derive(Serialize)]
pub struct Answer {
    status: u16,
    body: String,
}

fn base() -> String {
    let base = std::env::var("MEMNOX_CLOUD_URL").unwrap_or_else(|_| DEFAULT_BASE.into());
    if base.ends_with('/') {
        base
    } else {
        format!("{base}/")
    }
}

/// A path under the cloud's API and nothing else: relative, no way up and no other host.
fn allowed(path: &str) -> bool {
    path.starts_with("v1/")
        && !path.contains("..")
        && !path.contains("://")
        && !path.contains('\\')
        && !path.contains('#')
}

/// One exchange: the status and the body, or why nothing came back at all.
#[tauri::command]
pub async fn cloud_send(
    method: String,
    path: String,
    body: Option<String>,
    token: Option<String>,
) -> Result<Answer, String> {
    if !matches!(method.as_str(), "GET" | "POST" | "DELETE") || !allowed(&path) {
        return Err(format!("{method} {path} is not a Memnox Cloud request"));
    }
    let url = format!("{}{path}", base());
    tokio::task::spawn_blocking(move || exchange(&method, &url, body.as_deref(), token.as_deref()))
        .await
        .map_err(|why| why.to_string())?
}

fn exchange(
    method: &str,
    url: &str,
    body: Option<&str>,
    token: Option<&str>,
) -> Result<Answer, String> {
    let mut request = ureq::request(method, url)
        .timeout(TIMEOUT)
        .set("Accept", "application/json");
    if let Some(token) = token {
        request = request.set("Authorization", &format!("Bearer {token}"));
    }
    let answered = match body {
        Some(body) => request
            .set("Content-Type", "application/json")
            .send_string(body),
        None => request.call(),
    };
    let response = match answered {
        Ok(response) => response,
        // A refusal is still an answer, and the core reads its status and words.
        Err(ureq::Error::Status(_, response)) => response,
        Err(why) => return Err(why.to_string()),
    };
    let status = response.status();
    let body = response.into_string().map_err(|why| why.to_string())?;
    Ok(Answer { status, body })
}

fn entry() -> Result<keyring::Entry, String> {
    keyring::Entry::new(SERVICE, ACCOUNT).map_err(|why| why.to_string())
}

/// The credential as the core saved it, or None when nobody is signed in or the store cannot be read.
#[tauri::command]
pub async fn person_credential_load() -> Result<Option<String>, String> {
    tokio::task::spawn_blocking(|| match entry()?.get_password() {
        Ok(text) => Ok(Some(text)),
        Err(keyring::Error::NoEntry) => Ok(None),
        Err(why) => Err(why.to_string()),
    })
    .await
    .map_err(|why| why.to_string())?
}

#[tauri::command]
pub async fn person_credential_save(credential: String) -> Result<(), String> {
    tokio::task::spawn_blocking(move || {
        entry()?
            .set_password(&credential)
            .map_err(|why| why.to_string())
    })
    .await
    .map_err(|why| why.to_string())?
}

#[tauri::command]
pub async fn person_credential_delete() -> Result<(), String> {
    tokio::task::spawn_blocking(|| match entry()?.delete_credential() {
        Ok(()) | Err(keyring::Error::NoEntry) => Ok(()),
        Err(why) => Err(why.to_string()),
    })
    .await
    .map_err(|why| why.to_string())?
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_the_clouds_own_api_paths_are_sent() {
        assert!(allowed("v1/me"));
        assert!(allowed("v1/workspaces/ws_1/me/held?include=recent"));
        assert!(!allowed("/v1/me"));
        assert!(!allowed("v1/../admin"));
        assert!(!allowed("https://evil.example/v1"));
        assert!(!allowed("v2/me"));
    }
}
