//! Where the app learns a newer Memnox is out: this repo's releases on GitHub for the app, and the package
//! published to npm for the Memnox service. The core reads what comes back and decides what to offer; this
//! is only the transport, as the Mac's `GitHubReleases` is. The webview names a list and never an address,
//! so nothing it sends can make this reach anywhere else.

use serde::Deserialize;

/// The app's releases, read without signing in, as install.sh reads them.
const APP_RELEASES: &str =
    "https://api.github.com/repos/Memnox/memnox-desktop/releases?per_page=30";
/// The newest runtime npm serves, the same package the first run installs as `memnox@latest`.
const RUNTIME_LATEST: &str = "https://registry.npmjs.org/memnox/latest";
/// Long enough for a slow network, short enough that a look never hangs the pill it would draw.
const TIMEOUT: std::time::Duration = std::time::Duration::from_secs(20);
/// GitHub refuses a request that names no client.
const CLIENT: &str = "memnox-desktop";

/// The two lists the core may ask for, and nothing else.
#[derive(Deserialize, Clone, Copy, Debug, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum List {
    App,
    Runtime,
}

impl List {
    fn address(self) -> &'static str {
        match self {
            List::App => APP_RELEASES,
            List::Runtime => RUNTIME_LATEST,
        }
    }
}

/// One list's answer as it came, or why nothing came back at all.
#[tauri::command]
pub async fn release_feed(list: List) -> Result<String, String> {
    tokio::task::spawn_blocking(move || read(list.address()))
        .await
        .map_err(|why| why.to_string())?
}

fn read(address: &str) -> Result<String, String> {
    ureq::get(address)
        .timeout(TIMEOUT)
        .set("Accept", "application/json")
        .set("User-Agent", CLIENT)
        .call()
        .map_err(|why| why.to_string())?
        .into_string()
        .map_err(|why| why.to_string())
}

/// The version this app was built as, which `tauri.conf.json` carries and a release's tag names.
#[tauri::command]
pub fn app_version(app: tauri::AppHandle) -> String {
    app.package_info().version.to_string()
}

#[cfg(test)]
mod tests {
    use super::List;

    #[test]
    fn reaches_only_the_two_lists_it_names() {
        assert!(List::App
            .address()
            .starts_with("https://api.github.com/repos/Memnox/memnox-desktop/"));
        assert_eq!(
            List::Runtime.address(),
            "https://registry.npmjs.org/memnox/latest"
        );
        assert_eq!(
            serde_json::from_str::<List>("\"app\"").ok(),
            Some(List::App)
        );
        assert!(serde_json::from_str::<List>("\"https://elsewhere.test\"").is_err());
    }
}
