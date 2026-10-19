//! An editor's own window, terminals and agent panel, reached the way the Mac reaches them: the editor
//! opened on the session's folder by its own command line, which brings forward the window already on
//! it, then the Memnox extension's link, whose answer the extension writes beside the runtime's request,
//! since only it knows which of the editor's terminals holds the session.

use std::path::{Path, PathBuf};
use std::time::Duration;

use serde::Deserialize;

use super::plan::{
    conversation_link, encoded, extension_device, is_app_link, is_conversation_id, link, Editor,
    Host, Shown,
};
use super::process::{command, open_url, run, Failure, EDITOR_WAIT};

/// The Memnox extension's link host, and the start of its installed folder's name before the version.
const EXTENSION_HOST: &str = "memnox.memnox-terminals";
const EXTENSION_FOLDER: &str = "memnox.memnox-terminals-";
/// Where the runtime writes each display request, and the extension its answer on it.
const DISPLAYS: &str = ".memnox/displays";

/// How often the request is read while the extension acts on it.
const POLL: Duration = Duration::from_millis(100);
/// Long enough for a few sentences a key at a time, short of the runtime's own wait.
const ATTEMPTS: u32 = 200;
/// How often an unanswered link is sent again, since a window still starting drops the first.
const RESEND_EVERY: u32 = 30;
/// A moment for the editor's window to come forward before the link reaches it.
const SETTLE: Duration = Duration::from_millis(200);
/// Between opening the editor and its links, so a window just opened has its extensions running.
const APP_SETTLE: Duration = Duration::from_millis(1500);

/// Said when the extension never wrote back, which a window still on an older copy does.
const SILENT: &str =
    "the Memnox extension did not answer, so its editor window may need its extensions restarted";
/// What the extension says when no terminal in the editor holds the device.
const NO_TERMINAL: &str = "no integrated terminal holds its device";

/// The home folder, where both the editors' extensions and the runtime's displays live.
fn home() -> Option<PathBuf> {
    std::env::var_os(if cfg!(windows) { "USERPROFILE" } else { "HOME" })
        .filter(|home| !home.is_empty())
        .map(PathBuf::from)
}

/// Whether the editor has the Memnox extension, read from its extensions folder, since a link nothing
/// handles makes the editor offer to search its marketplace. A copy uninstalled since the editor started
/// stays on disk until it restarts, listed in `.obsolete`, and is never loaded.
fn has_extension(editor: Editor) -> bool {
    let Some(folder) = home().map(|home| home.join(editor.folder()).join("extensions")) else {
        return false;
    };
    installed_in(&folder)
}

fn installed_in(folder: &Path) -> bool {
    let removed: std::collections::HashMap<String, bool> = std::fs::read(folder.join(".obsolete"))
        .ok()
        .and_then(|bytes| serde_json::from_slice(&bytes).ok())
        .unwrap_or_default();
    std::fs::read_dir(folder)
        .map(|entries| {
            entries.flatten().any(|entry| {
                let name = entry.file_name().to_string_lossy().to_string();
                name.starts_with(EXTENSION_FOLDER) && removed.get(&name) != Some(&true)
            })
        })
        .unwrap_or(false)
}

/// The Memnox extension's link for one action, only where that editor has it installed.
fn extension_link(editor: Editor, path: &str, query: &[(&str, &str)]) -> Option<String> {
    has_extension(editor).then(|| link(editor.scheme(), EXTENSION_HOST, path, query))
}

/// The editor opened on a folder by its own command line, which brings forward the window already on it
/// or opens one. Never `--reuse-window`, which would put the folder in whatever window was last used.
fn open_folder(editor: Editor, folder: &str) -> Result<(), String> {
    let mut opener = command(editor.command());
    opener.arg(folder);
    match run(opener, EDITOR_WAIT) {
        Ok(_) => Ok(()),
        // Its command line is not on the path, so the editor's own link opens the folder instead.
        Err(Failure::Missing) => open_url(&file_link(editor, folder)).map_err(|_| {
            format!(
                "{} is not installed here, or its command line is not on the path",
                editor.title()
            )
        }),
        Err(failure) => Err(failure.said(editor.title())),
    }
}

