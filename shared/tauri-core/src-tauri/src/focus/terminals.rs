//! Terminals driven only through their own documented command lines: `wezterm cli list`,
//! `activate-pane` and `spawn`; kitty's remote control, `kitty @ ls`, `focus-window` and `launch`, only
//! where the person turned it on; and Windows Terminal's `wt new-tab`. The core chooses the pane with
//! TabMatch from what these list, so nothing here reads a screen or raises a window by itself.

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use super::plan::{encoded_command, one_line, stay_open, Shown};
use super::process::{command, run, Failure, CLI_WAIT};

/// One pane as its terminal listed it, with an id only that terminal reads back.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Pane {
    pub id: String,
    pub title: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cwd: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tty: Option<String>,
    /// The programs in front in it, by their command, where the terminal says.
    pub programs: Vec<String>,
}

/// The terminals whose own command line lists, focuses or opens a tab.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Terminal {
    WezTerm,
    Kitty,
    /// Windows Terminal, by its command.
    Wt,
}

/// Said when Windows Terminal is asked for its tabs, since `wt` can focus a tab only by an index it never lists.
const WT_CANNOT_LIST: &str =
    "Windows Terminal cannot list its tabs to another app, so which tab is the session's cannot be told";
/// Said when kitty's remote control is off or kitty listens nowhere this computer can find.
const KITTY_OFF: &str =
    "kitty's remote control is off, so it needs allow_remote_control and listen_on in kitty.conf";

impl Terminal {
    /// By the core's own word for it.
    pub fn named(name: &str) -> Option<Self> {
        match name {
            "wezterm" => Some(Self::WezTerm),
            "kitty" => Some(Self::Kitty),
            "windows-terminal" => Some(Self::Wt),
            _ => None,
        }
    }

    fn title(self) -> &'static str {
        match self {
            Self::WezTerm => "WezTerm",
            Self::Kitty => "kitty",
            Self::Wt => "Windows Terminal",
        }
    }

    /// Whether it opens a tab without bringing its window forward, so Stay where I am keeps the person's window.
    fn opens_behind(self) -> bool {
        matches!(self, Self::WezTerm | Self::Kitty)
    }

    /// The ones that run on this system, in the order a launch tries them when the runtime named none.
    fn here() -> &'static [Terminal] {
        if cfg!(windows) {
            &[Self::WezTerm, Self::Wt]
        } else {
            &[Self::WezTerm, Self::Kitty]
        }
    }
}

pub fn panes(terminal: Terminal) -> Result<Vec<Pane>, String> {
    match terminal {
        Terminal::WezTerm => {
            let mut list = command("wezterm");
            list.args(["cli", "list", "--format", "json"]);
            let out = run(list, CLI_WAIT).map_err(|failure| failure.said("WezTerm"))?;
            wezterm_panes(&out).ok_or_else(|| "WezTerm listed its tabs in a way Memnox could not read".into())
        }
        Terminal::Kitty => {
            let sockets = kitty_sockets()?;
            let mut all = Vec::new();
            let mut last = None;
            for socket in sockets {
                let mut list = command("kitty");
                list.args(["@", "--to", &socket, "ls"]);
                match run(list, CLI_WAIT) {
                    Ok(out) => all.extend(kitty_panes(&out, &socket).unwrap_or_default()),
                    Err(failure) => last = Some(failure.said("kitty")),
                }
            }
            if all.is_empty() {
                if let Some(why) = last {
                    return Err(why);
                }
            }
            Ok(all)
        }
        Terminal::Wt => Err(WT_CANNOT_LIST.into()),
    }
}

pub fn focus(terminal: Terminal, id: &str) -> Result<(), String> {
    match terminal {
        Terminal::WezTerm => {
            let pane = digits(id).ok_or("that is not a WezTerm pane")?;
            let mut activate = command("wezterm");
            activate.args(["cli", "activate-pane", "--pane-id", pane]);
            run(activate, CLI_WAIT).map(|_| ()).map_err(|failure| failure.said("WezTerm"))
        }
        Terminal::Kitty => {
            let (window, socket) = id.split_once(' ').ok_or("that is not a kitty window")?;
            let window = digits(window).ok_or("that is not a kitty window")?;
            let mut activate = command("kitty");
            activate.args(["@", "--to", socket, "focus-window", "--match", &format!("id:{window}")]);
            run(activate, CLI_WAIT).map(|_| ()).map_err(|failure| failure.said("kitty"))
        }
        Terminal::Wt => Err(WT_CANNOT_LIST.into()),
    }
}

