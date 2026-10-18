//! Paired servers reached through the relay, as the webview asks for them: pair from a `memnox pair` link,
//! list and forget them, and stream a daemon request to one of them. One link per server is kept for as long
//! as the app runs, so the island, Settings and every listener share one Noise session per server.
//! The private keys and relay tokens stay here and in the credential store; the webview never sees them.

mod framing;
mod link;
mod pairer;
mod schedule;
mod socket;
mod store;
mod tunnel;

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine;
use memnox_desktop_key::{point_base64, signature_base64, ConfirmKey, Signed};
use tauri::ipc::Channel;
use tokio::sync::Mutex;

use crate::key::Key;
use link::{RelayLink, ServerKeys};
use pairer::{PairFailure, Prover, VERDICT_WAIT};
use socket::{Dialer, WebSocketDialer};
use store::{KeyringServers, PairedServer, ServerStore, ServerSummary};

/// Every paired server's link, opened on first use.
pub struct Relays {
    store: Arc<dyn ServerStore>,
    dialer: Arc<dyn Dialer>,
    links: Mutex<HashMap<String, RelayLink>>,
}

impl Default for Relays {
    fn default() -> Self {
        Self { store: Arc::new(KeyringServers::new(KeyringServers::SERVICE)), dialer: Arc::new(WebSocketDialer), links: Mutex::new(HashMap::new()) }
    }
}

impl Relays {
    async fn servers(&self) -> Result<Vec<PairedServer>, String> {
        let store = self.store.clone();
        tokio::task::spawn_blocking(move || store.all()).await.map_err(|why| why.to_string())?
    }

    async fn link(&self, machine_id: &str) -> Result<RelayLink, String> {
        if let Some(link) = self.links.lock().await.get(machine_id) {
            return Ok(link.clone());
        }
        let server = self.servers().await?.into_iter().find(|server| server.machine_id == machine_id).ok_or_else(|| format!("{machine_id} is not paired with this computer"))?;
        let link = RelayLink::new(keys(&server)?, self.dialer.clone());
        Ok(self.links.lock().await.entry(machine_id.to_owned()).or_insert(link).clone())
    }
}

fn keys(server: &PairedServer) -> Result<ServerKeys, String> {
    let unreadable = |_| format!("the record for {} could not be read", server.machine);
    Ok(ServerKeys {
        relay_url: server.relay_url.clone(),
        relay_token: server.relay_token.clone(),
        mailbox: URL_SAFE_NO_PAD.decode(&server.mailbox).map_err(unreadable)?,
        runtime_static: STANDARD.decode(&server.runtime_static).map_err(unreadable)?,
        private_key: STANDARD.decode(&server.private_key).map_err(unreadable)?,
    })
}

/// The confirm key as the pairing asks it, each call on a blocking thread since it may wait on the person.
struct KeyProver(Arc<dyn ConfirmKey>);

impl Prover for KeyProver {
    fn point(&self) -> Result<Option<String>, String> {
        Ok(self.0.public_point().map_err(|why| why.to_string())?.as_ref().map(point_base64))
    }

    fn sign(&self, message: &str, reason: &str) -> Result<Option<String>, String> {
        Ok(match self.0.sign(message.as_bytes(), reason).map_err(|why| why.to_string())? {
            Signed::Signature(der) => Some(signature_base64(&der)),
            Signed::Declined => None,
        })
    }
}

fn now_ms() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|since| since.as_millis() as u64).unwrap_or(0)
}

/// Every server paired with this computer, oldest first, with no secret in it.
#[tauri::command]
pub async fn relay_servers(relays: tauri::State<'_, Relays>) -> Result<Vec<ServerSummary>, String> {
    Ok(relays.servers().await?.iter().map(PairedServer::summary).collect())
}

/// Pairs with the server in a pasted link; `code` hears the six digits for the person to type there.
#[tauri::command]
pub async fn relay_pair(relays: tauri::State<'_, Relays>, key: tauri::State<'_, Key>, link: String, name: String, code: Channel<String>) -> Result<ServerSummary, PairFailure> {
    let invitation = pairer::read_invitation(&link)?;
    let prover = Arc::new(KeyProver(key.0.clone()));
    let server = pairer::pair(&invitation, &name, relays.dialer.clone(), prover, VERDICT_WAIT, now_ms(), |digits| {
        let _ = code.send(digits);
    })
    .await?;
    let store = relays.store.clone();
    let kept = server.clone();
    tokio::task::spawn_blocking(move || store.save(&kept))
        .await
        .map_err(|why| PairFailure::NotKept { why: why.to_string() })?
        .map_err(|why| PairFailure::NotKept { why })?;
    // A link opened before for an earlier pairing of this machine holds the old keys, so it goes.
    if let Some(old) = relays.links.lock().await.remove(&server.machine_id) {
        old.close().await;
    }
    Ok(server.summary())
}

/// Forgets a server here and closes its session; the server keeps this computer's record until it is revoked there.
#[tauri::command]
pub async fn relay_forget(relays: tauri::State<'_, Relays>, machine_id: String) -> Result<(), String> {
    if let Some(link) = relays.links.lock().await.remove(&machine_id) {
        link.close().await;
    }
    let store = relays.store.clone();
    tokio::task::spawn_blocking(move || store.forget(&machine_id)).await.map_err(|why| why.to_string())?
}

/// Sends one request line to a server and writes every answer into `lines` until the caller says it is done,
/// or the session ends, with `renewed` for the hourly fresh handshake and `disconnected` for a drop.
#[tauri::command]
pub async fn relay_stream(relays: tauri::State<'_, Relays>, machine_id: String, request: String, stream: String, lines: Channel<String>) -> Result<(), String> {
    let link = relays.link(&machine_id).await?;
    let mut opened = link.stream(&request, &stream).await.map_err(|end| end.words())?;
    loop {
        tokio::select! {
            line = opened.lines.recv() => match line {
                // The webview went away, so nobody reads the rest.
                Some(line) => if lines.send(line).is_err() { link.forget(&stream).await; return Ok(()) },
                None => return Ok(()),
            },
            ended = &mut opened.ended => {
                // Lines that came just before the end still reach the webview.
                while let Ok(line) = opened.lines.try_recv() {
                    let _ = lines.send(line);
                }
                return ended.unwrap_or(Ok(())).map_err(|end| end.words());
            }
        }
    }
}

/// The caller had the last line it wanted from a stream, so the link stops routing to it.
#[tauri::command]
pub async fn relay_done(relays: tauri::State<'_, Relays>, machine_id: String, stream: String) -> Result<(), String> {
    if let Some(link) = relays.links.lock().await.get(&machine_id) {
        link.forget(&stream).await;
    }
    Ok(())
}
