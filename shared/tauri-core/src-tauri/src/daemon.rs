//! The link to the daemon: one connection per request, a JSON line out and every line back, over the
//! unix socket on Linux or the named pipe on Windows. The webview reads the lines through a channel,
//! so it never touches the socket and the core above it decodes the wire with the runtime's own types.

use std::path::PathBuf;

use sha2::{Digest, Sha256};
use tauri::ipc::Channel;
use tokio::io::{AsyncBufReadExt, AsyncRead, AsyncWrite, AsyncWriteExt, BufReader};

// Built on every platform so the test checks it here, and used only on Windows.
#[cfg_attr(not(windows), allow(dead_code))]
/// What the runtime's `pipeNameFor` keeps from an account name; anything else becomes a hyphen.
fn pipe_safe(character: char) -> char {
    if character.is_ascii_alphanumeric() || matches!(character, '.' | '_' | '-') {
        character
    } else {
        '-'
    }
}

#[cfg_attr(not(windows), allow(dead_code))]
/// `\\.\pipe\memnox-<account>-<first 8 hex of sha256(home)>`, built exactly as `endpoint.ts` builds it.
pub fn pipe_name_for(home: &str) -> String {
    let account = home
        .split(['\\', '/'])
        .rfind(|segment| !segment.is_empty())
        .unwrap_or("user");
    let account: String = account.chars().map(pipe_safe).collect();
    let digest = Sha256::digest(home.as_bytes());
    let short: String = digest
        .iter()
        .take(4)
        .map(|byte| format!("{byte:02x}"))
        .collect();
    format!(r"\\.\pipe\memnox-{account}-{short}")
}

/// `~/.memnox/memnox.sock`, the same path the runtime's `socketPathFor` builds off Windows.
pub fn socket_path_for(home: &str) -> PathBuf {
    PathBuf::from(home).join(".memnox").join("memnox.sock")
}

fn home() -> Result<String, String> {
    let variable = if cfg!(windows) { "USERPROFILE" } else { "HOME" };
    std::env::var(variable)
        .map_err(|_| format!("{variable} is not set, so the daemon cannot be found"))
}

/// Sends one request line and writes every line the daemon answers into `lines` until it closes.
#[tauri::command]
pub async fn daemon_stream(request: String, lines: Channel<String>) -> Result<(), String> {
    if request.contains('\n') {
        return Err("a request is one line".into());
    }
    let home = home()?;
    #[cfg(unix)]
    let stream = connect_unix(&socket_path_for(&home)).await?;
    #[cfg(windows)]
    let stream = connect_pipe(&pipe_name_for(&home)).await?;
    relay(stream, request, lines).await
}

async fn relay(
    mut stream: impl AsyncRead + AsyncWrite + Unpin,
    request: String,
    lines: Channel<String>,
) -> Result<(), String> {
    stream
        .write_all(format!("{request}\n").as_bytes())
        .await
        .map_err(unreachable)?;
    let mut reader = BufReader::new(stream).lines();
    while let Some(line) = reader.next_line().await.map_err(unreachable)? {
        if line.trim().is_empty() {
            continue;
        }
        // The webview went away, so nobody reads the rest.
        if lines.send(line).is_err() {
            break;
        }
    }
    Ok(())
}

fn unreachable(error: std::io::Error) -> String {
    format!("the daemon did not answer: {error}")
}

/// The socket, refused unless the process listening on it runs as this same user, so another account's
/// listener in a shared home can never be the one this app shows calls from and signs answers to.
#[cfg(unix)]
async fn connect_unix(path: &std::path::Path) -> Result<tokio::net::UnixStream, String> {
    let stream = tokio::net::UnixStream::connect(path)
        .await
        .map_err(unreachable)?;
    let peer = stream.peer_cred().map_err(unreachable)?;
    // SAFETY: getuid has no preconditions and cannot fail.
    let me = unsafe { libc::getuid() };
    if peer.uid() != me {
        return Err("the daemon's socket belongs to another user".into());
    }
    Ok(stream)
}

#[cfg(windows)]
async fn connect_pipe(
    name: &str,
) -> Result<tokio::net::windows::named_pipe::NamedPipeClient, String> {
    tokio::net::windows::named_pipe::ClientOptions::new()
        .open(name)
        .map_err(unreachable)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_the_pipe_the_runtime_listens_on() {
        // From the runtime: socketPathFor('C:\\Users\\Ana Lopez', 'win32').
        assert_eq!(
            pipe_name_for(r"C:\Users\Ana Lopez"),
            r"\\.\pipe\memnox-Ana-Lopez-033a367c"
        );
    }

    #[test]
    fn finds_the_socket_under_the_home() {
        assert_eq!(
            socket_path_for("/home/ana"),
            PathBuf::from("/home/ana/.memnox/memnox.sock")
        );
    }

    #[cfg(unix)]
    #[test]
    fn relays_every_line_the_daemon_writes() {
        let runtime = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap();
        runtime.block_on(relays_every_line());
    }

    #[cfg(unix)]
    async fn relays_every_line() {
        let (app, mut daemon) = tokio::io::duplex(1024);
        let writer = tokio::spawn(async move {
            let mut asked = vec![0u8; 64];
            let read = tokio::io::AsyncReadExt::read(&mut daemon, &mut asked)
                .await
                .unwrap();
            daemon
                .write_all(b"{\"id\":1,\"ok\":true}\n\n{\"id\":1,\"ok\":true,\"event\":{}}\n")
                .await
                .unwrap();
            String::from_utf8(asked[..read].to_vec()).unwrap()
        });
        let seen = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let kept = seen.clone();
        let lines = Channel::new(move |body| {
            if let tauri::ipc::InvokeResponseBody::Json(line) = body {
                kept.lock().unwrap().push(line);
            }
            Ok(())
        });
        relay(app, "{\"id\":1,\"method\":\"subscribe\"}".into(), lines)
            .await
            .unwrap();
        assert_eq!(
            writer.await.unwrap(),
            "{\"id\":1,\"method\":\"subscribe\"}\n"
        );
        assert_eq!(seen.lock().unwrap().len(), 2);
    }
}