/// The editor's own `file` link to a folder, each part of the path written safely.
fn file_link(editor: Editor, folder: &str) -> String {
    let path: Vec<String> = folder
        .replace('\\', "/")
        .trim_start_matches('/')
        .split('/')
        // A drive's colon stays, as the editor reads `C:/Users`.
        .map(|part| encoded(part).replace("%3A", ":"))
        .collect();
    format!("{}://file/{}", editor.scheme(), path.join("/"))
}

/// The exact conversation through its Claude Code link where the session has no terminal, else the editor
/// on its folder and, where the Memnox extension reads the device, the terminal in it.
pub fn focus(host: &Host) -> Shown {
    let Some(editor) = host.editor() else {
        return Shown::failed("it does not run in an editor Memnox reaches");
    };
    // A session with a terminal runs in one of the editor's terminals, never in the agent panel, and only
    // the agent's own id opens its conversation; any other id makes the panel start a new one.
    if host.tty.is_none() {
        if let Some(conversation) = host
            .conversation
            .as_deref()
            .filter(|id| is_conversation_id(id))
        {
            if open_url(&conversation_link(editor, conversation)).is_ok() {
                return Shown::done();
            }
        }
    }
    let Some(folder) = host
        .cwd
        .as_deref()
        .filter(|folder| Path::new(folder).is_dir())
    else {
        return Shown::failed(format!(
            "its folder was never noted, so {} has no window to bring forward",
            editor.title()
        ));
    };
    if let Err(why) = open_folder(editor, folder) {
        return Shown::failed(why);
    }
    // Then the terminal inside it, which only the Memnox extension can choose among several.
    if let Some(device) = host.tty.as_deref().and_then(extension_device) {
        if let Some(link) = extension_link(editor, "/terminal", &[("tty", &device)]) {
            std::thread::sleep(SETTLE);
            let _ = open_url(&link);
        }
    }
    Shown::done()
}

/// The editor's window on the repository comes forward, then the Memnox extension there opens a new
/// terminal and types the line, read from the request rather than the link.
pub fn launch(editor: Editor, folder: &str, request: &str) -> Shown {
    if !Path::new(folder).is_dir() {
        return Shown::failed("the repository folder is not there");
    }
    let Some(link) = extension_link(editor, "/launch", &[("request", request)]) else {
        return Shown::failed(format!(
            "the Memnox extension is not in {} yet, which the daemon puts in as it starts",
            editor.title()
        ));
    };
    if let Err(why) = open_folder(editor, folder) {
        return Shown::failed(why);
    }
    // A window just opened is still starting its extensions, and a link sent sooner is lost, so it is sent again until answered.
    std::thread::sleep(APP_SETTLE);
    if open_url(&link).is_err() {
        return Shown::failed(format!("{} would not take the Memnox link", editor.title()));
    }
    delivery(request, &link)
}

/// An agent app's own links, a moment apart, so each reaches the window the one before it opened.
pub fn open_app_links(links: &[String]) -> Shown {
    if links.is_empty() || !links.iter().all(|each| is_app_link(each)) {
        return Shown::failed("it has no link of its own this computer may open");
    }
    for (index, each) in links.iter().enumerate() {
        if index > 0 {
            std::thread::sleep(APP_SETTLE);
        }
        if open_url(each).is_err() {
            return Shown::failed("its app did not answer its link, so it may not be installed");
        }
    }
    Shown::done()
}

