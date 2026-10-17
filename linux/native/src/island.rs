//! The island on Linux: a layer shell surface on the top edge on KDE, Sway, Hyprland and COSMIC,
//! which stays above windows and never takes the keyboard. GNOME has no layer shell, so there the
//! window stays an ordinary undecorated one kept on top.

use gtk::prelude::GtkWindowExt;
use gtk_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};

/// Turns the app's GTK window into the island where the compositor allows it.
pub fn make_island(window: &gtk::ApplicationWindow) {
    if !gtk_layer_shell::is_supported() {
        window.set_keep_above(true);
        return;
    }
    window.init_layer_shell();
    window.set_layer(Layer::Overlay);
    window.set_anchor(Edge::Top, true);
    window.set_keyboard_mode(KeyboardMode::None);
    window.set_namespace("memnox-island");
}

/// Lets the island take the keyboard while the person rewrites a draft, and gives it back after.
pub fn island_keyboard(window: &gtk::ApplicationWindow, on: bool) {
    if gtk_layer_shell::is_supported() {
        window.set_keyboard_mode(if on {
            KeyboardMode::OnDemand
        } else {
            KeyboardMode::None
        });
    }
}
