//! The Add a memory source dialog's reads of this disk, as the Mac's `MemorySourceDisk`: the files or folders the
//! person picks, what a path is and the notes under it, and a Notion zip unzipped beside itself. Nothing here decides
//! what is read; it only gathers what `memory-import.ts` needs to say so before adding.

use std::path::{Path, PathBuf};
use std::process::Command;

use serde::Serialize;
use tauri::{AppHandle, WebviewWindow};
use tauri_plugin_dialog::DialogExt;

/// The most files one look lists, enough to count a person's notes without stalling the dialog on a huge tree.
const MOST_LOOKED: usize = 2_000;
/// How deep a look goes, the runtime's own bound on its walk.
const MOST_DEPTH: usize = 8;
const MARKDOWN: &[&str] = &["md", "markdown", "mdc"];
const INSTRUCTION_NAMES: &[&str] = &["CLAUDE.md", "AGENTS.md", "GEMINI.md", ".cursorrules"];
const CURSOR_RULES: &str = ".cursor/rules";
const SKIPPED_FOLDERS: &[&str] = &["node_modules"];
const FILTER_NAME: &str = "Notes";

/// One path as it was found, the shape `PathLook` in `memory-import.ts` reads.
#[derive(Serialize)]
pub struct PathLook {
    path: String,
    kind: &'static str,
    readable: bool,
    found: Vec<String>,
    cut: bool,
}

/// The person's home, so a typed `~` names the same folder the runtime will read.
#[tauri::command]
pub fn memory_source_home(window: WebviewWindow) -> Result<Option<String>, String> {
    allowed(&window)?;
    Ok(home().map(|path| path.to_string_lossy().into_owned()))
}

/// Asks for files, or folders where the kind reads only a folder, and answers their paths, or nothing when cancelled.
#[tauri::command]
pub async fn pick_memory_source(app: AppHandle, window: WebviewWindow, files: bool, extensions: Vec<String>, title: String) -> Result<Option<Vec<String>>, String> {
    allowed(&window)?;
    let (sent, chosen) = tokio::sync::oneshot::channel();
    let dialog = app.dialog().file().set_parent(&window).set_title(title);
    if files {
        let named: Vec<&str> = extensions.iter().map(String::as_str).collect();
        dialog.add_filter(FILTER_NAME, &named).pick_files(move |paths| {
            let _ = sent.send(paths);
        });
    } else {
        dialog.pick_folders(move |paths| {
            let _ = sent.send(paths);
        });
    }
    let Some(paths) = chosen.await.map_err(|error| error.to_string())? else {
        return Ok(None);
    };
    let paths = paths
        .into_iter()
        .filter_map(|path| path.into_path().ok())
        .map(|path| path.to_string_lossy().into_owned())
        .collect();
    Ok(Some(paths))
}

/// Every path looked at off the window's thread, since a large folder takes a moment to walk.
#[tauri::command]
pub async fn look_memory_paths(window: WebviewWindow, paths: Vec<String>, kind: String) -> Result<Vec<PathLook>, String> {
    allowed(&window)?;
    tokio::task::spawn_blocking(move || paths.into_iter().map(|path| look(path, &kind)).collect())
        .await
        .map_err(|error| error.to_string())
}

/// Unzips a Notion export into a folder beside it, and the zips Notion nests inside it too. A folder already there by
/// that name is taken as this export unzipped before, so nothing is written over.
#[tauri::command]
pub async fn unzip_memory_export(window: WebviewWindow, zip: String) -> Result<String, String> {
    allowed(&window)?;
    tokio::task::spawn_blocking(move || unzip(Path::new(&zip)))
        .await
        .map_err(|error| error.to_string())?
}

fn look(path: String, kind: &str) -> PathLook {
    let at = Path::new(&path);
    let Ok(meta) = std::fs::metadata(at) else {
        return PathLook { path, kind: "missing", readable: true, found: Vec::new(), cut: false };
    };
    if !meta.is_dir() {
        let kind = if meta.is_file() { "file" } else { "other" };
        let readable = std::fs::File::open(at).is_ok();
        return PathLook { path, kind, readable, found: Vec::new(), cut: false };
    }
    if std::fs::read_dir(at).is_err() {
        return PathLook { path, kind: "folder", readable: false, found: Vec::new(), cut: false };
    }
    let (found, cut) = if kind == "instructions" { instruction_files(at) } else { notes(at) };
    PathLook { path, kind: "folder", readable: true, found, cut }
}

