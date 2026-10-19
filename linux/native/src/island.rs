//! The island on Linux: a layer shell surface on the top edge on KDE, Sway, Hyprland and COSMIC,
//! which stays above windows and never takes the keyboard. GNOME has no layer shell, so there the
//! window stays an ordinary undecorated one kept on top. The side panel and the card wall are made
//! the same way on their own edges, and every one of them takes clicks only inside its input region.

use gtk::cairo::{RectangleInt, Region};
use gtk::glib::translate::ToGlibPtr;
use gtk::glib::Cast;
use gtk::prelude::{GtkWindowExt, WidgetExt};
use gtk_layer_shell::{Edge, KeyboardMode, Layer, LayerShell};

extern "C" {
    // The Rust binding takes a monitor only, while a null one is how the compositor is asked to choose.
    fn gtk_layer_set_monitor(
        window: *mut gtk::ffi::GtkWindow,
        monitor: *mut gtk::gdk::ffi::GdkMonitor,
    );
}

/// The screen edges a floating window of Memnox hangs from.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Hang {
    /// The island, centred on the top edge.
    Top,
    /// The side panel, centred on the left edge.
    Left,
    /// The card wall, in the top left corner.
    TopLeft,
}

/// Turns the app's GTK window into the island where the compositor allows it.
pub fn make_island(window: &gtk::ApplicationWindow) {
    make_floating(window, Hang::Top, "memnox-island");
}

/// Makes a window of Memnox a layer surface on its edge that never takes the keyboard, or keeps it on
/// top where there is no layer shell. Layer shell has to be set before the window is realized, so a
/// window already up is taken down for it and shown again.
pub fn make_floating(window: &gtk::ApplicationWindow, hang: Hang, namespace: &str) {
    if !gtk_layer_shell::is_supported() {
        window.set_keep_above(true);
        return;
    }
    let shown = window.is_visible();
    if window.is_realized() {
        window.hide();
        window.unrealize();
    }
    window.init_layer_shell();
    window.set_layer(Layer::Overlay);
    let edges: &[Edge] = match hang {
        Hang::Top => &[Edge::Top],
        Hang::Left => &[Edge::Left],
        Hang::TopLeft => &[Edge::Top, Edge::Left],
    };
    for edge in edges {
        window.set_anchor(*edge, true);
    }
    window.set_keyboard_mode(KeyboardMode::None);
    window.set_namespace(namespace);
    if shown {
        window.show();
    }
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

/// Takes clicks only inside these boxes, `(x, y, width, height)` in the window's own logical pixels, and
/// lets the rest through to the window underneath. On Wayland this is the surface's input region, so the
/// compositor routes the clicks and no pointer has to be read; on X11 it is the XShape input shape.
pub fn set_input_region(window: &gtk::ApplicationWindow, areas: &[(i32, i32, i32, i32)]) {
    let boxes: Vec<RectangleInt> = areas
        .iter()
        .filter(|(_, _, width, height)| *width > 0 && *height > 0)
        .map(|&(x, y, width, height)| RectangleInt::new(x, y, width, height))
        .collect();
    window.input_shape_combine_region(Some(&Region::create_rectangles(&boxes)));
}

/// Puts a layer surface on the output at `index` in GDK's list, or lets the compositor choose with None,
/// which KDE, Sway and Hyprland answer with the output in use. False where there is no layer shell, so
/// the caller places the window itself.
pub fn set_monitor(window: &gtk::ApplicationWindow, index: Option<i32>) -> bool {
    if !gtk_layer_shell::is_supported() {
        return false;
    }
    let monitor = index.and_then(|index| WidgetExt::display(window).monitor(index));
    let window_ptr: *mut gtk::ffi::GtkWindow = window.upcast_ref::<gtk::Window>().to_glib_none().0;
    let monitor_ptr: *mut gtk::gdk::ffi::GdkMonitor = monitor
        .as_ref()
        .map_or(std::ptr::null_mut(), |monitor| monitor.to_glib_none().0);
    // Both pointers are borrowed for the call alone, and the library copies what it keeps.
    unsafe { gtk_layer_set_monitor(window_ptr, monitor_ptr) };
    true
}
