//! The pointer anywhere on the screen and whether a mouse button is down, read the way each system
//! allows: `GetCursorPos` and `GetAsyncKeyState` on Windows, `XQueryPointer` on X11. Wayland gives no app
//! either, so there is no reader at all and the input region does the work alone. Also the window the
//! person was typing in, kept while a window of ours borrows the keyboard and handed back after.

use tauri::PhysicalPosition;

/// One look at the pointer: where it is in physical pixels, when that can be told, and whether a button is down.
pub struct Reading {
    pub at: Option<PhysicalPosition<f64>>,
    pub pressed: bool,
}

#[cfg(windows)]
mod system {
    use std::sync::Mutex;

    use tauri::{PhysicalPosition, WebviewWindow};
    use windows::Win32::Foundation::{HWND, POINT};
    use windows::Win32::UI::Input::KeyboardAndMouse::{GetAsyncKeyState, VK_LBUTTON, VK_MBUTTON, VK_RBUTTON};
    use windows::Win32::UI::WindowsAndMessaging::{GetCursorPos, GetForegroundWindow, IsWindow, SetForegroundWindow};

    use super::Reading;

    /// The high bit says the button is down now; the low bit says it went down since the last look, so a
    /// click quicker than one poll is still heard.
    const DOWN: u16 = 0x8000;
    const WENT_DOWN: u16 = 0x0001;

    pub struct Reader;

    impl Reader {
        pub fn open() -> Option<Self> {
            Some(Self)
        }

        pub fn read(&mut self, _window: &WebviewWindow) -> Reading {
            let mut point = POINT::default();
            let at = unsafe { GetCursorPos(&mut point) }
                .ok()
                .map(|()| PhysicalPosition::new(f64::from(point.x), f64::from(point.y)));
            let pressed = [VK_LBUTTON, VK_RBUTTON, VK_MBUTTON]
                .into_iter()
                .any(|button| unsafe { GetAsyncKeyState(i32::from(button.0)) } as u16 & (DOWN | WENT_DOWN) != 0);
            Reading { at, pressed }
        }
    }

    /// The window that had the keyboard before one of ours took it.
    static BEFORE: Mutex<Option<isize>> = Mutex::new(None);

    pub fn remember_foreground(ours: isize) {
        let front = unsafe { GetForegroundWindow() }.0 as isize;
        if front != 0 && front != ours {
            if let Ok(mut before) = BEFORE.lock() {
                *before = Some(front);
            }
        }
    }

    /// Hands the keyboard back only while ours still holds it, so a window the person clicked since keeps it.
    pub fn give_back_foreground(ours: isize) {
        let Some(before) = BEFORE.lock().ok().and_then(|mut before| before.take()) else {
            return;
        };
        let front = unsafe { GetForegroundWindow() }.0 as isize;
        let before = HWND(before as *mut _);
        if front == ours && unsafe { IsWindow(Some(before)) }.as_bool() {
            let _ = unsafe { SetForegroundWindow(before) };
        }
    }
}

#[cfg(target_os = "linux")]
mod system {
    use std::ffi::CString;
    use std::os::raw::{c_int, c_long, c_uchar, c_uint, c_ulong};
    use std::sync::Mutex;

    use tauri::{PhysicalPosition, WebviewWindow};
    use x11_dl::xlib::{self, Display, Xlib};

    use super::Reading;

    /// Any of the first three buttons down, as a press anywhere.
    const BUTTONS: c_uint = xlib::Button1Mask | xlib::Button2Mask | xlib::Button3Mask;
    /// Asked to raise a window as a pager would, which window managers honour without the focus rules.
    const FROM_PAGER: c_long = 2;

    fn wayland() -> bool {
        let backend = std::env::var("GDK_BACKEND").unwrap_or_default();
        if backend.starts_with("x11") {
            return false;
        }
        std::env::var_os("WAYLAND_DISPLAY").is_some() || std::env::var("XDG_SESSION_TYPE").is_ok_and(|kind| kind == "wayland")
    }

    /// A connection of its own to the X server, used only by the thread that follows the pointer.
    pub struct Reader {
        xlib: Xlib,
        display: *mut Display,
    }

    // The connection is opened, used and closed on the one thread that owns the reader.
    unsafe impl Send for Reader {}

    impl Reader {
        pub fn open() -> Option<Self> {
            if wayland() {
                return None;
            }
            let xlib = Xlib::open().ok()?;
            let display = unsafe { (xlib.XOpenDisplay)(std::ptr::null()) };
            (!display.is_null()).then_some(Self { xlib, display })
        }

