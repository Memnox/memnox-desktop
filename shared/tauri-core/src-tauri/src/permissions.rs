//! What this computer lets Memnox do, read as plain facts for the core to word: the Mac asks for the
//! microphone, Accessibility and Screen Recording, and here the same three questions have other answers.
//! Windows guards the microphone behind a privacy switch and lets an app type and read the screen; Linux
//! has no switch for the microphone, lets X11 apps type freely, and on Wayland types only through uinput.

use serde::Serialize;

/// The facts the Permissions page and the first run are drawn from; the core turns them into rows.
#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PermissionFacts {
    /// windows, linux, or other for a development build on a Mac.
    platform: &'static str,
    /// x11 or wayland on Linux, desktop on Windows.
    session: &'static str,
    /// allowed, denied, none (no input device at all) or unknown.
    microphone: &'static str,
    /// Whether keys typed for the person reach other apps.
    typing: bool,
    /// What seeing the screen would go through; nothing here is a grant, since no capture is asked for yet.
    seeing: Seeing,
    /// On Linux, whether a polkit agent runs to show the prompt before the key signs; None elsewhere.
    polkit_agent: Option<bool>,
    /// The Memnox terminals extension the daemon puts into the editors here.
    editors: Editors,
}

/// What a look at the screen would need: the desktop portal on Wayland, and the accessibility bus for the outline.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Seeing {
    /// Whether the screenshot portal answers; None where no portal is needed.
    portal: Option<bool>,
    /// Whether the accessibility bus is on, which GNOME leaves off; None where it was not read.
    accessibility: Option<bool>,
}

/// Which editors are here at all, and which hold the extension, by the folder they keep extensions in.
#[derive(Clone, Debug, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Editors {
    present: bool,
    with_extension: Vec<String>,
}

/// Read off the main thread, since a few of the facts ask the session bus.
#[tauri::command]
pub async fn permission_facts() -> PermissionFacts {
    tauri::async_runtime::spawn_blocking(|| PermissionFacts {
        platform: platform(),
        session: session(),
        microphone: microphone(),
        typing: typing(),
        seeing: seeing(),
        polkit_agent: polkit_agent(),
        editors: editors(),
    })
    .await
    .unwrap_or_else(|_| PermissionFacts {
        platform: platform(),
        session: session(),
        microphone: "unknown",
        typing: false,
        seeing: Seeing {
            portal: None,
            accessibility: None,
        },
        polkit_agent: None,
        editors: Editors {
            present: false,
            with_extension: Vec::new(),
        },
    })
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
    const STORE: &str = r"HKCU\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone";
    let read = |key: &str| {
        std::process::Command::new("reg")
            .args(["query", key, "/v", "Value"])
            .output()
            .ok()
            .map(|out| String::from_utf8_lossy(&out.stdout).to_string())
    };
    let whole = read(STORE);
    let desktop = read(&format!(r"{STORE}\NonPackaged"));
    let denied =
        |answer: &Option<String>| answer.as_deref().is_some_and(|text| text.contains("Deny"));
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

/// On Linux, asks the session bus through `busctl`, which every systemd desktop has; elsewhere nothing is read.
fn seeing() -> Seeing {
    if !cfg!(target_os = "linux") {
        return Seeing {
            portal: None,
            accessibility: None,
        };
    }
    let portal = (session() == "wayland").then(|| {
        bus_answer(&[
            "--user",
            "get-property",
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.Screenshot",
            "version",
        ])
        .is_some()
    });
    let accessibility = bus_answer(&[
        "--user",
        "get-property",
        "org.a11y.Bus",
        "/org/a11y/bus",
        "org.a11y.Status",
        "IsEnabled",
    ])
    .map(|answer| answer.trim() == "b true");
    Seeing {
        portal,
        accessibility,
    }
}

/// What `busctl` printed, or None when it failed or is not here.
fn bus_answer(args: &[&str]) -> Option<String> {
    let out = std::process::Command::new("busctl")
        .args(args)
        .output()
        .ok()?;
    out.status
        .success()
        .then(|| String::from_utf8_lossy(&out.stdout).to_string())
}

/// The agents that show polkit's prompt, by the name each runs under, as `/proc/<pid>/comm` keeps its first 15
/// letters. GNOME Shell carries its own; KDE, MATE, Xfce, LXQt, Hyprland and the rest run one of these.
const POLKIT_AGENTS: [&str; 10] = [
    "gnome-shell",
    "polkit-gnome-au",
    "polkit-kde-auth",
    "polkit-mate-aut",
    "xfce-polkit",
    "lxpolkit",
    "lxqt-policykit-",
    "hyprpolkitagent",
    "soteria",
    "cinnamon",
];

/// Whether an agent runs, since polkit has no call that lists them; the key cannot ask the person without one.
fn polkit_agent() -> Option<bool> {
    if !cfg!(target_os = "linux") {
        return None;
    }
    let processes = std::fs::read_dir("/proc").ok()?;
    let running = processes.flatten().any(|entry| {
        std::fs::read_to_string(entry.path().join("comm"))
            .is_ok_and(|name| is_polkit_agent(name.trim()))
    });
    Some(running)
}

fn is_polkit_agent(name: &str) -> bool {
    POLKIT_AGENTS.contains(&name)
        || name.contains("polkit-agent")
        || name.contains("authentication-agent")
}

/// Where each editor keeps its extensions under the home folder: VS Code, Cursor and Windsurf as on the Mac,
/// and on Linux VSCodium and the Flatpak VS Code as well.
fn extension_folders() -> Vec<&'static str> {
    let mut folders = vec![
        ".vscode/extensions",
        ".cursor/extensions",
        ".windsurf/extensions",
    ];
    if cfg!(target_os = "linux") {
        folders.extend([
            ".vscode-oss/extensions",
            ".var/app/com.visualstudio.code/data/vscode/extensions",
        ]);
    }
    folders
}

