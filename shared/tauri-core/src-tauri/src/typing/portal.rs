//! Typing on a Wayland session whose compositor offers no virtual keyboard, as GNOME's Mutter offers
//! none: the RemoteDesktop portal sends the keys, after one consent dialog whose answer is kept as a
//! restore token, so the person is asked once and never again, the counterpart of the Mac's Accessibility grant.

use std::path::PathBuf;
use std::time::Duration;

use ashpd::desktop::remote_desktop::{DeviceType, KeyState, RemoteDesktop, SelectDevicesOptions};
use ashpd::desktop::{PersistMode, Session};
use tokio::sync::Mutex;

/// Long enough for the person to read the consent dialog the first time.
const CONSENT_WAIT: Duration = Duration::from_secs(120);

/// Keysyms that are not the character itself.
const RETURN: i32 = 0xff0d;
const TAB: i32 = 0xff09;
const BACKSPACE: i32 = 0xff08;
/// Unicode past Latin 1 is sent as this plus the code point, as X keysyms number it.
const UNICODE_KEYSYMS: i32 = 0x0100_0000;

/// The keysym that types this character.
pub fn keysym(character: char) -> i32 {
    let point = character as i32;
    match character {
        '\n' => RETURN,
        '\t' => TAB,
        ' '..='~' | '\u{a0}'..='\u{ff}' => point,
        _ => UNICODE_KEYSYMS + point,
    }
}

struct Typing {
    portal: RemoteDesktop,
    session: Session<RemoteDesktop>,
}

static SESSION: Mutex<Option<Typing>> = Mutex::const_new(None);

/// Where the restore token is kept, so the consent dialog shows only the first time.
fn token_file() -> Option<PathBuf> {
    let config = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))?;
    Some(config.join("memnox").join("remote-desktop-token"))
}

async fn started() -> Result<Typing, String> {
    let portal = RemoteDesktop::new().await.map_err(|error| error.to_string())?;
    let session = portal.create_session(Default::default()).await.map_err(|error| error.to_string())?;
    let kept = token_file().and_then(|file| std::fs::read_to_string(file).ok());
    let options = SelectDevicesOptions::default()
        .set_devices(ashpd::enumflags2::BitFlags::from(DeviceType::Keyboard))
        .set_persist_mode(PersistMode::ExplicitlyRevoked)
        .set_restore_token(kept.as_deref().map(str::trim));
    portal.select_devices(&session, options).await.map_err(|error| error.to_string())?;
    let started = tokio::time::timeout(CONSENT_WAIT, async { portal.start(&session, None, Default::default()).await?.response() })
        .await
        .map_err(|_| "the typing permission was not answered".to_string())?
        .map_err(|_| "typing into other apps was not allowed".to_string())?;
    if let (Some(token), Some(file)) = (started.restore_token(), token_file()) {
        if let Some(dir) = file.parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        let _ = std::fs::write(file, token);
    }
    Ok(Typing { portal, session })
}

async fn send(keysyms: &[i32]) -> Result<(), String> {
    let mut held = SESSION.lock().await;
    if held.is_none() {
        *held = Some(started().await?);
    }
    let Some(typing) = held.as_ref() else {
        return Err("typing could not start".into());
    };
    for keysym in keysyms {
        for state in [KeyState::Pressed, KeyState::Released] {
            if let Err(error) = typing.portal.notify_keyboard_keysym(&typing.session, *keysym, state, Default::default()).await {
                // A session the person revoked is started again, and asks again, on the next try.
                *held = None;
                return Err(format!("the key could not be sent: {error}"));
            }
        }
    }
    Ok(())
}

pub fn type_text(text: &str) -> Result<(), String> {
    let keysyms: Vec<i32> = text.chars().filter(|character| *character != '\r').map(keysym).collect();
    tauri::async_runtime::block_on(send(&keysyms))
}

pub fn backspace(times: u32) -> Result<(), String> {
    let keysyms = vec![BACKSPACE; times as usize];
    tauri::async_runtime::block_on(send(&keysyms))
}

#[cfg(test)]
mod tests {
    use super::keysym;

    #[test]
    fn sends_latin_one_as_itself_and_the_rest_as_unicode_keysyms() {
        assert_eq!(keysym('a'), 0x61);
        assert_eq!(keysym('é'), 0xe9);
        assert_eq!(keysym('\n'), 0xff0d);
        assert_eq!(keysym('€'), 0x0100_20ac);
    }
}
