//! Glass behind a window on KDE Plasma: KWin blurs what lies under a rounded shape of the window, through
//! the `org_kde_kwin_blur` protocol on Wayland and the `_KDE_NET_WM_BLUR_BEHIND_REGION` property on X11.
//! GNOME offers an app no blur at all, so there the page keeps its near solid wash, and so does any other
//! desktop this does not know to blur.

use std::cell::RefCell;
use std::ffi::{c_void, CStr};
use std::os::raw::{c_long, c_ulong};

use gtk::gdk;
use gtk::glib::translate::ToGlibPtr;
use gtk::prelude::*;
use wayland_client::backend::{Backend, ObjectId};
use wayland_client::globals::{registry_queue_init, GlobalListContents};
use wayland_client::protocol::{wl_compositor, wl_region, wl_registry, wl_surface};
use wayland_client::{delegate_noop, Connection, Dispatch, EventQueue, Proxy, QueueHandle};
use wayland_protocols_plasma::blur::client::{org_kde_kwin_blur, org_kde_kwin_blur_manager};

/// A rounded rectangle in the window's own points, such as a panel drawn inside a margin for its shadow.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Rounded {
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
    pub radius: i32,
}

/// Whether this desktop blurs behind a window that asks, which only KDE Plasma does.
pub fn blur_offered() -> bool {
    std::env::var("XDG_CURRENT_DESKTOP")
        .map(|desktop| desktop.split(':').any(|name| name.eq_ignore_ascii_case("KDE")))
        .unwrap_or(false)
}

/// Asks KWin to blur what lies under `shape`; true when the ask was made. Call it on the GTK thread
/// each time the window is shown or resized, since a hidden Wayland window loses its surface.
pub fn blur_behind(window: &gtk::ApplicationWindow, shape: Rounded) -> bool {
    if !blur_offered() {
        return false;
    }
    let Some(gdk_window) = window.window() else {
        return false;
    };
    let display = gdk_window.display();
    match display.type_().name() {
        "GdkWaylandDisplay" => {
            let asked = wayland_blur(&gdk_window, &display, shape).is_some();
            // The blur takes effect with the surface's next commit, which GTK makes when it draws again.
            window.queue_draw();
            asked
        }
        "GdkX11Display" => x11_blur(&gdk_window, &display, shape).is_some(),
        _ => false,
    }
}

/// The shape as rows of rectangles, one per step of each rounded corner, which is all either protocol takes.
pub fn stepped(shape: Rounded, scale: i32) -> Vec<(i32, i32, i32, i32)> {
    let s = |value: i32| value * scale;
    let radius = s(shape.radius.min(shape.width / 2).min(shape.height / 2)).max(0);
    let (x, y, width, height) = (s(shape.x), s(shape.y), s(shape.width), s(shape.height));
    let mut rows = Vec::new();
    let corner = f64::from(radius);
    for step in 0..radius {
        let rise = corner - f64::from(step) - 0.5;
        let inset = (corner - (corner * corner - rise * rise).sqrt()).round() as i32;
        rows.push((x + inset, y + step, width - 2 * inset, 1));
        rows.push((x + inset, y + height - 1 - step, width - 2 * inset, 1));
    }
    rows.push((x, y + radius, width, height - 2 * radius));
    rows
}

/// A GDK function from the library already loaded, looked up at run time so a GDK built without one
/// of its backends still starts.
fn gdk_symbol(name: &CStr) -> Option<*mut c_void> {
    let found = unsafe { libc::dlsym(libc::RTLD_DEFAULT, name.as_ptr()) };
    (!found.is_null()).then_some(found)
}

fn x11_blur(window: &gdk::Window, display: &gdk::Display, shape: Rounded) -> Option<()> {
    type Xid = unsafe extern "C" fn(*mut gdk::ffi::GdkWindow) -> c_ulong;
    type XDisplay = unsafe extern "C" fn(*mut gdk::ffi::GdkDisplay) -> *mut x11_dl::xlib::Display;
    let xid: Xid = unsafe { std::mem::transmute(gdk_symbol(c"gdk_x11_window_get_xid")?) };
    let xdisplay: XDisplay =
        unsafe { std::mem::transmute(gdk_symbol(c"gdk_x11_display_get_xdisplay")?) };
    let xlib = x11_dl::xlib::Xlib::open().ok()?;
    let window_ptr: *mut gdk::ffi::GdkWindow = window.to_glib_none().0;
    let display_ptr: *mut gdk::ffi::GdkDisplay = display.to_glib_none().0;
    let rects: Vec<c_long> = stepped(shape, window.scale_factor())
        .into_iter()
        .flat_map(|(x, y, w, h)| [x, y, w, h].map(c_long::from))
        .collect();
    unsafe {
        let x = xdisplay(display_ptr);
        let atom = (xlib.XInternAtom)(x, c"_KDE_NET_WM_BLUR_BEHIND_REGION".as_ptr(), 0);
        (xlib.XChangeProperty)(
            x,
            xid(window_ptr),
            atom,
            x11_dl::xlib::XA_CARDINAL,
            32,
            x11_dl::xlib::PropModeReplace,
            rects.as_ptr().cast(),
            i32::try_from(rects.len()).ok()?,
        );
        (xlib.XFlush)(x);
    }
    Some(())
}