#[derive(Deserialize)]
struct Delivered {
    outcome: String,
    #[serde(default)]
    reason: Option<serde_json::Value>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Record {
    delivered: Option<Delivered>,
    no_terminal: Option<bool>,
    claimed_by: Option<serde_json::Value>,
}

/// Only an id the runtime makes is read, so the path never leaves the displays folder.
fn is_request_id(request: &str) -> bool {
    !request.is_empty()
        && request.chars().all(|character| {
            character.is_ascii_alphanumeric() || character == '_' || character == '-'
        })
}

/// What one read of the request says: answered, or still waiting.
fn answered(bytes: &[u8]) -> Option<Shown> {
    let record: Record = serde_json::from_slice(bytes).ok()?;
    if let Some(delivered) = record.delivered {
        return Some(if delivered.outcome == "typed" {
            Shown::done()
        } else {
            let reason = delivered
                .reason
                .and_then(|reason| reason.as_str().map(str::to_string))
                .unwrap_or_else(|| "the extension could not do it".into());
            Shown::failed(reason)
        });
    }
    // A window holding the terminal claimed it, so it is acting there whatever the window the link reached said.
    (record.no_terminal == Some(true) && record.claimed_by.is_none())
        .then(|| Shown::failed(NO_TERMINAL))
}

/// What the extension wrote on the request once it acted, read from the runtime's own folder, with the
/// link sent again now and then, since the extension answers a request once and a starting window drops it.
fn delivery(request: &str, link: &str) -> Shown {
    if !is_request_id(request) {
        return Shown::failed("the request has no id the extension could answer");
    }
    let Some(file) = home().map(|home| home.join(DISPLAYS).join(format!("{request}.json"))) else {
        return Shown::failed("the home folder is not known");
    };
    for attempt in 0..ATTEMPTS {
        if attempt > 0 && attempt % RESEND_EVERY == 0 {
            let _ = open_url(link);
        }
        if let Some(shown) = std::fs::read(&file).ok().and_then(|bytes| answered(&bytes)) {
            return shown;
        }
        std::thread::sleep(POLL);
    }
    Shown::failed(SILENT)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_the_extensions_answer_on_the_request() {
        assert_eq!(
            answered(br#"{"delivered":{"outcome":"typed","at":"x"}}"#),
            Some(Shown::done())
        );
        assert_eq!(
            answered(br#"{"delivered":{"outcome":"failed","reason":"no agent is in front in its terminal"}}"#),
            Some(Shown::failed("no agent is in front in its terminal"))
        );
        assert_eq!(
            answered(br#"{"noTerminal":true}"#),
            Some(Shown::failed(NO_TERMINAL))
        );
        assert_eq!(answered(br#"{"noTerminal":true,"claimedBy":42}"#), None);
        assert_eq!(
            answered(br#"{"line":"cd '/a' && memnox run claude"}"#),
            None
        );
        assert_eq!(answered(b"half a fi"), None);
    }

    #[test]
    fn reads_only_a_request_id_the_runtime_makes() {
        assert!(is_request_id("dsp_12-ab"));
        assert!(!is_request_id("../secrets"));
        assert!(!is_request_id(""));
    }

    #[test]
    fn finds_an_installed_extension_but_not_an_uninstalled_one() {
        let folder = std::env::temp_dir().join(format!("memnox-extensions-{}", std::process::id()));
        std::fs::create_dir_all(folder.join("memnox.memnox-terminals-1.0.0")).unwrap();
        assert!(installed_in(&folder));
        std::fs::write(
            folder.join(".obsolete"),
            br#"{"memnox.memnox-terminals-1.0.0":true}"#,
        )
        .unwrap();
        assert!(!installed_in(&folder));
        std::fs::remove_dir_all(&folder).unwrap();
    }

    #[test]
    fn writes_a_folder_as_the_editors_own_link() {
        assert_eq!(
            file_link(Editor::Code, "/home/a/my shop"),
            "vscode://file/home/a/my%20shop"
        );
        assert_eq!(
            file_link(Editor::Cursor, "C:\\Users\\a"),
            "cursor://file/C:/Users/a"
        );
    }

    #[test]
    fn opens_no_link_that_is_not_an_agent_apps() {
        assert_eq!(
            open_app_links(&["https://example.com".into()]).answer,
            "failed"
        );
        assert_eq!(open_app_links(&[]).answer, "failed");
    }
}
