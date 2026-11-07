//! Where the person runs their agents, as the Mac's `AgentHomes`: the terminals and the editor installed here,
//! found on the PATH, and a session started in the one they picked. Windows Terminal and kitty open a tab
//! through their own command lines in `terminals.rs`; the rest open a window of their own with the runtime's
//! line passed whole, so nothing here presses a key in another app or reads its screen.

use std::path::{Path, PathBuf};
use std::process::Stdio;

use serde::Serialize;

use super::editor::{has_extension_named, EXTENSION_FOLDER};
use super::plan::{encoded_command, Editor, Shown};
use super::process::command;
use super::terminals::{self, shell_for, Terminal};

/// Claude Code's extension folder, which the chat row reads as the Mac's does.
const CLAUDE_CODE_FOLDER: &str = "anthropic.claude-code-";

/// The characters cmd reads as a second command or a variable, which no folder handed to `start` may carry.
const CMD_SPECIAL: &[char] = &['&', '|', '<', '>', '^', '%', '!', '"'];

/// An app a session may open in, by the core's own word for it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Home {
    WindowsTerminal,
    PowerShell,
    Cmd,
    GnomeTerminal,
    Konsole,
    Kitty,
    Alacritty,
    Xterm,
    VsCode,
}

impl Home {
    pub fn named(name: &str) -> Option<Self> {
        Self::all(true)
            .iter()
            .chain(Self::all(false))
            .copied()
            .find(|home| home.id() == name)
    }

    fn id(self) -> &'static str {
        match self {
            Self::WindowsTerminal => "windows-terminal",
            Self::PowerShell => "powershell",
            Self::Cmd => "cmd",
            Self::GnomeTerminal => "gnome-terminal",
            Self::Konsole => "konsole",
            Self::Kitty => "kitty",
            Self::Alacritty => "alacritty",
            Self::Xterm => "xterm",
            Self::VsCode => "vscode",
        }
    }

    fn title(self) -> &'static str {
        match self {
            Self::WindowsTerminal => "Windows Terminal",
            Self::PowerShell => "PowerShell",
            Self::Cmd => "Command Prompt",
            Self::GnomeTerminal => "GNOME Terminal",
            Self::Konsole => "Konsole",
            Self::Kitty => "kitty",
            Self::Alacritty => "Alacritty",
            Self::Xterm => "xterm",
            Self::VsCode => "VS Code",
        }
    }

    /// The ones this system has, in the order the picker shows them.
    fn all(windows: bool) -> &'static [Home] {
        if windows {
            &[
                Self::WindowsTerminal,
                Self::PowerShell,
                Self::Cmd,
                Self::VsCode,
            ]
        } else {
            &[
                Self::GnomeTerminal,
                Self::Konsole,
                Self::Kitty,
                Self::Alacritty,
                Self::Xterm,
                Self::VsCode,
            ]
        }
    }

    /// The program the PATH is searched for; cmd and Windows PowerShell ship with Windows itself.
    fn program(self) -> &'static str {
        match self {
            Self::WindowsTerminal => "wt",
            Self::PowerShell => "powershell",
            Self::Cmd => "cmd",
            Self::GnomeTerminal => "gnome-terminal",
            Self::Konsole => "konsole",
            Self::Kitty => "kitty",
            Self::Alacritty => "alacritty",
            Self::Xterm => "xterm",
            Self::VsCode => "code",
        }
    }
}

/// One app found here, with the editor's two checks where it is the editor.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Found {
    pub kind: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub memnox_extension: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub claude_code: Option<bool>,
}

/// The apps here a session may open in, each found by whether its program is on the PATH.
fn installed(windows: bool, here: impl Fn(&str) -> bool) -> Vec<Home> {
    Home::all(windows)
        .iter()
        .copied()
        .filter(|home| here(home.program()))
        .collect()
}

/// Whether a program is on the PATH, as a shell would find it; on Windows by its .exe or .cmd too.
fn on_path(program: &str) -> bool {
    let Some(path) = std::env::var_os("PATH") else {
        return false;
    };
    let names: Vec<String> = if cfg!(windows) {
        vec![format!("{program}.exe"), format!("{program}.cmd")]
    } else {
        vec![program.to_string()]
    };
    std::env::split_paths(&path).any(|folder| names.iter().any(|name| folder.join(name).is_file()))
        || vs_code_beside(program)
}

/// VS Code installed for one person on Windows puts its command under LOCALAPPDATA, which a PATH set
/// before the install does not name yet.
fn vs_code_beside(program: &str) -> bool {
    if !cfg!(windows) || program != Home::VsCode.program() {
        return false;
    }
    std::env::var_os("LOCALAPPDATA")
        .map(PathBuf::from)
        .is_some_and(|local| {
            local
                .join("Programs")
                .join("Microsoft VS Code")
                .join("bin")
                .join("code.cmd")
                .is_file()
        })
}

/// Every app here a session may open in, with the editor's extension checks.
pub fn found() -> Vec<Found> {
    installed(cfg!(windows), on_path)
        .into_iter()
        .map(|home| {
            let editor = home == Home::VsCode;
            Found {
                kind: home.id(),
                memnox_extension: editor
                    .then(|| has_extension_named(Editor::Code, EXTENSION_FOLDER)),
                claude_code: editor.then(|| has_extension_named(Editor::Code, CLAUDE_CODE_FOLDER)),
            }
        })
        .collect()
}

