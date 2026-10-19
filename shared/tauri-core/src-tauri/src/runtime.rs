//! The Memnox runtime as setup reaches it, ported from the Mac's `RuntimeInstaller`: where `memnox` comes
//! from, installing it, and the three steps setup may take. The webview names a step and never a command
//! line, so nothing it sends can run anything else. Every command runs the way the person's own shell would.
//!
//! A release finds the person's own `memnox`, or installs the published package with their npm when their
//! Node is new enough, or else fetches the official Node into `~/.memnox/node`, checked against the
//! release's SHASUMS256, and installs Memnox beside it, so no Node is needed on the computer at all. A
//! development build started with `MEMNOX_RUNTIME_DIR` runs that `memnox-runtime` checkout's own CLI.

use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// A step setup may take, each one fixed command line after `memnox`.
#[derive(Deserialize, Clone, Copy, Debug, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum Step {
    /// Wires every agent found here in observe, which records and enforces nothing until the person says.
    Setup,
    /// Installs and starts the daemon as a service.
    Start,
    Update,
}

impl Step {
    fn words(self) -> &'static str {
        match self {
            Step::Setup => "setup --yes --no-probe",
            Step::Start => "daemon --install",
            Step::Update => "update --yes",
        }
    }
}

/// Where this build gets `memnox`, as the Mac's `RuntimeSource`.
#[derive(Serialize, Clone, Debug, PartialEq)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum Source {
    /// The runtime checkout at this path, for working on both at once.
    Local { checkout: String },
    /// The package published to npm, which is what a release installs.
    Npm,
}

/// Named only in a development build, so a release never runs a checkout an environment points at.
const CHECKOUT_VARIABLE: &str = "MEMNOX_RUNTIME_DIR";
/// Where the CLI sits in a runtime checkout, and the file a build leaves there.
const CLI_FOLDER: &str = "packages/cli";
const CLI_ENTRY: &str = "dist/index.js";
/// The Node line fetched when the computer has none new enough; the runtime needs 20 or later.
const NODE_LINE: &str = "latest-v22.x";
const NODE_DIST: &str = "https://nodejs.org/dist";
const OLDEST_NODE: u32 = 20;
/// More than any Node archive weighs, so a runaway download stops.
const MOST_DOWNLOAD: u64 = 200 * 1024 * 1024;

fn source() -> Source {
    source_from(
        cfg!(debug_assertions),
        std::env::var(CHECKOUT_VARIABLE).ok(),
    )
}

fn source_from(debug: bool, checkout: Option<String>) -> Source {
    match checkout {
        Some(checkout) if debug && !checkout.trim().is_empty() => Source::Local { checkout },
        _ => Source::Npm,
    }
}

fn home() -> Option<PathBuf> {
    let home = if cfg!(windows) {
        std::env::var_os("USERPROFILE")
    } else {
        std::env::var_os("HOME")
    };
    home.map(PathBuf::from)
}

/// `~/.memnox/node`, where the Node this app fetches and the runtime installed beside it live.
fn private_node() -> Option<PathBuf> {
    home().map(|home| home.join(".memnox").join("node"))
}

/// The folder of the private Node's commands: the root on Windows, `bin` elsewhere.
fn private_bin(node: &Path) -> PathBuf {
    if cfg!(windows) {
        node.to_path_buf()
    } else {
        node.join("bin")
    }
}

fn private_memnox(node: &Path) -> PathBuf {
    private_bin(node).join(if cfg!(windows) {
        "memnox.cmd"
    } else {
        "memnox"
    })
}

fn private_node_program(node: &Path) -> PathBuf {
    private_bin(node).join(if cfg!(windows) { "node.exe" } else { "node" })
}

fn private_npm(node: &Path) -> PathBuf {
    let modules = if cfg!(windows) {
        node.join("node_modules")
    } else {
        node.join("lib").join("node_modules")
    };
    modules.join("npm").join("bin").join("npm-cli.js")
}

/// Quoted for the shell the line runs in, with a quote inside closed, escaped and reopened.
fn quoted(path: &Path) -> String {
    let text = path.to_string_lossy();
    if cfg!(windows) {
        format!("\"{text}\"")
    } else {
        format!("'{}'", text.replace('\'', "'\\''"))
    }
}