/// An id made only of digits, so nothing else reaches a terminal's command line through it.
fn digits(id: &str) -> Option<&str> {
    (!id.is_empty() && id.chars().all(|character| character.is_ascii_digit())).then_some(id)
}

#[derive(Deserialize)]
struct WezPane {
    pane_id: u64,
    #[serde(default)]
    title: String,
    #[serde(default)]
    cwd: Option<String>,
    #[serde(default)]
    tty_name: Option<String>,
}

/// `wezterm cli list --format json`: every pane with its folder as a `file://` link and, on Linux, its device.
fn wezterm_panes(json: &str) -> Option<Vec<Pane>> {
    let listed: Vec<WezPane> = serde_json::from_str(json).ok()?;
    Some(
        listed
            .into_iter()
            .map(|pane| Pane {
                id: pane.pane_id.to_string(),
                title: pane.title,
                cwd: pane.cwd.filter(|cwd| !cwd.is_empty()),
                tty: pane.tty_name.filter(|tty| !tty.is_empty()),
                programs: Vec::new(),
            })
            .collect(),
    )
}

#[derive(Deserialize)]
struct KittyOsWindow {
    #[serde(default)]
    tabs: Vec<KittyTab>,
}

#[derive(Deserialize)]
struct KittyTab {
    #[serde(default)]
    windows: Vec<KittyWindow>,
}

#[derive(Deserialize)]
struct KittyWindow {
    id: u64,
    #[serde(default)]
    title: String,
    #[serde(default)]
    cwd: Option<String>,
    #[serde(default)]
    foreground_processes: Vec<KittyProcess>,
}

#[derive(Deserialize)]
struct KittyProcess {
    #[serde(default)]
    cmdline: Vec<String>,
}

/// `kitty @ ls`: every window of every tab, with its folder and the programs in front in it, each id
/// carrying the socket it was listed on, since two kittys number their windows alike.
fn kitty_panes(json: &str, socket: &str) -> Option<Vec<Pane>> {
    let listed: Vec<KittyOsWindow> = serde_json::from_str(json).ok()?;
    Some(
        listed
            .into_iter()
            .flat_map(|os| os.tabs)
            .flat_map(|tab| tab.windows)
            .map(|window| Pane {
                id: format!("{} {socket}", window.id),
                title: window.title,
                cwd: window.cwd.filter(|cwd| !cwd.is_empty()),
                tty: None,
                programs: window
                    .foreground_processes
                    .into_iter()
                    .filter_map(|process| process.cmdline.into_iter().next())
                    .collect(),
            })
            .collect(),
    )
}

/// What kitty.conf says about remote control: whether it is on, and where kitty listens.
#[derive(Debug, Default, PartialEq, Eq)]
struct KittyConf {
    allowed: bool,
    listen_on: Option<String>,
}

/// The two settings remote control needs, read from kitty.conf; the last line of each wins, as kitty reads it.
fn kitty_conf(text: &str) -> KittyConf {
    let mut conf = KittyConf::default();
    for line in text.lines() {
        let mut words = line.trim().splitn(2, char::is_whitespace);
        let (Some(key), Some(value)) = (words.next(), words.next().map(str::trim)) else {
            continue;
        };
        match key {
            "allow_remote_control" => conf.allowed = matches!(value, "yes" | "y" | "true" | "socket" | "socket-only" | "password"),
            "listen_on" => conf.listen_on = Some(value.to_string()),
            _ => {}
        }
    }
    conf
}

/// kitty.conf where kitty looks for it first.
fn kitty_conf_path() -> Option<PathBuf> {
    if let Some(folder) = std::env::var_os("KITTY_CONFIG_DIRECTORY").filter(|folder| !folder.is_empty()) {
        return Some(PathBuf::from(folder).join("kitty.conf"));
    }
    let config = std::env::var_os("XDG_CONFIG_HOME")
        .filter(|folder| !folder.is_empty())
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))?;
    Some(config.join("kitty").join("kitty.conf"))
}

