//! The rules the session actions follow, kept free of any system call so they are tested anywhere:
//! where a session runs as the runtime noted it, which links may start another app, and how the
//! runtime's line reaches a new tab's shell untouched.

use serde::{Deserialize, Serialize};

/// Where a session runs, as the runtime's `DisplayHost` says it.
#[derive(Clone, Debug, Default, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Host {
    pub app: Option<String>,
    pub app_path: Option<String>,
    pub tty: Option<String>,
    pub cwd: Option<String>,
    /// The agent's own id for the conversation, which an editor's agent panel opens by.
    pub conversation: Option<String>,
}

impl Host {
    /// The app's name lowercased, from its name or else its path, empty when neither was noted.
    pub fn app_name(&self) -> String {
        self.app
            .as_deref()
            .or(self.app_path.as_deref())
            .unwrap_or("")
            .to_lowercase()
    }

    /// The editor it runs in, when the runtime named one.
    pub fn editor(&self) -> Option<Editor> {
        Editor::named(&self.app_name())
    }
}

/// How an action ended, in the runtime's DELIVERY words, with why when it did not.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Shown {
    pub answer: &'static str,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reason: Option<String>,
}

impl Shown {
    /// Done, though nothing read it back, so it is not known to have landed.
    pub fn done() -> Self {
        Self {
            answer: "typed",
            reason: None,
        }
    }

    pub fn failed(reason: impl Into<String>) -> Self {
        Self {
            answer: "failed",
            reason: Some(reason.into()),
        }
    }
}

/// The editors whose terminals and agent panels Memnox reaches, by the names their apps go by.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Editor {
    Code,
    Cursor,
    Windsurf,
}

impl Editor {
    /// The editor a lowercased app name, executable or the core's own word names; Cursor and Windsurf
    /// first, since both are built on Code.
    pub fn named(name: &str) -> Option<Self> {
        let program = name.rsplit(['/', '\\']).next().unwrap_or(name);
        if name.contains("cursor") {
            Some(Self::Cursor)
        } else if name.contains("windsurf") {
            Some(Self::Windsurf)
        } else if name.contains("visual studio code")
            || name.contains("vscode")
            || matches!(program, "code" | "code.exe" | "code.cmd")
            || name.starts_with("code ")
        {
            Some(Self::Code)
        } else {
            None
        }
    }

    /// Its link scheme, which the Claude Code extension and the Memnox one answer on.
    pub fn scheme(self) -> &'static str {
        match self {
            Self::Code => "vscode",
            Self::Cursor => "cursor",
            Self::Windsurf => "windsurf",
        }
    }

    /// The folder under home its extensions are installed in.
    pub fn folder(self) -> &'static str {
        match self {
            Self::Code => ".vscode",
            Self::Cursor => ".cursor",
            Self::Windsurf => ".windsurf",
        }
    }

    /// Its command line, which opens a folder or brings forward the window already on it. On Windows it
    /// is a batch file beside the editor, which Rust runs only with arguments it can pass safely.
    pub fn command(self) -> &'static str {
        match (self, cfg!(windows)) {
            (Self::Code, false) => "code",
            (Self::Cursor, false) => "cursor",
            (Self::Windsurf, false) => "windsurf",
            (Self::Code, true) => "code.cmd",
            (Self::Cursor, true) => "cursor.cmd",
            (Self::Windsurf, true) => "windsurf.cmd",
        }
    }

    /// As a person names it.
    pub fn title(self) -> &'static str {
        match self {
            Self::Code => "Visual Studio Code",
            Self::Cursor => "Cursor",
            Self::Windsurf => "Windsurf",
        }
    }
}

/// The schemes an agent's own desktop app answers on, the only links an APP display may open, as
/// `open_link` allows only web pages, so a link from the runtime never starts any other app.
const APP_SCHEMES: [&str; 5] = ["claude", "codex", "cursor", "vscode", "windsurf"];

/// Whether a link is one of an agent app's own, with nothing in it a shell could read as a second command.
pub fn is_app_link(link: &str) -> bool {
    let Some((scheme, rest)) = link.split_once("://") else {
        return false;
    };
    APP_SCHEMES.contains(&scheme.to_ascii_lowercase().as_str())
        && !rest.is_empty()
        && !link.chars().any(|character| {
            character.is_whitespace() || character.is_control() || character == '"'
        })
}

/// A query value with everything but letters, digits and `-_.~` written as `%XX`.
pub fn encoded(value: &str) -> String {
    value
        .bytes()
        .map(|byte| match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                (byte as char).to_string()
            }
            _ => format!("%{byte:02X}"),
        })
        .collect()
}