/// The start of a shell line that runs `memnox`, from wherever this build says it comes from.
fn memnox_command() -> Option<String> {
    match source() {
        Source::Local { checkout } => {
            let entry = Path::new(&checkout).join(CLI_FOLDER).join(CLI_ENTRY);
            entry.exists().then(|| format!("node {}", quoted(&entry)))
        }
        Source::Npm => {
            let node = private_node();
            // The copy in ~/.memnox/node is this app's to keep up to date, so only a memnox from anywhere else is the person's own.
            if let Some(found) = found("memnox") {
                let ours = node
                    .as_ref()
                    .is_some_and(|node| Path::new(&found).starts_with(node));
                if !ours {
                    return Some("memnox".into());
                }
            }
            let node = node?;
            private_memnox(&node).exists().then(|| private_line(&node))
        }
    }
}

/// The private runtime with its own Node first on its PATH, so it needs no Node on the computer and
/// `memnox update` updates it in place, whatever prefix the person's own npmrc names.
fn private_line(node: &Path) -> String {
    let bin = private_bin(node);
    let memnox = quoted(&private_memnox(node));
    if cfg!(windows) {
        format!(
            "set \"PATH={};%PATH%\" && set \"NPM_CONFIG_PREFIX={}\" && {memnox}",
            bin.display(),
            node.display()
        )
    } else {
        format!(
            "PATH={}:\"$PATH\" NPM_CONFIG_PREFIX={} {memnox}",
            quoted(&bin),
            quoted(node)
        )
    }
}

/// Runs one line through the person's login shell, which knows nvm and npm's own folder, with no window.
fn shell(line: &str) -> bool {
    let mut command = shell_command(line);
    command
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    command
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

/// What one line printed, when it ran cleanly.
fn shell_output(line: &str) -> Option<String> {
    let out = shell_command(line).stdin(Stdio::null()).output().ok()?;
    out.status
        .success()
        .then(|| String::from_utf8_lossy(&out.stdout).to_string())
}

#[cfg(windows)]
fn shell_command(line: &str) -> Command {
    use std::os::windows::process::CommandExt;
    let mut command = Command::new("cmd");
    // Raw, since cmd reads quotes its own way: /S strips only the outer pair and keeps the line as written.
    command
        .args(["/D", "/S", "/C"])
        .raw_arg(format!("\"{line}\""))
        .creation_flags(NO_WINDOW);
    command
}

#[cfg(not(windows))]
fn shell_command(line: &str) -> Command {
    let login = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".into());
    let mut command = Command::new(login);
    command.args(["-lc", line]);
    command
}

/// So no console window flashes up behind the island.
#[cfg(windows)]
const NO_WINDOW: u32 = 0x0800_0000;

/// A program with no window, run directly rather than through a shell.
fn quiet(program: &Path) -> Command {
    #[allow(unused_mut)]
    let mut command = Command::new(program);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(NO_WINDOW);
    }
    command
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    command
}

/// The full path of a command as the person's shell finds it.
fn found(command: &str) -> Option<String> {
    let line = if cfg!(windows) {
        format!("where {command}")
    } else {
        format!("command -v {command}")
    };
    let output = shell_output(&line)?;
    let path = if cfg!(windows) {
        output.lines().next()
    } else {
        output.lines().last()
    }?
    .trim()
    .to_string();
    (!path.is_empty()).then_some(path)
}

/// The major version from `node -v`, such as 22 from "v22.11.0".
fn node_major(version: &str) -> Option<u32> {
    version
        .trim()
        .trim_start_matches('v')
        .split('.')
        .next()?
        .parse()
        .ok()
}

/// Whether the person's own Node and npm are here and new enough for the runtime.
fn own_node_fits() -> bool {
    found("npm").is_some()
        && shell_output("node -v")
            .and_then(|version| node_major(&version))
            .is_some_and(|major| major >= OLDEST_NODE)
}

