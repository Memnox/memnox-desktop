//! Opens a local file that evidence names, such as a note a memory was read from, with whatever the
//! system opens that kind of document with. Only a document is opened: never a folder, never a link,
//! and never anything the system would run, so a press on evidence can only ever show something.

use std::path::{Path, PathBuf};
use tauri::WebviewWindow;

/// The kinds of file opened, all of them read rather than run; anything else is copied as a path instead.
const DOCUMENTS: &[&str] = &[
    "md", "markdown", "mdx", "txt", "text", "log", "pdf", "json", "jsonl", "yaml", "yml", "toml",
    "csv", "tsv", "rtf", "odt", "ods", "odp", "docx", "xlsx", "pptx", "png", "jpg", "jpeg", "gif",
    "webp",
];

/// Opens a file evidence names, from the Memnox window only, once `openable` has passed it.
#[tauri::command]
pub fn open_file(window: WebviewWindow, path: String) -> Result<(), String> {
    if !crate::settings_windows::is_memnox_window(window.label()) {
        return Err("only the Memnox window opens a file".to_owned());
    }
    let file = openable(&path)?;
    launch(&file)
}

/// The file itself, once it is an absolute path to a regular document that is there, with links followed
/// so a link named like a note cannot stand in for a program.
fn openable(path: &str) -> Result<PathBuf, String> {
    let given = Path::new(path);
    if !given.is_absolute() {
        return Err(format!("{path} is not a whole path"));
    }
    let real = std::fs::canonicalize(given).map_err(|_| format!("{path} is not there"))?;
    let facts = std::fs::metadata(&real).map_err(|error| error.to_string())?;
    if !facts.is_file() {
        return Err(format!("{path} is not a file"));
    }
    let kind = real
        .extension()
        .and_then(|extension| extension.to_str())
        .map(str::to_ascii_lowercase);
    if !kind.is_some_and(|kind| DOCUMENTS.contains(&kind.as_str())) {
        return Err(format!("{path} is not a kind of document Memnox opens"));
    }
    if runnable(&facts) {
        return Err(format!("{path} can be run, so it is not opened"));
    }
    Ok(real)
}

/// The largest SKILL.md read into the window, far past any real one, so a stray huge file is never pulled whole.
const MOST_SKILL_BYTES: u64 = 1024 * 1024;

/// Reads a skill an agent already keeps, its SKILL.md or its agent file, so the Memnox window draws it formatted as the
/// Mac's preview does. Only a markdown document is read, from the Memnox window only, and nothing here writes to it.
#[tauri::command]
pub fn read_skill_file(window: WebviewWindow, path: String) -> Result<String, String> {
    if !crate::settings_windows::is_memnox_window(window.label()) {
        return Err("only the Memnox window reads a skill".to_owned());
    }
    let file = readable_skill(&path)?;
    std::fs::read_to_string(&file).map_err(|_| format!("{path} could not be read as text"))
}

/// The file itself, once `openable` has passed it, it is markdown, and it is small enough to read whole.
fn readable_skill(path: &str) -> Result<PathBuf, String> {
    let file = openable(path)?;
    let markdown = file
        .extension()
        .and_then(|extension| extension.to_str())
        .is_some_and(|kind| kind.eq_ignore_ascii_case("md") || kind.eq_ignore_ascii_case("markdown"));
    if !markdown {
        return Err(format!("{path} is not a skill's markdown"));
    }
    let size = std::fs::metadata(&file).map_err(|error| error.to_string())?.len();
    if size > MOST_SKILL_BYTES {
        return Err(format!("{path} is too large to read here"));
    }
    Ok(file)
}

#[cfg(unix)]
fn runnable(facts: &std::fs::Metadata) -> bool {
    use std::os::unix::fs::PermissionsExt;
    facts.permissions().mode() & 0o111 != 0
}

#[cfg(not(unix))]
fn runnable(_facts: &std::fs::Metadata) -> bool {
    false
}

