//! Which windowing backend the app asks GTK for. Wayland lets no window say where it goes or that it
//! stays on top, which a layer shell answers on KDE, Sway, Hyprland and COSMIC. GNOME has no layer shell,
//! so on its Wayland session the island would be put wherever Mutter centres a new window and sink under
//! the next one focused. Through XWayland the same window is a dock at the top of the screen, as on an
//! X11 session, so there the app asks for X11 before GTK starts.

use std::sync::atomic::{AtomicBool, Ordering};

/// Set to `0` to keep the Wayland window on GNOME.
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
const OPT_OUT_VAR: &str = "MEMNOX_X11";

/// Set once the app chose X11 for itself, so whoever reads the pointer knows the windows are X11 ones.
static THROUGH_X11: AtomicBool = AtomicBool::new(false);

/// Whether the app's own windows go through XWayland on a Wayland session.
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub fn through_x11() -> bool {
    THROUGH_X11.load(Ordering::Relaxed)
}

/// Whether to ask for X11: only on a Wayland session of GNOME, only with XWayland there to answer, since
/// asking for X11 without it leaves GTK no display at all, and never when the person said no. A
/// `GDK_BACKEND=wayland` that an editor or a terminal handed down is no choice of theirs, so it is not asked.
#[cfg_attr(not(target_os = "linux"), allow(dead_code))]
pub fn wants_x11(desktop: &str, session: &str, display: &str, opt_out: &str) -> bool {
    let gnome = desktop
        .split(':')
        .any(|each| each.eq_ignore_ascii_case("gnome"));
    session.eq_ignore_ascii_case("wayland") && gnome && !display.trim().is_empty() && opt_out != "0"
}

/// Asks GTK for X11 where `wants_x11` says so. Call it first thing, before GTK opens a display.
#[cfg(target_os = "linux")]
pub fn choose() {
    let read = |name: &str| std::env::var(name).unwrap_or_default();
    if wants_x11(
        &read("XDG_CURRENT_DESKTOP"),
        &read("XDG_SESSION_TYPE"),
        &read("DISPLAY"),
        &read(OPT_OUT_VAR),
    ) {
        memnox_linux::through_x11();
        THROUGH_X11.store(true, Ordering::Relaxed);
    }
}

#[cfg(test)]
mod tests {
    use super::wants_x11;

    #[test]
    fn asks_for_x11_only_on_a_wayland_session_of_gnome() {
        assert!(wants_x11("ubuntu:GNOME", "wayland", ":0", ""));
        assert!(wants_x11("GNOME", "Wayland", ":1", "1"));
        assert!(!wants_x11("GNOME", "x11", ":0", ""));
        assert!(!wants_x11("KDE", "wayland", ":0", ""));
        assert!(!wants_x11("sway", "wayland", ":0", ""));
        assert!(!wants_x11("", "wayland", ":0", ""));
    }

    #[test]
    fn never_asks_without_xwayland_or_against_the_person() {
        assert!(!wants_x11("GNOME", "wayland", "", ""));
        assert!(!wants_x11("GNOME", "wayland", " ", ""));
        assert!(!wants_x11("GNOME", "wayland", ":0", "0"));
    }
}
