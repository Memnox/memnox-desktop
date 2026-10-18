//! The one way the focus module runs another program: with no window of its own, nothing on its input,
//! a time limit, and why it gave no answer in words the voice can say.

use std::io::Read;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

/// Long enough for a terminal's command line to answer from its running instance, short enough that a
/// socket nobody listens on never holds the voice.
pub const CLI_WAIT: Duration = Duration::from_secs(4);
/// An editor's command line may start the editor itself, which takes longer than handing over a folder.
pub const EDITOR_WAIT: Duration = Duration::from_secs(15);
/// How often a running command is checked for having finished.
const CLI_POLL: Duration = Duration::from_millis(20);
/// Keeps a console program from flashing a window of its own, as `runtime.rs` runs its commands.
#[cfg(windows)]
const NO_WINDOW: u32 = 0x0800_0000;

/// Why a command did not give its answer.
#[derive(Debug, PartialEq, Eq)]
pub enum Failure {
    /// The program is not installed, or not on the path.
    Missing,
    /// It ran and refused, with what it said.
    Said(String),
    /// It did not finish in time and was stopped.
    Slow,
}

impl Failure {
    /// As the voice says it, naming the tool.
    pub fn said(&self, tool: &str) -> String {
        match self {
            Failure::Missing => format!("{tool} is not installed here"),
            Failure::Said(why) if why.is_empty() => format!("{tool} refused"),
            Failure::Said(why) => format!("{tool} said {why}"),
            Failure::Slow => format!("{tool} did not answer in time"),
        }
    }
}

/// A program with no window of its own and nothing on its input.
pub fn command(program: &str) -> Command {
    let mut command = Command::new(program);
    command.stdin(Stdio::null());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(NO_WINDOW);
    }
    command
}

/// Runs a command to its end and gives what it printed, stopping it once `wait` has passed.
pub fn run(mut command: Command, wait: Duration) -> Result<String, Failure> {
    let mut child = command
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| match error.kind() {
            std::io::ErrorKind::NotFound => Failure::Missing,
            _ => Failure::Said(error.to_string()),
        })?;
    // Read on their own threads, so a long listing never fills the pipe while the command waits on it.
    let reader = |stream: Option<Box<dyn Read + Send>>| {
        std::thread::spawn(move || {
            let mut text = String::new();
            if let Some(mut stream) = stream {
                let _ = stream.read_to_string(&mut text);
            }
            text
        })
    };
    let out = reader(child.stdout.take().map(|stream| Box::new(stream) as Box<dyn Read + Send>));
    let err = reader(child.stderr.take().map(|stream| Box::new(stream) as Box<dyn Read + Send>));
    let started = Instant::now();
    let status = loop {
        match child.try_wait() {
            Ok(Some(status)) => break status,
            Ok(None) if started.elapsed() < wait => std::thread::sleep(CLI_POLL),
            Ok(None) => {
                let _ = child.kill();
                let _ = child.wait();
                return Err(Failure::Slow);
            }
            Err(error) => return Err(Failure::Said(error.to_string())),
        }
    };
    let out = out.join().unwrap_or_default();
    let err = err.join().unwrap_or_default();
    if status.success() {
        Ok(out)
    } else {
        Err(Failure::Said(first_line(&err)))
    }
}

/// The first line a tool wrote, enough to say why without reading its whole complaint aloud.
fn first_line(text: &str) -> String {
    text.lines().map(str::trim).find(|line| !line.is_empty()).unwrap_or("").to_string()
}

/// A link opened by the system's URL handler, which hands it to the app registered for its scheme.
pub fn open_url(url: &str) -> Result<(), String> {
    let mut opener = if cfg!(windows) {
        // rundll32 takes the link whole, where cmd's start would read an ampersand in it as a second command.
        let mut opener = command("rundll32");
        opener.args(["url.dll,FileProtocolHandler", url]);
        opener
    } else {
        let mut opener = command("xdg-open");
        opener.arg(url);
        opener
    };
    opener
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map(|_| ())
        .map_err(|error| format!("the link handler would not start: {error}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn says_why_a_command_gave_no_answer() {
        assert_eq!(Failure::Missing.said("WezTerm"), "WezTerm is not installed here");
        assert_eq!(Failure::Said("no running instance".into()).said("WezTerm"), "WezTerm said no running instance");
        assert_eq!(first_line("\n  error: refused\nmore"), "error: refused");
    }

    #[test]
    fn calls_a_missing_program_missing() {
        assert_eq!(run(command("memnox-no-such-program"), CLI_WAIT).unwrap_err(), Failure::Missing);
    }
}