/// The archive name this computer takes from a Node release, by system and processor.
fn archive_suffix() -> Option<String> {
    let arch = match std::env::consts::ARCH {
        "x86_64" => "x64",
        "aarch64" => "arm64",
        _ => return None,
    };
    match std::env::consts::OS {
        "windows" => Some(format!("win-{arch}.zip")),
        "linux" => Some(format!("linux-{arch}.tar.xz")),
        "macos" => Some(format!("darwin-{arch}.tar.gz")),
        _ => None,
    }
}

/// The checksum and file name of the one archive with this suffix in a release's SHASUMS256.
fn pick_archive(sums: &str, suffix: &str) -> Option<(String, String)> {
    sums.lines().find_map(|line| {
        let mut parts = line.split_whitespace();
        let (hash, name) = (parts.next()?, parts.next()?);
        let fits = name.starts_with("node-v") && name.ends_with(&format!("-{suffix}"));
        (fits && hash.len() == 64).then(|| (hash.to_ascii_lowercase(), name.to_string()))
    })
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn fetch(url: &str) -> Result<Vec<u8>, String> {
    let response = ureq::get(url).call().map_err(|error| error.to_string())?;
    let mut body = Vec::new();
    response
        .into_reader()
        .take(MOST_DOWNLOAD)
        .read_to_end(&mut body)
        .map_err(|error| error.to_string())?;
    Ok(body)
}

/// The system's own tar, which unpacks the zip on Windows 10 and later and the xz tarball on Linux.
fn tar() -> PathBuf {
    if cfg!(windows) {
        let root = std::env::var_os("SystemRoot").unwrap_or_else(|| "C:\\Windows".into());
        PathBuf::from(root).join("System32").join("tar.exe")
    } else {
        PathBuf::from("tar")
    }
}

/// The official Node, fetched from nodejs.org, checked against the release's SHASUMS256 and unpacked into
/// `~/.memnox/node`, replacing what was there only once the new one is whole.
fn install_private_node(node: &Path) -> Result<(), String> {
    let suffix = archive_suffix().ok_or("no Node is published for this computer")?;
    let release = format!("{NODE_DIST}/{NODE_LINE}");
    let sums = String::from_utf8(fetch(&format!("{release}/SHASUMS256.txt"))?)
        .map_err(|error| error.to_string())?;
    let (hash, name) = pick_archive(&sums, &suffix)
        .ok_or("the Node release lists no archive for this computer")?;
    let archive = fetch(&format!("{release}/{name}"))?;
    if hex(&Sha256::digest(&archive)) != hash {
        return Err("the Node download did not match its checksum".into());
    }
    let parent = node.parent().ok_or("no folder for Node")?;
    let unpacking = parent.join("node-unpacking");
    let _ = std::fs::remove_dir_all(&unpacking);
    std::fs::create_dir_all(&unpacking).map_err(|error| error.to_string())?;
    let saved = unpacking.join(&name);
    std::fs::write(&saved, &archive).map_err(|error| error.to_string())?;
    let unpacked = quiet(&tar())
        .arg("-xf")
        .arg(&saved)
        .arg("-C")
        .arg(&unpacking)
        .status()
        .is_ok_and(|status| status.success());
    let folder = unpacking.join(
        name.trim_end_matches(".zip")
            .trim_end_matches(".tar.xz")
            .trim_end_matches(".tar.gz"),
    );
    if !unpacked || !private_npm(&folder).exists() {
        let _ = std::fs::remove_dir_all(&unpacking);
        return Err("the Node download would not unpack".into());
    }
    let _ = std::fs::remove_dir_all(node);
    let moved = std::fs::rename(&folder, node).map_err(|error| error.to_string());
    let _ = std::fs::remove_dir_all(&unpacking);
    moved
}

/// Memnox installed with the private Node's own npm, into the same folder, so it updates in place.
fn install_beside_private_node(node: &Path) -> bool {
    quiet(&private_node_program(node))
        .arg(private_npm(node))
        .args(["install", "-g", "--prefix"])
        .arg(node)
        .arg("memnox@latest")
        .env("PATH", path_with(&private_bin(node)))
        .status()
        .is_ok_and(|status| status.success())
        && private_memnox(node).exists()
}

fn path_with(folder: &Path) -> std::ffi::OsString {
    let mut folders = vec![folder.to_path_buf()];
    if let Some(path) = std::env::var_os("PATH") {
        folders.extend(std::env::split_paths(&path));
    }
    std::env::join_paths(folders).unwrap_or_default()
}

fn install() -> bool {
    match source() {
        // The checkout's CLI linked onto the PATH, so the daemon, the hooks and every terminal run its code.
        Source::Local { checkout } => {
            let cli = Path::new(&checkout).join(CLI_FOLDER);
            if !cli.join(CLI_ENTRY).exists() {
                return false;
            }
            shell(&format!("cd {} && npm link", quoted(&cli)));
            memnox_command().is_some()
        }
        Source::Npm => {
            if own_node_fits()
                && shell("npm install -g memnox@latest")
                && memnox_command().is_some()
            {
                return true;
            }
            let Some(node) = private_node() else {
                return false;
            };
            if !private_npm(&node).exists() && install_private_node(&node).is_err() {
                return false;
            }
            install_beside_private_node(&node)
        }
    }
}

async fn blocking<T: Send + 'static>(
    work: impl FnOnce() -> T + Send + 'static,
) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(work)
        .await
        .map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn runtime_found() -> Result<bool, String> {
    blocking(|| memnox_command().is_some()).await
}

