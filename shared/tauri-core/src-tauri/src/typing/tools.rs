//! The Linux programs that type, take back and copy, chosen by the kind of session, since Wayland lets
//! only its own tools type into other apps and X11 has xdotool. Pure, so the choice is tested anywhere.

#![cfg_attr(not(target_os = "linux"), allow(dead_code))]

/// A program and its arguments.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Run {
    pub program: &'static str,
    pub args: Vec<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Typer {
    Wtype,
    Ydotool,
    Xdotool,
}

/// Whether the session is Wayland, from the values of `WAYLAND_DISPLAY` and `XDG_SESSION_TYPE`.
pub fn is_wayland(wayland_display: Option<&str>, session_type: Option<&str>) -> bool {
    wayland_display.is_some_and(|display| !display.is_empty()) || session_type == Some("wayland")
}

/// The typers to try in order: Wayland's own first there, xdotool first on X11, and the rest as fallbacks.
pub fn typers(wayland: bool) -> [Typer; 3] {
    if wayland {
        [Typer::Wtype, Typer::Ydotool, Typer::Xdotool]
    } else {
        [Typer::Xdotool, Typer::Ydotool, Typer::Wtype]
    }
}

pub fn typing(typer: Typer, text: &str) -> Run {
    match typer {
        Typer::Wtype => Run {
            program: "wtype",
            args: vec!["--".into(), text.into()],
        },
        Typer::Ydotool => Run {
            program: "ydotool",
            args: vec!["type".into(), "--".into(), text.into()],
        },
        Typer::Xdotool => Run {
            program: "xdotool",
            args: vec![
                "type".into(),
                "--clearmodifiers".into(),
                "--delay".into(),
                "0".into(),
                "--".into(),
                text.into(),
            ],
        },
    }
}

/// The Linux input code of Backspace, which ydotool presses by number.
const BACKSPACE_CODE: &str = "14";

pub fn backspacing(typer: Typer, times: u32) -> Run {
    let times = times as usize;
    match typer {
        Typer::Wtype => Run {
            program: "wtype",
            args: ["-k", "BackSpace"].repeat(times).into_iter().map(String::from).collect(),
        },
        Typer::Ydotool => Run {
            program: "ydotool",
            args: std::iter::once("key".to_string())
                .chain(
                    std::iter::repeat_n(
                        [format!("{BACKSPACE_CODE}:1"), format!("{BACKSPACE_CODE}:0")],
                        times,
                    )
                    .flatten(),
                )
                .collect(),
        },
        Typer::Xdotool => Run {
            program: "xdotool",
            args: vec![
                "key".into(),
                "--clearmodifiers".into(),
                "--repeat".into(),
                times.to_string(),
                "--delay".into(),
                "0".into(),
                "BackSpace".into(),
            ],
        },
    }
}

/// What to install, said when no typer is there at all.
pub fn missing_typer(wayland: bool) -> String {
    if wayland {
        "Typing into other apps needs wtype or ydotool on Wayland; install one and try again".into()
    } else {
        "Typing into other apps needs xdotool; install it and try again".into()
    }
}

/// The clipboard programs to try in order, each reading the text on its standard input.
pub fn clipboards(wayland: bool) -> Vec<Run> {
    let wl = Run {
        program: "wl-copy",
        args: vec![],
    };
    let xclip = Run {
        program: "xclip",
        args: vec!["-selection".into(), "clipboard".into()],
    };
    let xsel = Run {
        program: "xsel",
        args: vec!["-b".into(), "-i".into()],
    };
    if wayland {
        vec![wl, xclip, xsel]
    } else {
        vec![xclip, xsel, wl]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chooses_the_session_own_typer_first() {
        assert!(is_wayland(Some("wayland-0"), None));
        assert!(is_wayland(None, Some("wayland")));
        assert!(!is_wayland(Some(""), Some("x11")));
        assert_eq!(typers(true)[0], Typer::Wtype);
        assert_eq!(typers(false)[0], Typer::Xdotool);
        assert_eq!(clipboards(true)[0].program, "wl-copy");
        assert_eq!(clipboards(false)[0].program, "xclip");
    }

    #[test]
    fn types_text_that_starts_with_a_dash_as_text() {
        assert_eq!(typing(Typer::Wtype, "-x").args, vec!["--", "-x"]);
        assert_eq!(typing(Typer::Xdotool, "hi").args.last().unwrap(), "hi");
    }

    #[test]
    fn takes_back_as_many_characters_as_asked() {
        assert_eq!(backspacing(Typer::Wtype, 2).args, vec!["-k", "BackSpace", "-k", "BackSpace"]);
        assert_eq!(backspacing(Typer::Ydotool, 1).args, vec!["key", "14:1", "14:0"]);
        assert!(backspacing(Typer::Xdotool, 3).args.contains(&"3".to_string()));
    }
}
