//! The Memnox runtime as setup reaches it: whether `memnox` is here, installing it from npm, and the three
//! steps setup may take. The webview names a step and never a command line, so nothing it sends can run
//! anything else. Every command runs the way the person's own shell would, so it lands where theirs would.

use std::process::{Command, Stdio};

use serde::Deserialize;

/// A step setup may take, each one fixed command line.
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
    fn line(self) -> &'static str {
        match self {
            Step::Setup => "memnox setup --yes --no-probe",
            Step::Start => "memnox daemon --install",
            Step::Update => "memnox update --yes",
        }
    }
}

/// Runs one fixed line through the person's login shell, which knows nvm and npm's own folder, with no window.
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

#[cfg(windows)]
fn shell_command(line: &str) -> Command {
    use std::os::windows::process::CommandExt;
    /// So no console window flashes up behind the island.
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    let mut command = Command::new("cmd");
    command
        .args(["/D", "/C", line])
        .creation_flags(CREATE_NO_WINDOW);
    command
}

#[cfg(not(windows))]
fn shell_command(line: &str) -> Command {
    let login = std::env::var("SHELL").unwrap_or_else(|_| "/bin/sh".into());
    let mut command = Command::new(login);
    command.args(["-lc", line]);
    command
}

fn found_line() -> &'static str {
    if cfg!(windows) {
        "where memnox"
    } else {
        "command -v memnox"
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
    blocking(|| shell(found_line())).await
}

/// The published package from npm, for a computer with no `memnox` yet.
#[tauri::command]
pub async fn runtime_install() -> Result<bool, String> {
    blocking(|| shell("npm install -g memnox@latest") && shell(found_line())).await
}

/// Whether this computer was set up before, which `memnox setup` marks by keeping `~/.memnox/kept.json`.
#[tauri::command]
pub fn runtime_wired() -> bool {
    let home = if cfg!(windows) {
        std::env::var("USERPROFILE")
    } else {
        std::env::var("HOME")
    };
    home.map(|home| {
        std::path::Path::new(&home)
            .join(".memnox")
            .join("kept.json")
            .exists()
    })
    .unwrap_or(false)
}

#[tauri::command]
pub async fn runtime_run(step: Step) -> Result<bool, String> {
    blocking(move || shell(step.line())).await
}

#[cfg(test)]
mod tests {
    use super::Step;

    #[test]
    fn names_only_the_three_fixed_steps() {
        let step: Step = serde_json::from_str("\"update\"").unwrap();
        assert_eq!(step.line(), "memnox update --yes");
        assert!(serde_json::from_str::<Step>("\"rm -rf ~\"").is_err());
    }
}