/// `~` and `$NAME` or `${NAME}` written out, as kitty expands them in listen_on.
fn expanded(value: &str, variable: impl Fn(&str) -> Option<String>) -> String {
    let value = match value.strip_prefix('~') {
        Some(rest) => format!("{}{rest}", variable("HOME").unwrap_or_default()),
        None => value.to_string(),
    };
    let mut out = String::new();
    let mut characters = value.chars().peekable();
    while let Some(character) = characters.next() {
        if character != '$' {
            out.push(character);
            continue;
        }
        let braced = characters.peek() == Some(&'{');
        if braced {
            characters.next();
        }
        let mut name = String::new();
        while let Some(&next) = characters.peek() {
            if next.is_ascii_alphanumeric() || next == '_' {
                name.push(next);
                characters.next();
            } else {
                break;
            }
        }
        if braced && characters.peek() == Some(&'}') {
            characters.next();
        }
        out.push_str(&variable(&name).unwrap_or_default());
    }
    out
}

/// The addresses a running kitty answers on. kitty adds `-PID` to a socket's name, or puts it where the
/// name says `{kitty_pid}`, so one listen_on becomes one socket per running kitty.
fn kitty_sockets() -> Result<Vec<String>, String> {
    if let Some(address) = std::env::var("KITTY_LISTEN_ON").ok().filter(|address| !address.is_empty()) {
        return Ok(vec![address]);
    }
    let conf = kitty_conf_path()
        .and_then(|path| std::fs::read_to_string(path).ok())
        .map(|text| kitty_conf(&text))
        .unwrap_or_default();
    let Some(listen_on) = conf.listen_on.filter(|_| conf.allowed) else {
        return Err(KITTY_OFF.into());
    };
    let listen_on = expanded(&listen_on, |name| std::env::var(name).ok());
    let sockets = if let Some(name) = listen_on.strip_prefix("unix:@") {
        let table = std::fs::read_to_string("/proc/net/unix").unwrap_or_default();
        abstract_sockets(&table, name)
    } else if let Some(path) = listen_on.strip_prefix("unix:") {
        path_sockets(Path::new(path))
    } else {
        vec![listen_on]
    };
    if sockets.is_empty() {
        return Err("kitty is not running, or not listening where kitty.conf says".into());
    }
    Ok(sockets)
}

/// Whether a socket's name is the configured one as kitty made it for some running kitty.
fn names_kitty(file: &str, configured: &str) -> bool {
    if let Some((before, after)) = configured.split_once("{kitty_pid}") {
        return file
            .strip_prefix(before)
            .and_then(|rest| rest.strip_suffix(after))
            .is_some_and(|pid| digits(pid).is_some());
    }
    file == configured || file.strip_prefix(configured).and_then(|rest| rest.strip_prefix('-')).is_some_and(|pid| digits(pid).is_some())
}

fn path_sockets(path: &Path) -> Vec<String> {
    let (Some(folder), Some(name)) = (path.parent(), path.file_name().and_then(|name| name.to_str())) else {
        return Vec::new();
    };
    let mut found: Vec<String> = std::fs::read_dir(folder)
        .map(|entries| {
            entries
                .flatten()
                .filter(|entry| names_kitty(&entry.file_name().to_string_lossy(), name))
                .map(|entry| format!("unix:{}", entry.path().display()))
                .collect()
        })
        .unwrap_or_default();
    found.sort();
    found
}

/// Linux's abstract sockets, read from `/proc/net/unix`, where the path is the last column after an `@`.
fn abstract_sockets(table: &str, name: &str) -> Vec<String> {
    let mut found: Vec<String> = table
        .lines()
        .filter_map(|line| line.split_whitespace().last()?.strip_prefix('@'))
        .filter(|socket| names_kitty(socket, name))
        .map(|socket| format!("unix:@{socket}"))
        .collect();
    found.sort();
    found.dedup();
    found
}

/// A POSIX shell to run the runtime's line in, the person's own where it reads `-c` as POSIX does.
fn posix_shell() -> String {
    let shell = std::env::var("SHELL").unwrap_or_default();
    let name = shell.rsplit('/').next().unwrap_or("");
    if matches!(name, "bash" | "zsh" | "sh" | "dash" | "ksh" | "mksh") {
        shell
    } else {
        "/bin/sh".into()
    }
}

