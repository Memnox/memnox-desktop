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

/// Whether the layout of the app in front types characters with AltGr: any key that gives a character
/// with Ctrl and Alt held, which is what AltGr sends. US English gives none; most European layouts do.
pub fn has_altgr() -> Option<bool> {
    use windows::Win32::UI::Input::KeyboardAndMouse::{GetKeyboardLayout, MapVirtualKeyExW, ToUnicodeEx, MAPVK_VK_TO_VSC, VK_CONTROL, VK_MENU};
    use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId};
    /// Down, in the key state array ToUnicodeEx reads.
    const HELD: u8 = 0x80;
    /// Leaves the keyboard's dead key state alone, so a check never eats the person's next accent.
    const KEEP_STATE: u32 = 0x4;
    // The letter and digit rows and the punctuation keys, where AltGr characters live.
    let keys = (0x30..=0x5A_u32).chain(0xBA..=0xC0).chain(0xDB..=0xDF).chain([0xE2]);
    // SAFETY: plain reads of the foreground thread's layout and of what keys give under it.
    unsafe {
        let thread = GetWindowThreadProcessId(GetForegroundWindow(), None);
        let layout = GetKeyboardLayout(thread);
        let mut state = [0_u8; 256];
        state[VK_CONTROL.0 as usize] = HELD;
        state[VK_MENU.0 as usize] = HELD;
        for vk in keys {
            let scan = MapVirtualKeyExW(vk, MAPVK_VK_TO_VSC, Some(layout));
            let mut out = [0_u16; 4];
            if ToUnicodeEx(vk, scan, &state, &mut out, KEEP_STATE, Some(layout)) > 0 {
                return Some(true);
            }
        }
        Some(false)
    }
}
