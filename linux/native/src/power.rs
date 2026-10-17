//! Keeping the computer awake while a phone is paired and it runs on mains power, so the phone can
//! reach it from anywhere. A held call that arrives while it sleeps waits until it wakes.

use std::fs;
use std::path::Path;
use std::process::{Child, Command, Stdio};

const SUPPLIES: &str = "/sys/class/power_supply";

/// Whether the computer runs on the charger; one with no battery at all, a desktop, always does.
pub fn on_mains() -> bool {
    let Ok(entries) = fs::read_dir(SUPPLIES) else {
        return true;
    };
    let supplies: Vec<_> = entries.flatten().map(|entry| entry.path()).collect();
    let mains: Vec<_> = supplies
        .iter()
        .filter(|path| read(path, "type") == "Mains")
        .collect();
    let has_battery = supplies.iter().any(|path| read(path, "type") == "Battery");
    !has_battery || mains.iter().any(|path| read(path, "online") == "1")
}

fn read(supply: &Path, field: &str) -> String {
    fs::read_to_string(supply.join(field))
        .unwrap_or_default()
        .trim()
        .to_string()
}

/// Sleep held off by `systemd-inhibit` while this lives; dropping it ends the inhibitor.
pub struct KeepAwake {
    inhibitor: Option<Child>,
}

impl KeepAwake {
    /// Without systemd there is nothing to ask, and the computer sleeps as it would have.
    pub fn start() -> Self {
        let inhibitor = Command::new("systemd-inhibit")
            .args(["--what=sleep", "--who=Memnox", "--mode=block"])
            .arg("--why=A phone is paired and may need this computer")
            .args(["sleep", "infinity"])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
            .ok();
        Self { inhibitor }
    }
}

impl Drop for KeepAwake {
    fn drop(&mut self) {
        if let Some(mut child) = self.inhibitor.take() {
            let _ = child.kill();
            let _ = child.wait();
        }
    }
}
