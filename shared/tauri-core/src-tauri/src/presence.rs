//! The screen locking and unlocking, which is how the Mac tells the person left and came back, so Catch
//! me up can tell them what happened while they were away. Windows says it of the input desktop, which
//! cannot be switched to while the lock screen is up; Linux says it through logind's `LockedHint`, which
//! GNOME, KDE and lockers driven by `xss-lock` all set, on X11 and Wayland alike. Looked at every few
//! seconds, since ten minutes away is what counts and a few seconds either way do not matter.

use std::time::Duration;

use tauri::{AppHandle, Emitter};

/// How often the lock is looked at.
#[cfg_attr(not(any(windows, target_os = "linux")), allow(dead_code))]
const LOOK_EVERY: Duration = Duration::from_secs(3);
/// The event the island hears, with "locked" or "unlocked".
#[cfg_attr(not(any(windows, target_os = "linux")), allow(dead_code))]
const PRESENCE_EVENT: &str = "presence";

/// Starts watching for the life of the app; a system that cannot say simply never reports.
pub fn watch(app: AppHandle) {
    #[cfg(windows)]
    std::thread::Builder::new()
        .name("memnox-presence".into())
        .spawn(move || {
            let mut was = false;
            loop {
                let locked = on_windows::locked();
                if locked != was {
                    tell(&app, locked);
                    was = locked;
                }
                std::thread::sleep(LOOK_EVERY);
            }
        })
        .map(drop)
        .unwrap_or_default();
    #[cfg(target_os = "linux")]
    tauri::async_runtime::spawn(async move {
        let _ = on_linux::follow(|locked| tell(&app, locked)).await;
    });
    #[cfg(not(any(windows, target_os = "linux")))]
    drop(app);
}

#[cfg_attr(not(any(windows, target_os = "linux")), allow(dead_code))]
fn tell(app: &AppHandle, locked: bool) {
    let _ = app.emit(PRESENCE_EVENT, if locked { "locked" } else { "unlocked" });
}

#[cfg(windows)]
mod on_windows {
    use windows::Win32::System::StationsAndDesktops::{
        CloseDesktop, OpenInputDesktop, SwitchDesktop, DESKTOP_CONTROL_FLAGS, DESKTOP_SWITCHDESKTOP,
    };

    /// The lock screen runs on a desktop of its own that no app may switch to, so the switch failing is the lock.
    pub fn locked() -> bool {
        // SAFETY: the desktop handle is closed before returning.
        unsafe {
            let Ok(desktop) =
                OpenInputDesktop(DESKTOP_CONTROL_FLAGS(0), false, DESKTOP_SWITCHDESKTOP)
            else {
                return true;
            };
            let switched = SwitchDesktop(desktop).is_ok();
            let _ = CloseDesktop(desktop);
            !switched
        }
    }
}

#[cfg(target_os = "linux")]
mod on_linux {
    use super::LOOK_EVERY;
    use zbus::zvariant::OwnedObjectPath;

    const LOGIND: &str = "org.freedesktop.login1";

    /// This session's object in logind: the one named by `XDG_SESSION_ID`, else the one this process runs in.
    async fn session(bus: &zbus::Connection) -> zbus::Result<zbus::Proxy<'static>> {
        let manager = zbus::Proxy::new(
            bus,
            LOGIND,
            "/org/freedesktop/login1",
            "org.freedesktop.login1.Manager",
        )
        .await?;
        let path: OwnedObjectPath = match std::env::var("XDG_SESSION_ID") {
            Ok(id) => manager.call("GetSession", &(id,)).await?,
            Err(_) => {
                manager
                    .call("GetSessionByPID", &(std::process::id(),))
                    .await?
            }
        };
        zbus::Proxy::new_owned(
            bus.clone(),
            LOGIND.to_string(),
            path,
            "org.freedesktop.login1.Session".to_string(),
        )
        .await
    }

    pub async fn follow(tell: impl Fn(bool)) -> zbus::Result<()> {
        let bus = zbus::Connection::system().await?;
        let session = session(&bus).await?;
        let mut was = false;
        loop {
            let locked: bool = session.get_property("LockedHint").await.unwrap_or(was);
            if locked != was {
                tell(locked);
                was = locked;
            }
            tokio::time::sleep(LOOK_EVERY).await;
        }
    }
}