fn notes(root: &Path) -> (Vec<String>, bool) {
    let mut found = Vec::new();
    let mut waiting = vec![(root.to_path_buf(), 0usize)];
    while let Some((folder, depth)) = waiting.pop() {
        let Ok(entries) = std::fs::read_dir(&folder) else { continue };
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            // Hidden entries are passed over, as the Mac's walk and the runtime's both do.
            if name.starts_with('.') {
                continue;
            }
            let Ok(kind) = entry.file_type() else { continue };
            let path = entry.path();
            if kind.is_dir() {
                if depth + 1 < MOST_DEPTH && !SKIPPED_FOLDERS.contains(&name.as_str()) {
                    waiting.push((path, depth + 1));
                }
                continue;
            }
            if !kind.is_file() || !is_markdown(&name) {
                continue;
            }
            found.push(relative(root, &path));
            if found.len() >= MOST_LOOKED {
                found.sort();
                return (found, true);
            }
        }
    }
    found.sort();
    (found, false)
}

fn instruction_files(root: &Path) -> (Vec<String>, bool) {
    let mut found: Vec<String> = INSTRUCTION_NAMES.iter().filter(|name| root.join(name).exists()).map(|name| (*name).to_owned()).collect();
    let mut rules: Vec<String> = std::fs::read_dir(root.join(CURSOR_RULES))
        .map(|entries| entries.flatten().map(|entry| entry.file_name().to_string_lossy().into_owned()).filter(|name| is_markdown(name)).collect())
        .unwrap_or_default();
    rules.sort();
    found.extend(rules.into_iter().map(|name| format!("{CURSOR_RULES}/{name}")));
    (found, false)
}

fn is_markdown(name: &str) -> bool {
    Path::new(name)
        .extension()
        .map(|extension| MARKDOWN.contains(&extension.to_string_lossy().to_lowercase().as_str()))
        .unwrap_or(false)
}

/// A path under the root with forward slashes, the spelling `counts` in `memory-import.ts` reads on every system.
fn relative(root: &Path, path: &Path) -> String {
    let inside = path.strip_prefix(root).unwrap_or(path);
    inside.components().map(|part| part.as_os_str().to_string_lossy().into_owned()).collect::<Vec<_>>().join("/")
}

fn unzip(zip: &Path) -> Result<String, String> {
    let into = zip.with_extension("");
    let name = |path: &Path| path.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default();
    if into.exists() {
        return if into.is_dir() { Ok(into.to_string_lossy().into_owned()) } else { Err(format!("{} is already a file beside the zip.", name(&into))) };
    }
    std::fs::create_dir_all(&into).map_err(|_| format!("{} could not be unzipped.", name(zip)))?;
    extract(zip, &into)?;
    // Notion splits a large export into part zips inside the first one.
    let parts: Vec<PathBuf> = std::fs::read_dir(&into)
        .map(|entries| entries.flatten().map(|entry| entry.path()).filter(|path| path.extension().is_some_and(|extension| extension.eq_ignore_ascii_case("zip"))).collect())
        .unwrap_or_default();
    for part in parts {
        extract(&part, &into)?;
        let _ = std::fs::remove_file(&part);
    }
    Ok(into.to_string_lossy().into_owned())
}

/// The system's own unzip: `tar` reads a zip on Windows 10 and later, and `unzip` is there on every Linux desktop.
fn extract(zip: &Path, into: &Path) -> Result<(), String> {
    let mut command = if cfg!(windows) {
        let mut tar = Command::new("tar");
        tar.arg("-xf").arg(zip).arg("-C").arg(into);
        tar
    } else {
        let mut unzip = Command::new("unzip");
        unzip.arg("-q").arg("-o").arg(zip).arg("-d").arg(into);
        unzip
    };
    let name = zip.file_name().map(|name| name.to_string_lossy().into_owned()).unwrap_or_default();
    let status = command.status().map_err(|_| "The system could not start unzipping it.".to_owned())?;
    if status.success() { Ok(()) } else { Err(format!("{name} could not be unzipped.")) }
}

fn home() -> Option<PathBuf> {
    let variable = if cfg!(windows) { "USERPROFILE" } else { "HOME" };
    std::env::var_os(variable).map(PathBuf::from).filter(|path| path.is_absolute())
}

/// Only the Memnox window and its popped out inspectors add a memory source, so only they ask.
fn allowed(window: &WebviewWindow) -> Result<(), String> {
    if crate::settings_windows::is_memnox_window(window.label()) {
        Ok(())
    } else {
        Err("only the Memnox window adds a memory source".to_owned())
    }
}