/// The connection to GTK's own Wayland display and KWin's blur manager, found once.
struct Kwin {
    connection: Connection,
    queue: EventQueue<Blurring>,
    compositor: wl_compositor::WlCompositor,
    manager: org_kde_kwin_blur_manager::OrgKdeKwinBlurManager,
}

thread_local! {
    static KWIN: RefCell<Option<Kwin>> = const { RefCell::new(None) };
}

struct Blurring;

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for Blurring {
    fn event(
        _: &mut Self,
        _: &wl_registry::WlRegistry,
        _: wl_registry::Event,
        _: &GlobalListContents,
        _: &Connection,
        _: &QueueHandle<Self>,
    ) {
    }
}

delegate_noop!(Blurring: ignore wl_compositor::WlCompositor);
delegate_noop!(Blurring: ignore wl_region::WlRegion);
delegate_noop!(Blurring: ignore wl_surface::WlSurface);
delegate_noop!(Blurring: org_kde_kwin_blur_manager::OrgKdeKwinBlurManager);
delegate_noop!(Blurring: org_kde_kwin_blur::OrgKdeKwinBlur);

fn kwin(display: &gdk::Display) -> Option<Kwin> {
    type WlDisplay = unsafe extern "C" fn(*mut gdk::ffi::GdkDisplay) -> *mut c_void;
    let wl_display: WlDisplay =
        unsafe { std::mem::transmute(gdk_symbol(c"gdk_wayland_display_get_wl_display")?) };
    let display_ptr: *mut gdk::ffi::GdkDisplay = display.to_glib_none().0;
    let raw = unsafe { wl_display(display_ptr) };
    if raw.is_null() {
        return None;
    }
    // GTK keeps the display; this only borrows it, with an event queue of its own.
    let backend = unsafe { Backend::from_foreign_display(raw.cast()) };
    let connection = Connection::from_backend(backend);
    let (globals, queue) = registry_queue_init::<Blurring>(&connection).ok()?;
    let handle = queue.handle();
    let compositor = globals.bind(&handle, 1..=4, ()).ok()?;
    let manager = globals.bind(&handle, 1..=1, ()).ok()?;
    Some(Kwin {
        connection,
        queue,
        compositor,
        manager,
    })
}

fn wayland_blur(window: &gdk::Window, display: &gdk::Display, shape: Rounded) -> Option<()> {
    type Surface = unsafe extern "C" fn(*mut gdk::ffi::GdkWindow) -> *mut c_void;
    let surface_of: Surface =
        unsafe { std::mem::transmute(gdk_symbol(c"gdk_wayland_window_get_wl_surface")?) };
    let window_ptr: *mut gdk::ffi::GdkWindow = window.to_glib_none().0;
    let raw = unsafe { surface_of(window_ptr) };
    if raw.is_null() {
        return None;
    }
    KWIN.with(|cell| {
        let mut held = cell.borrow_mut();
        if held.is_none() {
            *held = kwin(display);
        }
        let kwin = held.as_mut()?;
        let id = unsafe { ObjectId::from_ptr(wl_surface::WlSurface::interface(), raw.cast()) }.ok()?;
        let surface = wl_surface::WlSurface::from_id(&kwin.connection, id).ok()?;
        let handle = kwin.queue.handle();
        let region = kwin.compositor.create_region(&handle, ());
        for (x, y, width, height) in stepped(shape, 1) {
            region.add(x, y, width, height);
        }
        let blur = kwin.manager.create(&surface, &handle, ());
        blur.set_region(Some(&region));
        blur.commit();
        region.destroy();
        kwin.connection.flush().ok()?;
        kwin.queue.dispatch_pending(&mut Blurring).ok()?;
        Some(())
    })?;
    Some(())
}

#[cfg(test)]
mod tests {
    use super::{stepped, Rounded};

    #[test]
    fn steps_each_corner_and_fills_the_middle() {
        let shape = Rounded {
            x: 12,
            y: 12,
            width: 300,
            height: 200,
            radius: 4,
        };
        let rows = stepped(shape, 1);
        assert_eq!(rows.len(), 9);
        assert_eq!(rows[8], (12, 16, 300, 192));
        // The first row is the most inset, the last step of a corner barely so.
        assert!(rows[0].0 > rows[6].0);
        assert_eq!(rows[6].2 + 2 * (rows[6].0 - 12), 300);
    }
}