/// Hands the file to the system's default for its kind, as one argument, so nothing in a name is read as a command.
fn launch(file: &Path) -> Result<(), String> {
    let mut command = if cfg!(windows) {
        let mut command = std::process::Command::new("rundll32");
        command
            .args(["url.dll,FileProtocolHandler"])
            .arg(plain(file));
        command
    } else if cfg!(target_os = "macos") {
        let mut command = std::process::Command::new("open");
        command.arg(file);
        command
    } else {
        let mut command = std::process::Command::new("xdg-open");
        command.arg(file);
        command
    };
    command
        .spawn()
        .map(|_| ())
        .map_err(|error| error.to_string())
}

/// Windows hands a canonical path back with the `\\?\` prefix, which the shell's file handler does not take.
fn plain(file: &Path) -> String {
    let text = file.to_string_lossy();
    if let Some(share) = text.strip_prefix(r"\\?\UNC\") {
        return format!(r"\\{share}");
    }
    text.strip_prefix(r"\\?\").unwrap_or(&text).to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn folder(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("memnox-open-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("a temporary folder");
        dir
    }

    #[test]
    fn opens_a_document_that_is_there() {
        let dir = folder("note");
        let note = dir.join("Releases.MD");
        std::fs::write(&note, "Tuesdays").expect("a note");
        assert_eq!(
            openable(note.to_str().unwrap()),
            Ok(std::fs::canonicalize(&note).unwrap())
        );
    }

    #[test]
    fn refuses_a_relative_path_a_missing_file_and_a_folder() {
        let dir = folder("refuse");
        assert!(openable("notes/a.md").is_err());
        assert!(openable(dir.join("gone.md").to_str().unwrap()).is_err());
        let inner = dir.join("folder.md");
        std::fs::create_dir_all(&inner).unwrap();
        assert!(openable(inner.to_str().unwrap()).is_err());
    }

    #[test]
    fn never_opens_what_the_system_would_run() {
        let dir = folder("run");
        for name in [
            "setup.exe",
            "run.sh",
            "x.bat",
            "a.desktop",
            "page.html",
            "noextension",
        ] {
            let file = dir.join(name);
            std::fs::write(&file, "x").unwrap();
            assert!(
                openable(file.to_str().unwrap()).is_err(),
                "{name} was let through"
            );
        }
    }

    #[cfg(unix)]
    #[test]
    fn follows_a_link_and_refuses_a_runnable_note() {
        use std::os::unix::fs::PermissionsExt;
        let dir = folder("link");
        let program = dir.join("tool.sh");
        std::fs::write(&program, "#!/bin/sh").unwrap();
        let disguised = dir.join("notes.md");
        std::os::unix::fs::symlink(&program, &disguised).unwrap();
        assert!(openable(disguised.to_str().unwrap()).is_err());
        let runnable_note = dir.join("run.md");
        std::fs::write(&runnable_note, "x").unwrap();
        std::fs::set_permissions(&runnable_note, std::fs::Permissions::from_mode(0o755)).unwrap();
        assert!(openable(runnable_note.to_str().unwrap()).is_err());
    }

    #[test]
    fn drops_the_verbatim_prefix_windows_adds() {
        assert_eq!(plain(Path::new(r"\\?\C:\notes\a.md")), r"C:\notes\a.md");
        assert_eq!(
            plain(Path::new(r"\\?\UNC\server\share\a.md")),
            r"\\server\share\a.md"
        );
        assert_eq!(plain(Path::new("/home/sam/a.md")), "/home/sam/a.md");
    }

    #[test]
    fn reads_only_a_skills_markdown() {
        let dir = folder("skill");
        let skill = dir.join("SKILL.md");
        std::fs::write(&skill, "---\nname: notes\n---\nWrite notes.").expect("a skill");
        assert_eq!(readable_skill(skill.to_str().unwrap()), Ok(std::fs::canonicalize(&skill).unwrap()));
        let other = dir.join("notes.txt");
        std::fs::write(&other, "plain").expect("a note");
        assert!(readable_skill(other.to_str().unwrap()).is_err());
    }
}
