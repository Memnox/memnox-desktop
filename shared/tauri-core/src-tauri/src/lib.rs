//! Memnox on Windows and Linux: a face and a signing key over the daemon, and nothing else. The
//! webview draws the island from the core in `src/core`; this crate gives it the daemon, the key and
//! the window, and the platform crates in `windows/` and `linux/` hold what each system does its own way.

mod awake;
mod daemon;
mod island;
mod key;
mod keys;
mod panels;
mod permissions;
mod runtime;
mod sessions;
mod settings_windows;
mod talk_key;
mod tray;
mod typing;
mod voice;

use std::sync::Arc;

use memnox_desktop_voice::VoiceModels;
use tauri::Manager;

/// The island's window, as `tauri.conf.json` names it.
pub(crate) const ISLAND: &str = "island";

pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_autostart::init(
            tauri_plugin_autostart::MacosLauncher::LaunchAgent,
            None,
        ))
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .manage(awake::Awake::default())
        .manage(Arc::new(island::HitAreas::default()))
        .setup(|app| {
            let window = app
                .get_webview_window(ISLAND)
                .ok_or("the island window is missing")?;
            app.manage(key::Key::for_platform(&window));
            let models = app.path().app_data_dir()?.join("voice");
            let chosen = app.path().app_config_dir()?.join("voice.txt");
            let voice = Arc::new(voice::Voice::new(VoiceModels::new(models), chosen));
            voice.report_levels(app.handle().clone());
            app.manage(voice);
            make_island(&window);
            island::place(&window);
            island::follow(
                window.clone(),
                app.state::<Arc<island::HitAreas>>().inner().clone(),
            );
            // A screen added, removed or rescaled moves the top centre, so the island follows it there.
            let placed = window.clone();
            window.on_window_event(move |event| {
                if matches!(event, tauri::WindowEvent::ScaleFactorChanged { .. }) {
                    island::place(&placed);
                }
            });
            // Right Alt to dictate and Ctrl with left Alt for a rule, seen from any app.
            keys::start(app.handle());
            tray::build(app)?;
            tray::start_at_sign_in_once(app);
            // Another app holding the key is no reason not to start; the Talk button still works.
            if let Err(why) = talk_key::register(app) {
                eprintln!("Memnox: the talk key is taken: {why}");
            }
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            daemon::daemon_stream,
            key::confirm_key_point,
            key::confirm_key_sign,
            awake::keep_awake,
            awake::on_power,
            voice::voice_installed,
            voice::voice_install,
            voice::listen_once,
            voice::speak,
            voice::speak_stop,
            voice::speak_hush,
            voice::speak_carry_on,
            voice::ear_open,
            voice::ear_close,
            voice::chime,
            island_keyboard,
            keys::keys_watching,
            typing::focus_read,
            typing::type_text,
            typing::type_revise,
            typing::clipboard_set,
            island::island_hit_areas,
            voice::voice_choice,
            voice::choose_voice,
            runtime::runtime_found,
            runtime::runtime_install,
            runtime::runtime_wired,
            runtime::runtime_run,
            tray::tray_action,
            tray::tray_panel_hide,
            tray::tray_panel_fit,
            panels::cards_show,
            panels::cards_hide,
            panels::cards_fit,
            panels::scan_show,
            panels::scan_hide,
            sessions::open_live_session,
            sessions::open_side,
            sessions::open_switcher,
            sessions::open_board,
            sessions::dismiss_session_windows,
            sessions::close_session_window,
            sessions::open_folder,
            sessions::open_link,
            settings_windows::open_settings,
            settings_windows::open_onboarding,
            settings_windows::close_window,
            settings_windows::apply_appearance,
            settings_windows::start_at_sign_in,
            settings_windows::set_start_at_sign_in,
            settings_windows::restart_memnox,
            settings_windows::open_page,
            permissions::permission_facts,
            permissions::open_privacy,
        ])
        .run(tauri::generate_context!())
        .expect("Memnox could not start its window");
}

/// The platform's own island: no focus and no taskbar on Windows, a layer shell surface on Linux.
#[allow(unused_variables)]
fn make_island(window: &tauri::WebviewWindow) {
    #[cfg(windows)]
    if let Ok(hwnd) = window.hwnd() {
        memnox_windows::make_island(hwnd.0 as isize);
    }
    #[cfg(target_os = "linux")]
    if let Ok(gtk) = window.gtk_window() {
        memnox_linux::make_island(&gtk);
    }
}

/// Lets the island take the keyboard while a draft is rewritten, and gives it back after.
#[tauri::command]
fn island_keyboard(window: tauri::WebviewWindow, on: bool) -> Result<(), String> {
    #[cfg(windows)]
    if let Ok(hwnd) = window.hwnd() {
        memnox_windows::island_keyboard(hwnd.0 as isize, on);
    }
    #[cfg(target_os = "linux")]
    {
        let island = window.clone();
        window
            .run_on_main_thread(move || {
                if let Ok(gtk) = island.gtk_window() {
                    memnox_linux::island_keyboard(&gtk, on);
                }
            })
            .map_err(|error| error.to_string())?;
    }
    if on {
        window.set_focus().map_err(|error| error.to_string())?;
    }
    Ok(())
}