/// PowerShell 7 where it is installed, since the runtime's line joins its steps with `&&`, which
/// Windows PowerShell 5 does not read.
fn powershell() -> &'static str {
    let found = std::env::var_os("PATH")
        .map(|path| std::env::split_paths(&path).any(|folder| folder.join("pwsh.exe").is_file()))
        .unwrap_or(false);
    if found {
        "pwsh"
    } else {
        "powershell"
    }
}

/// The program and its arguments that run the runtime's line in a new tab and keep the tab open after,
/// with the line passed whole, so no terminal's own parsing reaches inside it.
fn shell_for(line: &str, windows: bool) -> Vec<String> {
    let line = one_line(line);
    if windows {
        vec![powershell().into(), "-NoExit".into(), "-EncodedCommand".into(), encoded_command(&line)]
    } else {
        vec![posix_shell(), "-l".into(), "-c".into(), stay_open(&line)]
    }
}

/// The command that opens a new tab in one terminal, in the folder, running the shell given.
fn launch_command(terminal: Terminal, folder: &str, shell: &[String], background: bool) -> Result<(String, Vec<String>), String> {
    let mut args: Vec<String> = Vec::new();
    let program = match terminal {
        Terminal::WezTerm => {
            args.extend(["cli", "spawn", "--cwd", folder, "--"].map(String::from));
            "wezterm"
        }
        Terminal::Kitty => {
            let socket = kitty_sockets()?.into_iter().next().ok_or(KITTY_OFF)?;
            args.extend(["@".to_string(), "--to".into(), socket, "launch".into(), "--type=tab".into(), format!("--cwd={folder}")]);
            // kitty opens the tab behind the one in front, so the person's own tab keeps the keyboard.
            if background {
                args.push("--keep-focus".into());
            }
            "kitty"
        }
        Terminal::Wt => {
            // wt reads a `;` anywhere in its arguments as the start of another command.
            if folder.contains(';') {
                return Err("the folder's name has a semicolon in it, which Windows Terminal reads as a second command".into());
            }
            args.extend(["-w", "0", "new-tab", "-d", folder].map(String::from));
            "wt"
        }
    };
    args.extend(shell.iter().cloned());
    Ok((program.into(), args))
}

