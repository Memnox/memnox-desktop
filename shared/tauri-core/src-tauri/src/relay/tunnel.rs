//! A finished Noise session over one relay mailbox, ported from the Mac's `NoiseTunnel`: JSON lines in,
//! sealed chunks out, and the rekey counted both ways. The same type serves either end, so the test
//! runtime speaks exactly what this app does.

use std::sync::{Arc, Mutex};

use memnox_desktop_noise::core::Transport;
use tokio::sync::mpsc;

use super::framing::{self, FrameKind, LineJoiner};
use super::schedule::RekeyCounter;
use super::socket::RelaySocket;

/// Why the tunnel stopped.
#[derive(Debug, PartialEq, Eq)]
pub enum TunnelError {
    /// The peer closed, or the relay dropped the connection.
    Disconnected,
    /// A sealed chunk did not open or a line did not join, so the session cannot be trusted further.
    Broken(String),
}

impl std::fmt::Display for TunnelError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Disconnected => write!(f, "disconnected"),
            Self::Broken(why) => write!(f, "{why}"),
        }
    }
}

/// The cipher states with a rekey counter each way, behind one lock since the writer and the reader share them.
struct Cipher {
    transport: Transport,
    sent: RekeyCounter,
    received: RekeyCounter,
}

/// The sending half, cloned into every request that writes a line.
#[derive(Clone)]
pub struct TunnelWriter {
    mailbox: Vec<u8>,
    cipher: Arc<Mutex<Cipher>>,
    outgoing: mpsc::Sender<Vec<u8>>,
}

/// The receiving half, owned by the one task that reads the session.
pub struct TunnelReader {
    mailbox: Vec<u8>,
    cipher: Arc<Mutex<Cipher>>,
    incoming: mpsc::Receiver<Vec<u8>>,
    joiner: LineJoiner,
}

/// Splits a finished handshake's transport over a socket into its writer and its reader.
pub fn tunnel(socket: RelaySocket, mailbox: &[u8], transport: Transport, rekey_every: u64) -> (TunnelWriter, TunnelReader) {
    let cipher = Arc::new(Mutex::new(Cipher { transport, sent: RekeyCounter::new(rekey_every), received: RekeyCounter::new(rekey_every) }));
    let writer = TunnelWriter { mailbox: mailbox.to_vec(), cipher: cipher.clone(), outgoing: socket.outgoing };
    let reader = TunnelReader { mailbox: mailbox.to_vec(), cipher, incoming: socket.incoming, joiner: LineJoiner::default() };
    (writer, reader)
}

impl TunnelWriter {
    /// Sends one JSON line, cut into chunks, each sealed as its own transport message.
    pub async fn send_line(&self, line: &[u8]) -> Result<(), TunnelError> {
        // Sealed under the lock and sent after it, so the counter and the nonce move together.
        let messages = {
            let mut cipher = self.cipher.lock().map_err(|_| TunnelError::Broken("the cipher lock was poisoned".into()))?;
            let mut messages = Vec::new();
            for chunk in framing::chunks(line) {
                let sealed = cipher.transport.encrypt(&chunk).map_err(|why| TunnelError::Broken(why.to_string()))?;
                messages.push(framing::message(&self.mailbox, FrameKind::Transport, &sealed).map_err(|why| TunnelError::Broken(why.to_string()))?);
                if cipher.sent.counted() {
                    cipher.transport.rekey_outgoing();
                }
            }
            messages
        };
        for message in messages {
            self.outgoing.send(message).await.map_err(|_| TunnelError::Disconnected)?;
        }
        Ok(())
    }

    /// Tells the peer this side drops the session; the connection closes once every writer is gone.
    pub async fn close(&self) {
        if let Ok(message) = framing::message(&self.mailbox, FrameKind::Close, &[]) {
            let _ = self.outgoing.send(message).await;
        }
    }
}

