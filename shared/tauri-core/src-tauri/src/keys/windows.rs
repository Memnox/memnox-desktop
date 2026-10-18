//! Keys seen from anywhere on Windows through a low level keyboard hook, which needs no permission and
//! sees every app. The hook only looks: every key is passed on, so nothing the person types is lost.

use std::cell::RefCell;
use std::sync::mpsc::channel;
use std::thread;

use windows::Win32::Foundation::{LPARAM, LRESULT, WPARAM};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::WindowsAndMessaging::{
    CallNextHookEx, DispatchMessageW, GetMessageW, SetWindowsHookExW, TranslateMessage, HC_ACTION,
    KBDLLHOOKSTRUCT, LLKHF_EXTENDED, LLKHF_INJECTED, MSG, WH_KEYBOARD_LL, WM_KEYDOWN, WM_KEYUP,
    WM_SYSKEYDOWN, WM_SYSKEYUP,
};

use super::event::{windows_key, Pressed, Reporter, Seen, Sink};

/// The hook runs on the thread that set it, so what it remembers lives on that thread.
struct Watch {
    reporter: Reporter,
    pressed: Pressed,
}

thread_local! {
    static WATCH: RefCell<Option<Watch>> = const { RefCell::new(None) };
}

/// Sets the hook on a thread of its own with the message loop a low level hook needs, and returns once it is set.
pub fn watch(sink: Sink) -> Result<(), String> {
    let (ready, set) = channel();
    thread::Builder::new()
        .name("memnox-keys".into())
        .spawn(move || {
            WATCH.with(|watch| {
                *watch.borrow_mut() = Some(Watch {
                    reporter: Reporter::new(sink),
                    pressed: Pressed::default(),
                })
            });
            // SAFETY: the hook procedure is a plain function for the life of the process.
            let hooked = unsafe {
                let module = GetModuleHandleW(None).ok().map(|module| module.into());
                SetWindowsHookExW(WH_KEYBOARD_LL, Some(seen), module, 0)
            };
            if let Err(error) = hooked {
                let _ = ready.send(Err(format!("Windows would not let Memnox see the keys: {error}")));
                return;
            }
            let _ = ready.send(Ok(()));
            let mut message = MSG::default();
            // SAFETY: a standard message loop on the hook's own thread, which is what keeps the hook called.
            unsafe {
                while GetMessageW(&mut message, None, 0, 0).as_bool() {
                    let _ = TranslateMessage(&message);
                    DispatchMessageW(&message);
                }
            }
        })
        .map_err(|error| error.to_string())?;
    set.recv()
        .map_err(|_| "the key watcher stopped before it started".to_string())?
}

unsafe extern "system" fn seen(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if code == HC_ACTION as i32 {
        // SAFETY: for WH_KEYBOARD_LL with HC_ACTION, lparam points at a KBDLLHOOKSTRUCT.
        let info = unsafe { &*(lparam.0 as *const KBDLLHOOKSTRUCT) };
        let message = wparam.0 as u32;
        let down = message == WM_KEYDOWN || message == WM_SYSKEYDOWN;
        let up = message == WM_KEYUP || message == WM_SYSKEYUP;
        // Keys Memnox types itself are not the person's, so dictation typing never reads as a key pressed.
        let injected = info.flags.0 & LLKHF_INJECTED.0 != 0;
        if (down || up) && !injected {
            let extended = info.flags.0 & LLKHF_EXTENDED.0 != 0;
            WATCH.with(|watch| {
                if let Some(watch) = watch.borrow_mut().as_mut() {
                    match windows_key(info.vkCode, info.scanCode, extended) {
                        Seen::Modifier(modifier) => {
                            watch.pressed.set(modifier, down);
                            watch.reporter.modifiers(watch.pressed);
                        }
                        Seen::Other if down => watch.reporter.key(),
                        Seen::Other | Seen::Ignored => {}
                    }
                }
            });
        }
    }
    // SAFETY: passing the event on unchanged, as every hook must.
    unsafe { CallNextHookEx(None, code, wparam, lparam) }
}
