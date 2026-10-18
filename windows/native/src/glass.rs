//! What the glass behind a window needs from Windows beyond `window-vibrancy`: whether this is Windows 11,
//! where the system backdrop and rounded corners exist, and the round corners themselves. Windows 10 has
//! neither, so there the page keeps its near solid wash and square edges are never shown under glass.

use windows::Wdk::System::SystemServices::RtlGetVersion;
use windows::Win32::Foundation::HWND;
use windows::Win32::Graphics::Dwm::{
    DwmSetWindowAttribute, DWMWA_WINDOW_CORNER_PREFERENCE, DWMWCP_ROUND,
};
use windows::Win32::System::SystemInformation::OSVERSIONINFOW;

/// The first build of Windows 11, where Mica, the acrylic backdrop and rounded corners arrived.
const WINDOWS_11: u32 = 22_000;

/// Whether the system is Windows 11 or later, read from the kernel since `GetVersionEx` may be told less.
pub fn is_windows_11() -> bool {
    let mut info = OSVERSIONINFOW {
        dwOSVersionInfoSize: u32::try_from(std::mem::size_of::<OSVERSIONINFOW>()).unwrap_or(0),
        ..Default::default()
    };
    let status = unsafe { RtlGetVersion(&mut info) };
    status.is_ok() && info.dwMajorVersion >= 10 && info.dwBuildNumber >= WINDOWS_11
}

/// Rounds a borderless window's corners as Windows 11 rounds its own menus, with the system's shadow.
pub fn round_corners(hwnd: isize) -> bool {
    let preference = DWMWCP_ROUND;
    unsafe {
        DwmSetWindowAttribute(
            HWND(hwnd as *mut _),
            DWMWA_WINDOW_CORNER_PREFERENCE,
            std::ptr::from_ref(&preference).cast(),
            u32::try_from(std::mem::size_of_val(&preference)).unwrap_or(0),
        )
    }
    .is_ok()
}
