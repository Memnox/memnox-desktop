//! What this computer lets Memnox do, read as plain facts for the core to word: the Mac asks for the
//! microphone, Accessibility and Screen Recording, and here the same three questions have other answers.
//! Windows guards the microphone behind a privacy switch and lets an app type and read the screen; Linux
//! has no switch for the microphone, lets X11 apps type freely, and on Wayland types only through uinput.

use serde::Serialize;

/// The facts the Permissions page and the first run are drawn from; the core turns them into rows.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct PermissionFacts {
    /// windows, linux, or other for a development build on a Mac.
    platform: &'static str,
    /// x11 or wayland on Linux, desktop on Windows.
    session: &'static str,
    /// allowed, denied, none (no input device at all) or unknown.
    microphone: &'static str,
    /// Whether keys typed for the person reach other apps.
    typing: bool,
}

#[tauri::command]
pub fn permission_facts() -> PermissionFacts {
    PermissionFacts {
        platform: platform(),
        session: session(),
        microphone: microphone(),
        typing: typing(),
    }
}

/// Opens the system's own page for one permission, answering whether one opened.
#[tauri::command]
pub fn open_privacy(pane: String) -> bool {
    privacy_pages(&pane)
        .iter()
        .any(|page| open_with_system(page).is_ok() || run(page))
}

fn platform() -> &'static str {
    if cfg!(windows) {
        "windows"
    } else if cfg!(target_os = "linux") {
        "linux"
    } else {
        "other"
    }
}

fn session() -> &'static str {
    if cfg!(windows) {
        return "desktop";
    }
    let wayland = std::env::var("XDG_SESSION_TYPE").is_ok_and(|kind| kind == "wayland")
        || std::env::var_os("WAYLAND_DISPLAY").is_some();
    if wayland {
        "wayland"
    } else {
        "x11"
    }
}

/// The privacy switch for desktop apps, as Windows keeps it per user: Deny on the whole microphone or on
/// apps that are not from the Store turns Memnox deaf, whatever else is set.
#[cfg(windows)]
fn microphone() -> &'static str {
    const STORE: &str =
        r"HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone";
    let read = |key: &str| {
        std::process::Command::new("reg")
            .args(["query", key, "/v", "Value"])
            .output()
            .ok()
            .map(|out| String::from_utf8_lossy(&out.stdout).to_string())
    };
    let whole = read(STORE);
    let desktop = read(&format!(r"{STORE}\NonPackaged"));
    let denied = |answer: &Option<String>| answer.as_deref().is_some_and(|text| text.contains("Deny"));
    if denied(&whole) || denied(&desktop) {
        "denied"
    } else if whole.is_none() && desktop.is_none() {
        "unknown"
    } else {
        "allowed"
    }
}

/// Linux asks nothing before an app hears, so what matters is whether there is anything to hear with.
#[cfg(not(windows))]
fn microphone() -> &'static str {
    if !cfg!(target_os = "linux") {
        return "unknown";
    }
    let capture = std::fs::read_dir("/dev/snd").map(|devices| {
        devices
            .flatten()
            .any(|device| device.file_name().to_string_lossy().ends_with('c'))
    });
    match capture {
        Ok(true) => "allowed",
        Ok(false) => "none",
        Err(_) => "unknown",
    }
}

/// Windows and X11 deliver typed keys to other apps; Wayland only through uinput, which needs write access.
fn typing() -> bool {
    if cfg!(windows) || session() == "x11" {
        return true;
    }
    uinput_writable()
}

#[cfg(unix)]
fn uinput_writable() -> bool {
    let path = c"/dev/uinput";
    // SAFETY: access reads a constant, NUL terminated path and changes nothing.
    unsafe { libc::access(path.as_ptr(), libc::W_OK) == 0 }
}

#[cfg(not(unix))]
fn uinput_writable() -> bool {
    false
}

/// Each pane's own page, best first: a Windows settings link, or the Linux desktops' sound and privacy panels.
fn privacy_pages(pane: &str) -> Vec<&'static str> {
    if cfg!(windows) {
        return match pane {
            "microphone" => vec!["ms-settings:privacy-microphone"],
            "sound" => vec!["ms-settings:sound"],
            _ => vec!["ms-settings:privacy"],
        };
    }
    match pane {
        "microphone" | "sound" => vec!["gnome-control-center sound", "systemsettings kcm_pulseaudio"],
        _ => vec!["gnome-control-center privacy", "systemsettings"],
    }
}

/// Runs one fixed line from the table above, never anything the webview wrote.
fn run(line: &str) -> bool {
    let mut words = line.split_whitespace();
    let Some(program) = words.next() else {
        return false;
    };
    std::process::Command::new(program).args(words).spawn().is_ok()
}

/// Hands a link to whatever the system opens links with.
pub fn open_with_system(link: &str) -> Result<(), String> {
    let mut command = if cfg!(windows) {
        // rundll32 takes the link whole, where cmd's start would read an ampersand in it as a second command.
        let mut command = std::process::Command::new("rundll32");
        command.args(["url.dll,FileProtocolHandler", link]);
        command
    } else if cfg!(target_os = "macos") {
        let mut command = std::process::Command::new("open");
        command.arg(link);
        command
    } else {
        let mut command = std::process::Command::new("xdg-open");
        command.arg(link);
        command
    };
    if !link.contains(':') {
        return Err(format!("{link} is not a link"));
    }
    command.spawn().map(|_| ()).map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_pane_never_runs_more_than_its_fixed_lines() {
        for pane in ["microphone", "sound", "typing", "screen", "rm -rf /"] {
            for page in privacy_pages(pane) {
                assert!(page.starts_with("ms-settings:") || page.starts_with("gnome-control-center") || page.starts_with("systemsettings"));
            }
        }
    }

    #[test]
    fn something_that_is_not_a_link_is_not_opened() {
        assert!(open_with_system("not a link").is_err());
    }
}