impl TunnelReader {
    /// The next whole JSON line, failing when the peer closes or the relay drops.
    pub async fn receive_line(&mut self) -> Result<Vec<u8>, TunnelError> {
        loop {
            let message = self.incoming.recv().await.ok_or(TunnelError::Disconnected)?;
            // Another mailbox or a kind nobody sends is dropped rather than read.
            let Some((kind, body)) = framing::frame(&message, &self.mailbox) else { continue };
            match kind {
                FrameKind::Close => return Err(TunnelError::Disconnected),
                // A handshake message inside a finished session is dropped.
                FrameKind::Handshake => continue,
                FrameKind::Transport => {
                    let plaintext = {
                        let mut cipher = self.cipher.lock().map_err(|_| TunnelError::Broken("the cipher lock was poisoned".into()))?;
                        let plaintext = cipher.transport.decrypt(body).map_err(|why| TunnelError::Broken(why.to_string()))?;
                        if cipher.received.counted() {
                            cipher.transport.rekey_incoming();
                        }
                        plaintext
                    };
                    if let Some(line) = self.joiner.push(&plaintext).map_err(|why| TunnelError::Broken(why.to_string()))? {
                        return Ok(line);
                    }
                }
            }
        }
    }
}

/// Sends one handshake message in a frame.
pub async fn send_handshake(outgoing: &mpsc::Sender<Vec<u8>>, mailbox: &[u8], message: &[u8]) -> Result<(), TunnelError> {
    let framed = framing::message(mailbox, FrameKind::Handshake, message).map_err(|why| TunnelError::Broken(why.to_string()))?;
    outgoing.send(framed).await.map_err(|_| TunnelError::Disconnected)
}

/// Waits for the next handshake message, failing on a close and skipping anything else.
pub async fn receive_handshake(incoming: &mut mpsc::Receiver<Vec<u8>>, mailbox: &[u8]) -> Result<Vec<u8>, TunnelError> {
    loop {
        let message = incoming.recv().await.ok_or(TunnelError::Disconnected)?;
        match framing::frame(&message, mailbox) {
            Some((FrameKind::Handshake, body)) => return Ok(body.to_vec()),
            Some((FrameKind::Close, _)) => return Err(TunnelError::Disconnected),
            // A transport message before the handshake finished, or one for another mailbox.
            _ => continue,
        }
    }
}