/// The published package, with the person's npm or a Node of the app's own; a checkout is linked instead.
#[tauri::command]
pub async fn runtime_install() -> Result<bool, String> {
    blocking(install).await
}

/// Where this build gets `memnox`, so setup words a failure and updates a checkout the right way.
#[tauri::command]
pub fn runtime_source() -> Source {
    source()
}

/// Whether this computer was set up before, which `memnox setup` marks by keeping `~/.memnox/kept.json`.
#[tauri::command]
pub fn runtime_wired() -> bool {
    home().is_some_and(|home| home.join(".memnox").join("kept.json").exists())
}

#[tauri::command]
pub async fn runtime_run(step: Step) -> Result<bool, String> {
    blocking(move || {
        memnox_command().is_some_and(|memnox| shell(&format!("{memnox} {}", step.words())))
    })
    .await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_only_the_three_fixed_steps() {
        let step: Step = serde_json::from_str("\"update\"").unwrap();
        assert_eq!(step.words(), "update --yes");
        assert!(serde_json::from_str::<Step>("\"rm -rf ~\"").is_err());
    }

    #[test]
    fn runs_a_checkout_only_in_a_development_build() {
        let checkout = Some("/src/memnox-runtime".to_string());
        assert_eq!(
            source_from(true, checkout.clone()),
            Source::Local {
                checkout: "/src/memnox-runtime".into()
            }
        );
        assert_eq!(source_from(false, checkout), Source::Npm);
        assert_eq!(source_from(true, Some(" ".into())), Source::Npm);
        assert_eq!(
            serde_json::to_string(&Source::Npm).unwrap(),
            "{\"kind\":\"npm\"}"
        );
    }

    #[test]
    fn picks_the_one_archive_for_this_computer_from_the_sums() {
        let hash = "a".repeat(64);
        let sums = format!(
            "{hash}  node-v22.11.0-linux-x64.tar.xz\n{hash}  node-v22.11.0-linux-x64.tar.gz\n{hash}  node-v22.11.0-win-x64.zip\n"
        );
        assert_eq!(
            pick_archive(&sums, "linux-x64.tar.xz"),
            Some((hash.clone(), "node-v22.11.0-linux-x64.tar.xz".into()))
        );
        assert_eq!(
            pick_archive(&sums, "win-x64.zip").map(|(_, name)| name),
            Some("node-v22.11.0-win-x64.zip".into())
        );
        assert_eq!(
            pick_archive("short  node-v22-win-x64.zip", "win-x64.zip"),
            None
        );
    }

    #[test]
    fn reads_the_major_node_version() {
        assert_eq!(node_major("v22.11.0\n"), Some(22));
        assert_eq!(node_major("garbage"), None);
    }

    #[test]
    fn checks_the_download_against_its_hex_digest() {
        assert_eq!(
            hex(&Sha256::digest(b"abc")),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }
}
