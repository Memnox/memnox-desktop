//! Typing on Linux through the session's own tools, wtype or ydotool on Wayland and xdotool on X11, or
//! the RemoteDesktop portal where the compositor has no virtual keyboard, as on GNOME. The app in front
//! comes from X11 where it can, and the field itself, a password or not, its selection and its text, from
//! AT-SPI, which also names the app on Wayland where X11 sees nothing.

use std::ffi::CString;
use std::io::{ErrorKind, Write};
use std::os::raw::{c_int, c_long, c_uchar, c_ulong};
use std::process::{Command, Stdio};

use x11_dl::xlib::{self, Display, Xlib};

use super::tools::{self, Run};
use super::{accessibility, portal, Focus};

fn wayland() -> bool {
    tools::is_wayland(
        std::env::var("WAYLAND_DISPLAY").ok().as_deref(),
        std::env::var("XDG_SESSION_TYPE").ok().as_deref(),
    )
}

/// Runs each program in turn until one works; a missing one is skipped, and a failing one is remembered.
fn first_that_works(
    runs: impl IntoIterator<Item = Run>,
    input: Option<&str>,
    missing: String,
) -> Result<(), String> {
    let mut failed: Option<String> = None;
    for run in runs {
        let mut command = Command::new(run.program);
        command
            .args(&run.args)
            .stdin(if input.is_some() {
                Stdio::piped()
            } else {
                Stdio::null()
            })
            .stdout(Stdio::null())
            .stderr(Stdio::piped());
        let mut child = match command.spawn() {
            Ok(child) => child,
            Err(error) if error.kind() == ErrorKind::NotFound => continue,
            Err(error) => {
                failed = Some(format!("{} could not start: {error}", run.program));
                continue;
            }
        };
        if let (Some(text), Some(mut stdin)) = (input, child.stdin.take()) {
            let _ = stdin.write_all(text.as_bytes());
        }
        match child.wait_with_output() {
            Ok(output) if output.status.success() => return Ok(()),
            Ok(output) => {
                let said = String::from_utf8_lossy(&output.stderr).trim().to_string();
                failed = Some(format!("{} did not type: {said}", run.program));
            }
            Err(error) => failed = Some(format!("{} stopped: {error}", run.program)),
        }
    }
    Err(failed.unwrap_or(missing))
}

/// GNOME's Mutter offers no virtual keyboard, so wtype cannot type there and the portal goes first.
fn gnome() -> bool {
    std::env::var("XDG_CURRENT_DESKTOP").is_ok_and(|desktop| {
        desktop
            .split(':')
            .any(|each| each.eq_ignore_ascii_case("gnome"))
    })
}

/// The portal first on GNOME Wayland, the session's own tools first elsewhere, and the other one after.
fn typed(
    tools_way: impl FnOnce() -> Result<(), String>,
    portal_way: impl FnOnce() -> Result<(), String>,
) -> Result<(), String> {
    if !wayland() {
        return tools_way();
    }
    if gnome() {
        return portal_way().or_else(|why| tools_way().map_err(|_| why));
    }
    tools_way().or_else(|why| portal_way().map_err(|_| why))
}

pub fn type_text(text: &str) -> Result<(), String> {
    let wayland = wayland();
    typed(
        || {
            let runs = tools::typers(wayland).map(|typer| tools::typing(typer, text));
            first_that_works(runs, None, tools::missing_typer(wayland))
        },
        || portal::type_text(text),
    )
}

pub fn backspace(times: u32) -> Result<(), String> {
    if times == 0 {
        return Ok(());
    }
    let wayland = wayland();
    typed(
        || {
            let runs = tools::typers(wayland).map(|typer| tools::backspacing(typer, times));
            first_that_works(runs, None, tools::missing_typer(wayland))
        },
        || portal::backspace(times),
    )
}

pub fn clipboard(text: &str) -> Result<(), String> {
    let wayland = wayland();
    let missing = if wayland {
        "Copying needs wl-copy from wl-clipboard; install it and try again".to_string()
    } else {
        "Copying needs xclip or xsel; install one and try again".to_string()
    };
    first_that_works(tools::clipboards(wayland), Some(text), missing)
}