/// A new tab running the runtime's line exactly as it was sent: in the terminal named, or else the first
/// supported one here that opens it. With `background`, only a terminal that opens a tab behind is used.
pub fn launch(terminal: Option<Terminal>, line: &str, folder: &str, background: bool) -> Shown {
    if !Path::new(folder).is_dir() {
        return Shown::failed("the repository folder is not there");
    }
    let named = terminal.is_some();
    let asked: Vec<Terminal> = match terminal {
        Some(terminal) => vec![terminal],
        None => Terminal::here().to_vec(),
    };
    let shell = shell_for(line, cfg!(windows));
    let mut reasons = Vec::new();
    for terminal in asked {
        if background && !terminal.opens_behind() {
            reasons.push(format!(
                "Stay where I am is on, and {} brings its window forward to open a tab, so nothing was started",
                terminal.title()
            ));
            continue;
        }
        if terminal == Terminal::Kitty && cfg!(windows) {
            continue;
        }
        let (program, args) = match launch_command(terminal, folder, &shell, background) {
            Ok(built) => built,
            Err(why) => {
                reasons.push(why);
                continue;
            }
        };
        let mut start = command(&program);
        start.args(&args);
        match run(start, CLI_WAIT) {
            Ok(_) => return Shown::done(),
            // One not installed says nothing worth repeating unless the runtime named it.
            Err(Failure::Missing) if !named => continue,
            Err(failure) => reasons.push(failure.said(terminal.title())),
        }
    }
    Shown::failed(reasons.into_iter().next().unwrap_or_else(|| {
        if cfg!(windows) {
            "neither WezTerm nor Windows Terminal is here to open a tab in".into()
        } else {
            "no terminal here opens a tab for Memnox; WezTerm does, and so does kitty with remote control on".into()
        }
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_wezterms_listing() {
        let json = r#"[{"window_id":0,"tab_id":1,"pane_id":7,"workspace":"default","title":"claude","cwd":"file://box/home/a/shop","is_active":true,"tty_name":"/dev/pts/3"},
                      {"window_id":0,"tab_id":2,"pane_id":8,"title":"zsh","cwd":"","tty_name":null}]"#;
        let panes = wezterm_panes(json).unwrap();
        assert_eq!(panes[0].id, "7");
        assert_eq!(panes[0].cwd.as_deref(), Some("file://box/home/a/shop"));
        assert_eq!(panes[0].tty.as_deref(), Some("/dev/pts/3"));
        assert_eq!(panes[1].cwd, None);
        assert_eq!(wezterm_panes("not json"), None);
    }

    #[test]
    fn reads_kittys_listing_with_its_socket_in_each_id() {
        let json = r#"[{"id":1,"tabs":[{"id":2,"title":"t","windows":[{"id":3,"title":"Fix the login","cwd":"/home/a/shop",
            "foreground_processes":[{"pid":9,"cwd":"/home/a/shop","cmdline":["/home/a/.local/bin/claude","--resume"]}]}]}]}]"#;
        let panes = kitty_panes(json, "unix:/tmp/kitty-12").unwrap();
        assert_eq!(panes[0].id, "3 unix:/tmp/kitty-12");
        assert_eq!(panes[0].programs, vec!["/home/a/.local/bin/claude".to_string()]);
    }

    #[test]
    fn needs_remote_control_on_to_reach_kitty() {
        assert_eq!(
            kitty_conf("# a comment\nallow_remote_control yes\nlisten_on unix:/tmp/kitty\n"),
            KittyConf { allowed: true, listen_on: Some("unix:/tmp/kitty".into()) }
        );
        assert!(!kitty_conf("allow_remote_control yes\nallow_remote_control no\n").allowed);
        assert!(names_kitty("kitty-1234", "kitty"));
        assert!(names_kitty("kitty", "kitty"));
        assert!(!names_kitty("kitty-x", "kitty"));
        assert!(names_kitty("mykitty-55.sock", "mykitty-{kitty_pid}.sock"));
        let table = "Num RefCount Protocol Flags Type St Inode Path\n0: 2 0 10000 1 1 99 @mykitty-41\n0: 2 0 10000 1 1 98 /run/other\n";
        assert_eq!(abstract_sockets(table, "mykitty"), vec!["unix:@mykitty-41".to_string()]);
        let home = |name: &str| (name == "HOME" || name == "XDG_RUNTIME_DIR").then(|| "/home/a".to_string());
        assert_eq!(expanded("unix:${XDG_RUNTIME_DIR}/kitty", home), "unix:/home/a/kitty");
    }

    #[test]
    fn passes_the_runtimes_line_whole_to_the_new_tab() {
        let windows = shell_for("cd 'C:\\a' && memnox run claude 'fix; it'", true);
        assert_eq!(windows[1..3], ["-NoExit".to_string(), "-EncodedCommand".to_string()]);
        assert!(!windows[3].contains(';'));
        let posix = shell_for("cd '/a' &&\nmemnox run claude", false);
        assert_eq!(posix[1..3], ["-l".to_string(), "-c".to_string()]);
        assert_eq!(posix[3], "cd '/a' && memnox run claude; exec \"${SHELL:-sh}\"");
        let (program, args) = launch_command(Terminal::WezTerm, "/a", &posix, true).unwrap();
        assert_eq!(program, "wezterm");
        assert_eq!(args[..5], ["cli", "spawn", "--cwd", "/a", "--"].map(String::from));
        let (program, args) = launch_command(Terminal::Wt, "C:\\a", &windows, false).unwrap();
        assert_eq!(program, "wt");
        assert_eq!(args[..5], ["-w", "0", "new-tab", "-d", "C:\\a"].map(String::from));
        assert!(launch_command(Terminal::Wt, "C:\\a;b", &windows, false).is_err());
    }

    #[test]
    fn touches_only_a_pane_id_made_of_digits() {
        assert!(focus(Terminal::WezTerm, "7; rm").is_err());
        assert!(focus(Terminal::Kitty, "x unix:/tmp/k").is_err());
        assert!(panes(Terminal::Wt).is_err());
    }
}
