//! One authenticated connection to the relay, carrying whole binary messages, ported from the Mac's
//! `RelaySocket` and `WebSocketRelay`. It is a pair of channels, so the tunnel, the link and the pairing
//! are tested against an in-memory relay with no network. The relay sees only ciphertext and a mailbox
//! id, so a stolen token gets someone bytes that fail the handshake: the token is never trust.

use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use futures_util::{SinkExt, StreamExt};
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::http::HeaderValue;
use tokio_tungstenite::tungstenite::protocol::WebSocketConfig;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::Connector;

use super::framing::LARGEST_MESSAGE;

/// Messages queued toward the relay before a sender waits, a handful of chunked lines.
const QUEUED: usize = 64;

/// One relay connection: send whole messages, receive whole messages, and None once it is gone.
/// Dropping the sender closes the connection.
pub struct RelaySocket {
    pub outgoing: mpsc::Sender<Vec<u8>>,
    pub incoming: mpsc::Receiver<Vec<u8>>,
}

pub type Dialing = Pin<Box<dyn Future<Output = Result<RelaySocket, String>> + Send>>;

/// Opens relay connections with a bearer token: rlp_ while pairing, rly_ after.
pub trait Dialer: Send + Sync {
    fn dial(&self, url: &str, token: &str) -> Dialing;
}

/// The real relay over a WebSocket with rustls and the webpki roots, the token as a bearer header.
pub struct WebSocketDialer;

impl Dialer for WebSocketDialer {
    fn dial(&self, url: &str, token: &str) -> Dialing {
        let url = url.to_owned();
        let token = token.to_owned();
        Box::pin(async move { open(&url, &token).await })
    }
}

async fn open(url: &str, token: &str) -> Result<RelaySocket, String> {
    let mut request = url.into_client_request().map_err(|why| format!("the relay address is unusable: {why}"))?;
    let bearer = HeaderValue::from_str(&format!("Bearer {token}")).map_err(|_| "the relay token is unusable".to_owned())?;
    request.headers_mut().insert("Authorization", bearer);
    let config = WebSocketConfig::default().max_message_size(Some(LARGEST_MESSAGE)).max_frame_size(Some(LARGEST_MESSAGE));
    let (stream, _) = tokio_tungstenite::connect_async_tls_with_config(request, Some(config), false, Some(connector()?))
        .await
        // The relay's answer to the upgrade, such as 401 for a refused token, is the useful part of the reason.
        .map_err(|why| format!("the relay refused the connection: {why}"))?;
    let (mut sink, mut source) = stream.split();
    let (outgoing, mut to_relay) = mpsc::channel::<Vec<u8>>(QUEUED);
    let (from_relay, incoming) = mpsc::channel::<Vec<u8>>(QUEUED);
    tokio::spawn(async move {
        while let Some(message) = to_relay.recv().await {
            if sink.send(Message::Binary(message.into())).await.is_err() {
                return;
            }
        }
        let _ = sink.close().await;
    });
    tokio::spawn(async move {
        while let Some(Ok(message)) = source.next().await {
            match message {
                Message::Binary(bytes) => {
                    if from_relay.send(bytes.to_vec()).await.is_err() {
                        return;
                    }
                }
                Message::Close(_) => return,
                // The relay speaks only binary, so text is somebody else's and is skipped; pings are tungstenite's.
                _ => continue,
            }
        }
    });
    Ok(RelaySocket { outgoing, incoming })
}

/// TLS through rustls with ring and the webpki roots, so the same certificates are trusted on Windows and Linux.
fn connector() -> Result<Connector, String> {
    let roots = rustls::RootCertStore { roots: webpki_roots::TLS_SERVER_ROOTS.to_vec() };
    let config = rustls::ClientConfig::builder_with_provider(Arc::new(rustls::crypto::ring::default_provider()))
        .with_safe_default_protocol_versions()
        .map_err(|why| format!("TLS could not be set up: {why}"))?
        .with_root_certificates(roots)
        .with_no_client_auth();
    Ok(Connector::Rustls(Arc::new(config)))
}

/// Two sockets joined to each other, the relay in memory for tests.
#[cfg(test)]
pub fn pair() -> (RelaySocket, RelaySocket) {
    let (a_out, b_in) = mpsc::channel(QUEUED);
    let (b_out, a_in) = mpsc::channel(QUEUED);
    (RelaySocket { outgoing: a_out, incoming: a_in }, RelaySocket { outgoing: b_out, incoming: b_in })
}