/// The folder the extension installs as, followed by its version.
const EXTENSION_PREFIX: &str = "memnox.memnox-terminals-";

/// The editors here and those the extension landed in; installing it is the daemon's job, so this only looks.
fn editors() -> Editors {
    let home = if cfg!(windows) {
        std::env::var("USERPROFILE")
    } else {
        std::env::var("HOME")
    };
    let Ok(home) = home else {
        return Editors {
            present: false,
            with_extension: Vec::new(),
        };
    };
    let home = std::path::Path::new(&home);
    let folders = extension_folders();
    let present = folders.iter().any(|folder| home.join(folder).exists());
    let with_extension = folders
        .into_iter()
        .filter(|folder| {
            std::fs::read_dir(home.join(folder)).is_ok_and(|names| {
                names.flatten().any(|name| {
                    name.file_name()
                        .to_string_lossy()
                        .starts_with(EXTENSION_PREFIX)
                })
            })
        })
        .map(String::from)
        .collect();
    Editors {
        present,
        with_extension,
    }
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
        "microphone" | "sound" => vec![
            "gnome-control-center sound",
            "systemsettings kcm_pulseaudio",
        ],
        _ => vec!["gnome-control-center privacy", "systemsettings"],
    }
}

/// Runs one fixed line from the table above, never anything the webview wrote.
fn run(line: &str) -> bool {
    let mut words = line.split_whitespace();
    let Some(program) = words.next() else {
        return false;
    };
    std::process::Command::new(program)
        .args(words)
        .spawn()
        .is_ok()
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
    command
        .spawn()
        .map(|_| ())
        .map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_pane_never_runs_more_than_its_fixed_lines() {
        for pane in ["microphone", "sound", "typing", "screen", "rm -rf /"] {
            for page in privacy_pages(pane) {
                assert!(
                    page.starts_with("ms-settings:")
                        || page.starts_with("gnome-control-center")
                        || page.starts_with("systemsettings")
                );
            }
        }
    }

    #[test]
    fn knows_the_polkit_agents_by_the_names_they_run_under() {
        assert!(is_polkit_agent("polkit-kde-auth"));
        assert!(is_polkit_agent("gnome-shell"));
        assert!(!is_polkit_agent("bash"));
    }

    #[test]
    fn something_that_is_not_a_link_is_not_opened() {
        assert!(open_with_system("not a link").is_err());
    }
}
