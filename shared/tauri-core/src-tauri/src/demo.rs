//! Demo mode, for judging the design with every page full: on only when the app starts with `MEMNOX_DEMO=1`. Every
//! window is told before its own script runs, and answers from `shared/demo/power-user.json` rather than the daemon.

use tauri::plugin::{Builder, TauriPlugin};
use tauri::Runtime;

/// The variable that turns demo mode on, as the Mac app reads it too.
const VARIABLE: &str = "MEMNOX_DEMO";

/// Whether this run was started in demo mode.
pub fn on() -> bool {
    std::env::var(VARIABLE).is_ok_and(|value| value == "1")
}

/// Turns the demo on or off and starts the app again, since every window reads it once as its script starts. The
/// restarted app inherits this process's environment, so the variable carries the choice and nothing is kept on disk.
#[tauri::command]
pub fn switch_demo<R: Runtime>(app: tauri::AppHandle<R>, on: bool) {
    if on {
        std::env::set_var(VARIABLE, "1");
    } else {
        std::env::remove_var(VARIABLE);
    }
    app.restart();
}

/// Marks every window as a demo before its script runs, or does nothing at all when demo mode is off.
pub fn plugin<R: Runtime>() -> TauriPlugin<R> {
    let builder = Builder::new("memnox-demo");
    if on() {
        builder
            .js_init_script("window.__MEMNOX_DEMO__ = true;")
            .build()
    } else {
        builder.build()
    }
}