        pub fn read(&mut self, _window: &WebviewWindow) -> Reading {
            let (mut root, mut child) = (0, 0);
            let (mut x, mut y, mut window_x, mut window_y) = (0, 0, 0, 0);
            let mut mask: c_uint = 0;
            let found = unsafe {
                let screen_root = (self.xlib.XDefaultRootWindow)(self.display);
                (self.xlib.XQueryPointer)(
                    self.display,
                    screen_root,
                    &mut root,
                    &mut child,
                    &mut x,
                    &mut y,
                    &mut window_x,
                    &mut window_y,
                    &mut mask,
                )
            };
            Reading {
                at: (found != 0).then(|| PhysicalPosition::new(f64::from(x), f64::from(y))),
                pressed: mask & BUTTONS != 0,
            }
        }
    }

    impl Drop for Reader {
        fn drop(&mut self) {
            unsafe { (self.xlib.XCloseDisplay)(self.display) };
        }
    }

    /// The X11 window that had the keyboard before one of ours took it.
    static BEFORE: Mutex<Option<c_ulong>> = Mutex::new(None);

    fn atom(xlib: &Xlib, display: *mut Display, name: &str) -> c_ulong {
        let name = CString::new(name).unwrap_or_default();
        unsafe { (xlib.XInternAtom)(display, name.as_ptr(), xlib::False) }
    }

    fn active_window(xlib: &Xlib, display: *mut Display) -> Option<c_ulong> {
        let root = unsafe { (xlib.XDefaultRootWindow)(display) };
        let property = atom(xlib, display, "_NET_ACTIVE_WINDOW");
        let (mut kind, mut format, mut count, mut after) = (0, 0 as c_int, 0, 0);
        let mut data: *mut c_uchar = std::ptr::null_mut();
        let read = unsafe {
            (xlib.XGetWindowProperty)(display, root, property, 0, 1, xlib::False, xlib::XA_WINDOW, &mut kind, &mut format, &mut count, &mut after, &mut data)
        };
        if read != 0 || data.is_null() {
            return None;
        }
        let window = (count == 1 && format == 32).then(|| unsafe { *(data as *const c_ulong) });
        unsafe { (xlib.XFree)(data.cast()) };
        window.filter(|window| *window != 0)
    }

    fn with_display<T>(act: impl FnOnce(&Xlib, *mut Display) -> T) -> Option<T> {
        if wayland() {
            return None;
        }
        let xlib = Xlib::open().ok()?;
        let display = unsafe { (xlib.XOpenDisplay)(std::ptr::null()) };
        if display.is_null() {
            return None;
        }
        let done = act(&xlib, display);
        unsafe { (xlib.XCloseDisplay)(display) };
        Some(done)
    }

    /// On Wayland the layer surface's keyboard mode gives the keyboard back by itself, so only X11 keeps one.
    pub fn remember_foreground(_ours: isize) {
        if let Some(Some(front)) = with_display(active_window) {
            if let Ok(mut before) = BEFORE.lock() {
                *before = Some(front);
            }
        }
    }

    pub fn give_back_foreground(_ours: isize) {
        let Some(before) = BEFORE.lock().ok().and_then(|mut before| before.take()) else {
            return;
        };
        with_display(|xlib, display| {
            let root = unsafe { (xlib.XDefaultRootWindow)(display) };
            let mut event: xlib::XEvent = unsafe { std::mem::zeroed() };
            let message = unsafe { &mut event.client_message };
            message.type_ = xlib::ClientMessage;
            message.window = before;
            message.message_type = atom(xlib, display, "_NET_ACTIVE_WINDOW");
            message.format = 32;
            message.data.set_long(0, FROM_PAGER);
            message.data.set_long(1, xlib::CurrentTime as c_long);
            unsafe {
                (xlib.XSendEvent)(display, root, xlib::False, xlib::SubstructureRedirectMask | xlib::SubstructureNotifyMask, &mut event);
                (xlib.XFlush)(display);
            }
        });
    }
}

#[cfg(not(any(windows, target_os = "linux")))]
mod system {
    use tauri::WebviewWindow;

    use super::Reading;

    /// Elsewhere, as when this crate is checked on a Mac, the pointer comes from the window and no press is heard.
    pub struct Reader;

    impl Reader {
        pub fn open() -> Option<Self> {
            Some(Self)
        }

        pub fn read(&mut self, window: &WebviewWindow) -> Reading {
            Reading {
                at: window.cursor_position().ok(),
                pressed: false,
            }
        }
    }

}

pub use system::Reader;
#[cfg(any(windows, target_os = "linux"))]
pub use system::{give_back_foreground, remember_foreground};