/// A link with its query written in the order given, so the same request always builds the same link.
pub fn link(scheme: &str, host: &str, path: &str, query: &[(&str, &str)]) -> String {
    let query: Vec<String> = query
        .iter()
        .map(|(key, value)| format!("{key}={}", encoded(value)))
        .collect();
    if query.is_empty() {
        format!("{scheme}://{host}{path}")
    } else {
        format!("{scheme}://{host}{path}?{}", query.join("&"))
    }
}

/// The Claude Code extension's host, whose `/open` link opens a conversation.
pub const CLAUDE_CODE: &str = "anthropic.claude-code";

/// The agent's own conversation id is a UUID, the only id that opens its conversation rather than a new one.
pub fn is_conversation_id(id: &str) -> bool {
    id.len() == 36
        && id
            .chars()
            .all(|character| character.is_ascii_hexdigit() || character == '-')
}

/// The Claude Code link that opens one conversation in its editor.
pub fn conversation_link(editor: Editor, conversation: &str) -> String {
    link(
        editor.scheme(),
        CLAUDE_CODE,
        "/open",
        &[("session", conversation)],
    )
}

/// The terminal device as the Memnox extension takes it in a link, only the `ttys004` form, since the
/// extension reads devices that way and no other, so a Linux `pts/3` is never sent to it.
pub fn extension_device(tty: &str) -> Option<String> {
    let name = tty.trim().strip_prefix("/dev/").unwrap_or(tty.trim());
    let digits = name
        .strip_prefix("ttys")
        .or_else(|| name.strip_prefix("tty"))?;
    (!digits.is_empty() && digits.chars().all(|character| character.is_ascii_digit()))
        .then(|| name.to_string())
}

/// The Mac's quoting rule: the runtime's line on one line, since a line break in it would run half the line.
pub fn one_line(text: &str) -> String {
    text.lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect::<Vec<_>>()
        .join(" ")
}

/// Unicode as PowerShell's `-EncodedCommand` takes it: little endian UTF 16 in base 64, so the
/// runtime's quoting reaches the shell untouched by Windows Terminal's own `;` and quote parsing.
pub fn encoded_command(line: &str) -> String {
    use base64::Engine;
    let bytes: Vec<u8> = line.encode_utf16().flat_map(u16::to_le_bytes).collect();
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

/// A shell line kept to one argument for `sh -c`, so a new tab runs the runtime's line and then stays.
pub fn stay_open(line: &str) -> String {
    format!("{line}; exec \"${{SHELL:-sh}}\"")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn opens_only_an_agent_app_link() {
        assert!(is_app_link("claude://code/new?folder=%2Ftmp"));
        assert!(is_app_link(
            "cursor://anysphere.cursor-deeplink/prompt?text=hi"
        ));
        assert!(!is_app_link("https://example.com"));
        assert!(!is_app_link("file:///etc/passwd"));
        assert!(!is_app_link("claude://x y"));
        assert!(!is_app_link("claude://"));
    }

    #[test]
    fn reads_the_host_the_runtime_noted() {
        let host = Host {
            app: Some("Visual Studio Code".into()),
            ..Host::default()
        };
        assert_eq!(host.editor(), Some(Editor::Code));
        assert_eq!(
            Editor::named("c:\\program files\\microsoft vs code\\code.exe"),
            Some(Editor::Code)
        );
        assert_eq!(Editor::named("cursor"), Some(Editor::Cursor));
        assert_eq!(Editor::named("gnome-terminal-server"), None);
        assert_eq!(Editor::named("wezterm"), None);
        assert_eq!(
            conversation_link(Editor::Cursor, "0f8fad5b-d9cb-469f-a165-70867728950e"),
            "cursor://anthropic.claude-code/open?session=0f8fad5b-d9cb-469f-a165-70867728950e"
        );
        assert!(is_conversation_id("0f8fad5b-d9cb-469f-a165-70867728950e"));
        assert!(!is_conversation_id("ses_1"));
    }

    #[test]
    fn names_only_a_device_the_extension_reads() {
        assert_eq!(extension_device("/dev/ttys004").as_deref(), Some("ttys004"));
        assert_eq!(extension_device("pts/3"), None);
        assert_eq!(extension_device("ttys"), None);
        assert_eq!(extension_device("ttys1;rm"), None);
    }

    #[test]
    fn hands_the_shell_the_line_untouched() {
        assert_eq!(encoded_command("ls"), "bABzAA==");
        assert_eq!(
            one_line("cd '/a' &&\n  memnox run claude\n"),
            "cd '/a' && memnox run claude"
        );
        assert_eq!(
            stay_open("claude 'hi'"),
            "claude 'hi'; exec \"${SHELL:-sh}\""
        );
        assert_eq!(
            link(
                "vscode",
                "memnox.memnox-terminals",
                "/launch",
                &[("request", "dsp_1 2")]
            ),
            "vscode://memnox.memnox-terminals/launch?request=dsp_1%202"
        );
    }
}