/// The app in front and its field: X11's hints for the app where an X11 window is in front, AT-SPI for
/// the field, and for the app too on Wayland, where X11 only ever sees an XWayland window.
pub fn focus() -> Focus {
    let mut focus = x11_focus();
    if let Some(field) = accessibility::read() {
        if focus.app.is_none() || wayland() {
            focus.app = field.app.or(focus.app);
        }
        focus.secure = field.secure;
        focus.selection = field.selection;
        focus.value = field.value;
        focus.caret = field.caret;
        focus.selection_end = field.selection_end;
    }
    focus
}

fn x11_focus() -> Focus {
    let Ok(xlib) = Xlib::open() else {
        return Focus::default();
    };
    // SAFETY: a null name opens the display named by DISPLAY; it is closed before returning.
    let display = unsafe { (xlib.XOpenDisplay)(std::ptr::null()) };
    if display.is_null() {
        return Focus::default();
    }
    let focus = read_focus(&xlib, display);
    // SAFETY: opened above and not used after.
    unsafe { (xlib.XCloseDisplay)(display) };
    focus
}

fn read_focus(xlib: &Xlib, display: *mut Display) -> Focus {
    // SAFETY: the display is open.
    let root = unsafe { (xlib.XDefaultRootWindow)(display) };
    let Some(window) = property(xlib, display, root, "_NET_ACTIVE_WINDOW", xlib::XA_WINDOW)
        .and_then(|bytes| first_long(&bytes))
        .filter(|window| *window != 0)
    else {
        return Focus::default();
    };
    let window = window as c_ulong;
    let utf8 = atom(xlib, display, "UTF8_STRING");
    let title = property(xlib, display, window, "_NET_WM_NAME", utf8)
        .or_else(|| property(xlib, display, window, "WM_NAME", xlib::XA_STRING))
        .map(|bytes| {
            String::from_utf8_lossy(&bytes)
                .trim_end_matches('\0')
                .to_string()
        })
        .filter(|title| !title.is_empty());
    let app = property(xlib, display, window, "_NET_WM_PID", xlib::XA_CARDINAL)
        .and_then(|bytes| first_long(&bytes))
        .and_then(|pid| std::fs::read_to_string(format!("/proc/{pid}/comm")).ok())
        .map(|name| name.trim().to_lowercase())
        .filter(|name| !name.is_empty());
    Focus {
        app,
        title,
        ..Focus::default()
    }
}

fn atom(xlib: &Xlib, display: *mut Display, name: &str) -> c_ulong {
    let Ok(name) = CString::new(name) else {
        return 0;
    };
    // SAFETY: the display is open and the name is a valid C string.
    unsafe { (xlib.XInternAtom)(display, name.as_ptr(), xlib::False) }
}

/// A window property's raw bytes; a 32 bit format comes back as one C long per item, as Xlib hands it over.
fn property(
    xlib: &Xlib,
    display: *mut Display,
    window: c_ulong,
    name: &str,
    kind: c_ulong,
) -> Option<Vec<u8>> {
    let property = atom(xlib, display, name);
    if property == 0 {
        return None;
    }
    let mut actual: c_ulong = 0;
    let mut format: c_int = 0;
    let mut items: c_ulong = 0;
    let mut after: c_ulong = 0;
    let mut data: *mut c_uchar = std::ptr::null_mut();
    // SAFETY: every out pointer is valid, and the data is freed with XFree below.
    let status = unsafe {
        (xlib.XGetWindowProperty)(
            display,
            window,
            property,
            0,
            1024,
            xlib::False,
            kind,
            &mut actual,
            &mut format,
            &mut items,
            &mut after,
            &mut data,
        )
    };
    if status != xlib::Success as c_int || data.is_null() {
        return None;
    }
    let width = match format {
        8 => 1,
        16 => std::mem::size_of::<std::os::raw::c_short>(),
        32 => std::mem::size_of::<c_long>(),
        _ => 0,
    };
    // SAFETY: Xlib returned `items` items of `width` bytes each at `data`.
    let bytes = unsafe { std::slice::from_raw_parts(data, items as usize * width) }.to_vec();
    // SAFETY: data came from XGetWindowProperty.
    unsafe { (xlib.XFree)(data.cast()) };
    (!bytes.is_empty()).then_some(bytes)
}

fn first_long(bytes: &[u8]) -> Option<i64> {
    let width = std::mem::size_of::<c_long>();
    let first: [u8; 8] = match width {
        8 => bytes.get(..8)?.try_into().ok()?,
        _ => {
            let mut wide = [0u8; 8];
            wide[..4].copy_from_slice(bytes.get(..4)?);
            wide
        }
    };
    Some(i64::from_ne_bytes(first))
}
