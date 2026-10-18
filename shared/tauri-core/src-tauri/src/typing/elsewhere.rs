//! Any other system, where this crate is only built to be checked: nothing is typed, and it says so.

use super::Focus;

const NOT_HERE: &str = "not on this system";

pub fn focus() -> Focus {
    Focus::default()
}

pub fn type_text(_text: &str) -> Result<(), String> {
    Err(NOT_HERE.into())
}

pub fn backspace(_times: u32) -> Result<(), String> {
    Err(NOT_HERE.into())
}

pub fn clipboard(_text: &str) -> Result<(), String> {
    Err(NOT_HERE.into())
}