/// The program and its arguments that open a new window of the app in the folder, running the shell given.
fn window_command(
    home: Home,
    folder: &str,
    line: &str,
    windows: bool,
) -> Result<(String, Vec<String>, bool), String> {
    let shell = shell_for(line, windows);
    let mut args: Vec<String> = Vec::new();
    // Whether the folder is set as the program's own working folder, for an app with no flag of its own for it.
    let mut in_folder = false;
    let program = match home {
        Home::PowerShell | Home::Cmd => {
            if folder.contains(CMD_SPECIAL) {
                return Err(
                    "the folder's name has a character in it that cmd reads as a second command"
                        .into(),
                );
            }
            // start opens the console window; the line reaches PowerShell encoded, so cmd never parses it.
            args.extend(["/c", "start", "", "/D", folder].map(String::from));
            if home == Home::Cmd {
                args.extend(["cmd", "/K"].map(String::from));
                args.extend([
                    super::terminals::powershell().to_string(),
                    "-NoProfile".into(),
                    "-EncodedCommand".into(),
                    encoded_command(&super::plan::one_line(line)),
                ]);
            } else {
                args.extend(shell);
            }
            "cmd"
        }
        Home::GnomeTerminal => {
            args.extend([
                "--tab".to_string(),
                format!("--working-directory={folder}"),
                "--".into(),
            ]);
            args.extend(shell);
            "gnome-terminal"
        }
        Home::Konsole => {
            args.extend(["--new-tab", "--workdir", folder, "-e"].map(String::from));
            args.extend(shell);
            "konsole"
        }
        Home::Kitty => {
            args.extend(["--directory", folder].map(String::from));
            args.extend(shell);
            "kitty"
        }
        Home::Alacritty => {
            args.extend(["--working-directory", folder, "-e"].map(String::from));
            args.extend(shell);
            "alacritty"
        }
        Home::Xterm => {
            in_folder = true;
            args.push("-e".into());
            args.extend(shell);
            "xterm"
        }
        Home::WindowsTerminal | Home::VsCode => {
            return Err(format!(
                "{} opens a session through its own command line",
                home.title()
            ))
        }
    };
    Ok((program.into(), args, in_folder))
}

/// A new window of the picked app in the folder, running the runtime's line exactly as it was sent. kitty
/// opens a tab where its remote control is on, and a window of its own where it is not.
pub fn launch(home: Home, line: &str, folder: &str) -> Shown {
    if !Path::new(folder).is_dir() {
        return Shown::failed("the repository folder is not there");
    }
    match home {
        Home::WindowsTerminal => return terminals::launch(Some(Terminal::Wt), line, folder, false),
        Home::Kitty => {
            let tab = terminals::launch(Some(Terminal::Kitty), line, folder, false);
            if tab.reason.is_none() {
                return tab;
            }
        }
        _ => {}
    }
    let (program, args, in_folder) = match window_command(home, folder, line, cfg!(windows)) {
        Ok(built) => built,
        Err(why) => return Shown::failed(why),
    };
    let mut start = command(&program);
    start
        .args(&args)
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    if in_folder {
        start.current_dir(folder);
    }
    match start.spawn() {
        Ok(mut child) => {
            // The window lives as long as the person keeps it, so it is waited on apart and never held.
            std::thread::spawn(move || {
                let _ = child.wait();
            });
            Shown::done()
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            Shown::failed(format!("{} is not installed here", home.title()))
        }
        Err(error) => Shown::failed(format!("{} would not open: {error}", home.title())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn offers_each_systems_own_apps_by_whether_they_are_installed() {
        let windows = installed(true, |program| program != "code");
        assert_eq!(
            windows,
            vec![Home::WindowsTerminal, Home::PowerShell, Home::Cmd]
        );
        let linux = installed(false, |program| {
            matches!(program, "konsole" | "xterm" | "code")
        });
        assert_eq!(linux, vec![Home::Konsole, Home::Xterm, Home::VsCode]);
        assert_eq!(Home::named("gnome-terminal"), Some(Home::GnomeTerminal));
        assert_eq!(Home::named("rm -rf"), None);
    }

    #[test]
    fn opens_a_window_in_the_folder_with_the_line_whole() {
        let (program, args, in_folder) =
            window_command(Home::Konsole, "/src/web", "claude 'fix it'", false).unwrap();
        assert_eq!(program, "konsole");
        assert_eq!(&args[..4], ["--new-tab", "--workdir", "/src/web", "-e"]);
        assert!(args.last().unwrap().starts_with("claude 'fix it'"));
        assert!(!in_folder);
        let (_, args, in_folder) =
            window_command(Home::Xterm, "/src/web", "claude", false).unwrap();
        assert_eq!(args[0], "-e");
        assert!(in_folder);
        let (program, args, _) =
            window_command(Home::GnomeTerminal, "/src/web", "claude", false).unwrap();
        assert_eq!(program, "gnome-terminal");
        assert_eq!(args[1], "--working-directory=/src/web");
    }

    #[test]
    fn keeps_cmd_from_reading_the_folder_or_the_line() {
        let (program, args, _) =
            window_command(Home::Cmd, "C:\\src\\web", "claude && echo", true).unwrap();
        assert_eq!(program, "cmd");
        assert_eq!(&args[..5], ["/c", "start", "", "/D", "C:\\src\\web"]);
        assert!(!args.iter().any(|arg| arg.contains("&&")));
        assert!(window_command(Home::PowerShell, "C:\\a&b", "claude", true).is_err());
    }
}
