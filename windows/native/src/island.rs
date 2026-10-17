//! The island on Windows: a window that stays on top, never takes focus from what the person types
//! in, and never shows in the taskbar or the task switcher.

use windows::Win32::Foundation::HWND;
use windows::Win32::UI::WindowsAndMessaging::{
    GetWindowLongPtrW, SetWindowLongPtrW, GWL_EXSTYLE, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW,
};

/// Turns the app's window into the island; `window` is its HWND from the raw window handle.
pub fn make_island(window: isize) {
    let hwnd = HWND(window as *mut _);
    unsafe {
        let style = GetWindowLongPtrW(hwnd, GWL_EXSTYLE);
        SetWindowLongPtrW(
            hwnd,
            GWL_EXSTYLE,
            style | (WS_EX_NOACTIVATE.0 | WS_EX_TOOLWINDOW.0) as isize,
        );
    }
}
