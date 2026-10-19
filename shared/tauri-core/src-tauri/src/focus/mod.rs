//! A session's own app brought forward, and an agent started, only through each tool's own documented
//! controls: an editor's command line and the Memnox extension's links, a terminal's own command line
//! (WezTerm's `wezterm cli`, kitty's remote control, Windows Terminal's `wt`), and the system's URL
//! handler for an agent app's registered links. By design nothing here raises another app's window by
//! itself, presses a key in it or reads its screen, so where no such control reaches, the answer says so.

mod editor;
mod plan;
mod process;
mod terminals;

use plan::{Editor, Host, Shown};
use terminals::{Pane, Terminal};

/// Blocking work off the main thread, since a command line or the extension's answer can take seconds.
async fn off_main<T: Send + 'static>(work: impl FnOnce() -> T + Send + 'static, lost: T) -> T {
    tauri::async_runtime::spawn_blocking(work)
        .await
        .unwrap_or(lost)
}

/// The panes a terminal's own command line lists, or why it cannot.
#[tauri::command]
pub async fn terminal_panes(terminal: String) -> Result<Vec<Pane>, String> {
    let Some(terminal) = Terminal::named(&terminal) else {
        return Err(format!("{terminal} is not a terminal Memnox drives"));
    };
    off_main(
        move || terminals::panes(terminal),
        Err("the listing stopped".into()),
    )
    .await
}

/// One listed pane brought forward by its terminal's own command.
#[tauri::command]
pub async fn terminal_focus(terminal: String, id: String) -> Result<(), String> {
    let Some(terminal) = Terminal::named(&terminal) else {
        return Err(format!("{terminal} is not a terminal Memnox drives"));
    };
    off_main(
        move || terminals::focus(terminal, &id),
        Err("the focus stopped".into()),
    )
    .await
}

/// The session's editor on its folder, and its conversation or terminal where a link can say which.
#[tauri::command]
pub async fn focus_editor(host: Host) -> Shown {
    off_main(
        move || editor::focus(&host),
        Shown::failed("the editor stopped answering"),
    )
    .await
}

/// A new tab in a supported terminal, in the folder, running the runtime's line as it was sent.
#[tauri::command]
pub async fn launch_in_terminal(
    terminal: Option<String>,
    line: String,
    folder: String,
    background: bool,
) -> Shown {
    let terminal = terminal.as_deref().and_then(Terminal::named);
    off_main(
        move || terminals::launch(terminal, &line, &folder, background),
        Shown::failed("the terminal stopped answering"),
    )
    .await
}

/// The editor on the folder, then the Memnox extension's launch link, answered once the extension writes back.
#[tauri::command]
pub async fn launch_in_editor(editor: String, folder: String, request: String) -> Shown {
    let Some(editor) = Editor::named(&editor) else {
        return Shown::failed(format!(
            "{editor} is not an editor the Memnox extension runs in"
        ));
    };
    off_main(
        move || editor::launch(editor, &folder, &request),
        Shown::failed("the editor stopped answering"),
    )
    .await
}

/// An agent app's own links, a moment apart, through the system's URL handler.
#[tauri::command]
pub async fn open_app_links(links: Vec<String>) -> Shown {
    off_main(
        move || editor::open_app_links(&links),
        Shown::failed("the app stopped answering"),
    )
    .await
}
