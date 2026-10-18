//! Typing on Windows with SendInput as Unicode keystrokes, which any app takes whatever the keyboard
//! layout, and the focused field read through UI Automation so a password field is never typed into.

use windows::core::PWSTR;
use windows::Win32::Foundation::{CloseHandle, GlobalFree, HANDLE, HGLOBAL};
use windows::Win32::System::Com::{CoCreateInstance, CoInitializeEx, CLSCTX_INPROC_SERVER, COINIT_MULTITHREADED};
use windows::Win32::System::DataExchange::{CloseClipboard, EmptyClipboard, OpenClipboard, SetClipboardData};
use windows::Win32::System::Memory::{GlobalAlloc, GlobalLock, GlobalUnlock, GMEM_MOVEABLE};
use windows::Win32::System::Ole::CF_UNICODETEXT;
use windows::Win32::System::Threading::{OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION};
use windows::Win32::UI::Accessibility::{CUIAutomation, IUIAutomation, IUIAutomationTextPattern, UIA_TextPatternId};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYBD_EVENT_FLAGS, KEYEVENTF_KEYUP, KEYEVENTF_UNICODE, VIRTUAL_KEY, VK_BACK,
    VK_RETURN,
};
use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowTextW, GetWindowThreadProcessId};

use super::{strokes, Focus, Stroke};

/// Keystrokes per SendInput call, small enough that a busy app's input queue never drops any.
const STROKES_PER_SEND: usize = 64;
/// The longest window title or path read.
const LONGEST_NAME: usize = 1024;
/// The longest selection read, since a whole document selected is not an instruction's subject.
const LONGEST_SELECTION: i32 = 20_000;

fn key(vk: VIRTUAL_KEY, scan: u16, flags: KEYBD_EVENT_FLAGS) -> INPUT {
    INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT {
                wVk: vk,
                wScan: scan,
                dwFlags: flags,
                time: 0,
                dwExtraInfo: 0,
            },
        },
    }
}

/// A key down and up for one stroke.
fn pressed(stroke: Stroke) -> [INPUT; 2] {
    match stroke {
        Stroke::Unit(unit) => [
            key(VIRTUAL_KEY(0), unit, KEYEVENTF_UNICODE),
            key(VIRTUAL_KEY(0), unit, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP),
        ],
        Stroke::Enter => [key(VK_RETURN, 0, KEYBD_EVENT_FLAGS(0)), key(VK_RETURN, 0, KEYEVENTF_KEYUP)],
    }
}

fn send(inputs: &[INPUT]) -> Result<(), String> {
    for chunk in inputs.chunks(STROKES_PER_SEND * 2) {
        // SAFETY: every INPUT is a fully formed keyboard input of the size given.
        let sent = unsafe { SendInput(chunk, std::mem::size_of::<INPUT>() as i32) };
        if sent as usize != chunk.len() {
            return Err("Windows would not take the keystrokes, which happens when the app in front runs as administrator".into());
        }
    }
    Ok(())
}

pub fn type_text(text: &str) -> Result<(), String> {
    let inputs: Vec<INPUT> = strokes(text).into_iter().flat_map(pressed).collect();
    send(&inputs)
}

pub fn backspace(times: u32) -> Result<(), String> {
    let inputs: Vec<INPUT> = (0..times)
        .flat_map(|_| [key(VK_BACK, 0, KEYBD_EVENT_FLAGS(0)), key(VK_BACK, 0, KEYEVENTF_KEYUP)])
        .collect();
    send(&inputs)
}

pub fn clipboard(text: &str) -> Result<(), String> {
    let mut units: Vec<u16> = text.encode_utf16().collect();
    units.push(0);
    let bytes = units.len() * std::mem::size_of::<u16>();
    // SAFETY: the memory is allocated, filled and handed to the clipboard, which owns it once set.
    unsafe {
        OpenClipboard(None).map_err(|error| format!("the clipboard is busy: {error}"))?;
        let done = (|| -> Result<(), String> {
            EmptyClipboard().map_err(|error| error.to_string())?;
            let memory: HGLOBAL = GlobalAlloc(GMEM_MOVEABLE, bytes).map_err(|error| error.to_string())?;
            let into = GlobalLock(memory) as *mut u16;
            if into.is_null() {
                let _ = GlobalFree(Some(memory));
                return Err("the clipboard memory could not be written".into());
            }
            std::ptr::copy_nonoverlapping(units.as_ptr(), into, units.len());
            let _ = GlobalUnlock(memory);
            if let Err(error) = SetClipboardData(u32::from(CF_UNICODETEXT.0), Some(HANDLE(memory.0))) {
                let _ = GlobalFree(Some(memory));
                return Err(error.to_string());
            }
            Ok(())
        })();
        let _ = CloseClipboard();
        done
    }
}

pub fn focus() -> Focus {
    // SAFETY: plain reads of the foreground window and its process, each handle closed after use.
    let (app, title) = unsafe {
        let window = GetForegroundWindow();
        let mut text = vec![0u16; LONGEST_NAME];
        let length = GetWindowTextW(window, &mut text);
        let title = (length > 0).then(|| String::from_utf16_lossy(&text[..length as usize]));
        let mut pid = 0u32;
        GetWindowThreadProcessId(window, Some(&mut pid));
        (executable(pid), title)
    };
    let (secure, selection) = focused_field();
    Focus {
        app,
        title,
        secure,
        selection,
    }
}

/// The executable's file stem, lowercased, such as "slack" for Slack.exe.
unsafe fn executable(pid: u32) -> Option<String> {
    if pid == 0 {
        return None;
    }
    // SAFETY: the handle is closed before returning.
    unsafe {
        let process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).ok()?;
        let mut path = vec![0u16; LONGEST_NAME];
        let mut size = path.len() as u32;
        let read = QueryFullProcessImageNameW(process, PROCESS_NAME_WIN32, PWSTR(path.as_mut_ptr()), &mut size);
        let _ = CloseHandle(process);
        read.ok()?;
        let path = String::from_utf16_lossy(&path[..size as usize]);
        std::path::Path::new(&path)
            .file_stem()
            .map(|stem| stem.to_string_lossy().to_lowercase())
    }
}

/// Whether the focused field is a password, and what is selected in it, from UI Automation; a field that
/// cannot be read counts as not secure, since most apps that hide it are not password fields.
fn focused_field() -> (bool, Option<String>) {
    // SAFETY: COM is initialised for this thread first; an earlier choice of apartment is fine to keep.
    unsafe {
        let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
        let Ok(automation) = CoCreateInstance::<_, IUIAutomation>(&CUIAutomation, None, CLSCTX_INPROC_SERVER) else {
            return (false, None);
        };
        let Ok(element) = automation.GetFocusedElement() else {
            return (false, None);
        };
        let secure = element.CurrentIsPassword().map(|secure| secure.as_bool()).unwrap_or(false);
        if secure {
            return (true, None);
        }
        let selection = element
            .GetCurrentPatternAs::<IUIAutomationTextPattern>(UIA_TextPatternId)
            .and_then(|pattern| pattern.GetSelection())
            .ok()
            .and_then(|ranges| {
                if ranges.Length().ok()? < 1 {
                    return None;
                }
                let text = ranges.GetElement(0).ok()?.GetText(LONGEST_SELECTION).ok()?;
                let text = text.to_string();
                (!text.trim().is_empty()).then_some(text)
            });
        (false, selection)
    }
}