/// Sends the close frame on a socket that never became a tunnel.
pub async fn send_close(outgoing: &mpsc::Sender<Vec<u8>>, mailbox: &[u8]) {
    if let Ok(message) = framing::message(mailbox, FrameKind::Close, &[]) {
        let _ = outgoing.send(message).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::relay::socket::{pair, RelaySocket};
    use memnox_desktop_noise::core::{generate_keypair, Handshake, Pattern};

    const MAILBOX: [u8; 16] = [3; 16];

    /// Both ends of a finished IK session over an in-memory relay, the second being the runtime.
    async fn ik_tunnels(rekey_every: u64) -> ((TunnelWriter, TunnelReader), (TunnelWriter, TunnelReader)) {
        let (phone, runtime) = (generate_keypair().unwrap(), generate_keypair().unwrap());
        let (mut ours, mut theirs) = pair();
        let mut initiator = Handshake::initiator(Pattern::IK, &phone.private, Some(&runtime.public), None).unwrap();
        let mut responder = Handshake::responder(Pattern::IK, &runtime.private, None).unwrap();
        send_handshake(&ours.outgoing, &MAILBOX, &initiator.write_message(b"").unwrap()).await.unwrap();
        responder.read_message(&receive_handshake(&mut theirs.incoming, &MAILBOX).await.unwrap()).unwrap();
        send_handshake(&theirs.outgoing, &MAILBOX, &responder.write_message(b"").unwrap()).await.unwrap();
        initiator.read_message(&receive_handshake(&mut ours.incoming, &MAILBOX).await.unwrap()).unwrap();
        (
            tunnel(ours, &MAILBOX, initiator.into_transport().unwrap(), rekey_every),
            tunnel(theirs, &MAILBOX, responder.into_transport().unwrap(), rekey_every),
        )
    }

    #[tokio::test]
    async fn lines_cross_both_ways_and_survive_a_rekey_every_two_messages() {
        let ((ours, mut our_reader), (theirs, mut their_reader)) = ik_tunnels(2).await;
        for n in 0..5 {
            ours.send_line(format!("{{\"id\":{n}}}").as_bytes()).await.unwrap();
            assert_eq!(their_reader.receive_line().await.unwrap(), format!("{{\"id\":{n}}}").into_bytes());
            theirs.send_line(b"{\"ok\":true}").await.unwrap();
            assert_eq!(our_reader.receive_line().await.unwrap(), b"{\"ok\":true}");
        }
        let long = vec![b'x'; 140_000];
        ours.send_line(&long).await.unwrap();
        assert_eq!(their_reader.receive_line().await.unwrap(), long);
    }

    #[tokio::test]
    async fn a_close_frame_ends_the_reader() {
        let ((ours, _), (_, mut their_reader)) = ik_tunnels(16).await;
        ours.close().await;
        assert_eq!(their_reader.receive_line().await, Err(TunnelError::Disconnected));
    }
    /// The runtime's own Node addon answers this app's IK session, so both ends are checked to run one Noise.
    /// Skipped where no runtime checkout with a built addon sits beside this repository, or MEMNOX_RUNTIME names none.
    #[tokio::test]
    async fn the_runtimes_node_noise_answers_an_ik_session_with_rekeys() {
        use std::io::{BufRead, BufReader, Write};
        let here = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
        let runtime = std::env::var("MEMNOX_RUNTIME").map(std::path::PathBuf::from).unwrap_or_else(|_| here.join("../../../../memnox-runtime"));
        let addon = runtime.join("native/noise/index.js");
        if !addon.exists() {
            eprintln!("skipped: no memnox-runtime Noise addon at {}", addon.display());
            return;
        }
        let script = here.join("src/relay/node-responder.cjs");
        let Ok(mut node) = std::process::Command::new("node").arg(&script).arg(&addon).stdin(std::process::Stdio::piped()).stdout(std::process::Stdio::piped()).spawn() else {
            eprintln!("skipped: no node on the path");
            return;
        };
        let mut stdin = node.stdin.take().unwrap();
        let mut stdout = BufReader::new(node.stdout.take().unwrap());
        let mut read_hex = move || {
            let mut line = String::new();
            stdout.read_line(&mut line).unwrap();
            hex(line.trim())
        };
        let mailbox = [6u8; 16];
        let server_static = read_hex();
        let ours = generate_keypair().unwrap();
        let mut initiator = Handshake::initiator(Pattern::IK, &ours.private, Some(&server_static), None).unwrap();
        let first = framing::message(&mailbox, FrameKind::Handshake, &initiator.write_message(b"").unwrap()).unwrap();
        writeln!(stdin, "{}", to_hex(&first)).unwrap();
        let second = read_hex();
        let (kind, body) = framing::frame(&second, &mailbox).unwrap();
        assert_eq!(kind, FrameKind::Handshake);
        initiator.read_message(body).unwrap();
        let (outgoing, mut to_node) = mpsc::channel(8);
        let (from_node, incoming) = mpsc::channel(8);
        let (writer, mut reader) = tunnel(RelaySocket { outgoing, incoming }, &mailbox, initiator.into_transport().unwrap(), 2);
        for n in 0..5 {
            writer.send_line(format!("{{\"id\":{n},\"method\":\"ping\"}}").as_bytes()).await.unwrap();
            let sealed = to_node.recv().await.unwrap();
            writeln!(stdin, "{}", to_hex(&sealed)).unwrap();
            from_node.send(read_hex()).await.unwrap();
            let answer: serde_json::Value = serde_json::from_slice(&reader.receive_line().await.unwrap()).unwrap();
            assert_eq!((answer["id"].as_u64(), answer["seen"].as_bool()), (Some(n), Some(true)));
        }
        drop(stdin);
        let _ = node.wait();
    }

    fn hex(text: &str) -> Vec<u8> {
        (0..text.len()).step_by(2).map(|at| u8::from_str_radix(&text[at..at + 2], 16).unwrap()).collect()
    }

    fn to_hex(bytes: &[u8]) -> String {
        bytes.iter().map(|byte| format!("{byte:02x}")).collect()
    }
}
