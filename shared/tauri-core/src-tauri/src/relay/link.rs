//! A paired server's daemon reached through the relay, ported from the Mac's `NoiseRelayLink`: one Noise IK
//! session carries every request, each answer is routed back by id, and the session is replaced by a fresh
//! handshake every hour. Every window of this app shares the one session, so each request travels under an
//! id this link hands out and comes back under the id its caller gave it.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use memnox_desktop_noise::core::{Handshake, Pattern};
use serde_json::Value;
use tokio::sync::{mpsc, oneshot, Mutex};
use tokio::task::JoinHandle;

use super::schedule::{REKEY_INTERVAL, SESSION_LIFETIME};
use super::socket::Dialer;
use super::tunnel::{
    receive_handshake, send_close, send_handshake, tunnel, TunnelReader, TunnelWriter,
};

/// Long enough for a slow relay to answer two messages, short enough that a dead one is not waited on forever.
const HANDSHAKE_PATIENCE: Duration = Duration::from_secs(20);

/// How a stream through the link ended, when it did not end because its caller was done with it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum End {
    /// The relay or the network dropped the session, or the server closed it.
    Disconnected,
    /// The link closed the session itself for its hourly fresh handshake, so a listener can open again at once.
    Renewed,
    /// The request never went, with why.
    Refused(String),
}

impl End {
    /// The words the webview reads: the two kinds of end a listener tells apart, or the refusal.
    pub fn words(&self) -> String {
        match self {
            End::Disconnected => DISCONNECTED.into(),
            End::Renewed => RENEWED.into(),
            End::Refused(why) => why.clone(),
        }
    }
}

pub const DISCONNECTED: &str = "disconnected";
pub const RENEWED: &str = "renewed";

/// What the link needs of a paired server: where to meet it and the keys of this pairing.
#[derive(Clone)]
pub struct ServerKeys {
    pub relay_url: String,
    pub relay_token: String,
    pub mailbox: Vec<u8>,
    pub runtime_static: Vec<u8>,
    pub private_key: Vec<u8>,
}

/// The lines for one request as they come, and how it ended.
pub struct Stream {
    pub lines: mpsc::UnboundedReceiver<String>,
    pub ended: oneshot::Receiver<Result<(), End>>,
}

struct Route {
    caller_id: Value,
    key: String,
    lines: mpsc::UnboundedSender<String>,
    ended: Option<oneshot::Sender<Result<(), End>>>,
}

impl Route {
    fn end(mut self, how: Result<(), End>) {
        if let Some(ended) = self.ended.take() {
            let _ = ended.send(how);
        }
    }
}

struct Session {
    writer: TunnelWriter,
    started: Instant,
    generation: u64,
    reader: JoinHandle<()>,
    timer: JoinHandle<()>,
}

#[derive(Default)]
struct State {
    session: Option<Session>,
    next_id: u64,
    generation: u64,
    handshakes: u64,
    routes: HashMap<u64, Route>,
    keys: HashMap<String, u64>,
}

struct Inner {
    server: ServerKeys,
    dialer: Arc<dyn Dialer>,
    lifetime: Duration,
    rekey_every: u64,
    state: Mutex<State>,
}

/// One server's link, cheap to clone, every clone the same session.
#[derive(Clone)]
pub struct RelayLink {
    inner: Arc<Inner>,
}

impl RelayLink {
    pub fn new(server: ServerKeys, dialer: Arc<dyn Dialer>) -> Self {
        Self::with_schedule(server, dialer, SESSION_LIFETIME, REKEY_INTERVAL)
    }

    pub fn with_schedule(
        server: ServerKeys,
        dialer: Arc<dyn Dialer>,
        lifetime: Duration,
        rekey_every: u64,
    ) -> Self {
        Self {
            inner: Arc::new(Inner {
                server,
                dialer,
                lifetime,
                rekey_every,
                state: Mutex::new(State::default()),
            }),
        }
    }

    /// Sends one request line; `key` is the caller's own name for the stream, which `forget` takes back.
    pub async fn stream(&self, request: &str, key: &str) -> Result<Stream, End> {
        let mut parsed: Value = serde_json::from_str(request)
            .map_err(|_| End::Refused("a request is one JSON object".into()))?;
        let caller_id = parsed
            .get("id")
            .cloned()
            .ok_or_else(|| End::Refused("a request carries an id".into()))?;
        let (lines_in, lines) = mpsc::unbounded_channel();
        let (ended_in, ended) = oneshot::channel();
        let (writer, id, line) = {
            let mut state = self.inner.state.lock().await;
            // Ready first, since starting over an hour old session ends every route on it.
            let writer = self.ready(&mut state).await?;
            if state.keys.contains_key(key) {
                return Err(End::Refused(format!("stream {key} is already in flight")));
            }
            state.next_id += 1;
            let id = state.next_id;
            parsed["id"] = Value::from(id);
            state.keys.insert(key.to_owned(), id);
            state.routes.insert(
                id,
                Route {
                    caller_id,
                    key: key.to_owned(),
                    lines: lines_in,
                    ended: Some(ended_in),
                },
            );
            (writer, id, parsed.to_string())
        };
        if writer.send_line(line.as_bytes()).await.is_err() {
            let mut state = self.inner.state.lock().await;
            if let Some(route) = state.routes.remove(&id) {
                state.keys.remove(&route.key);
            }
            return Err(End::Disconnected);
        }
        Ok(Stream { lines, ended })
    }

    /// The caller is done with a stream: the daemon's last line came, or nobody listens any more.
    pub async fn forget(&self, key: &str) {
        let mut state = self.inner.state.lock().await;
        if let Some(id) = state.keys.remove(key) {
            if let Some(route) = state.routes.remove(&id) {
                route.end(Ok(()));
            }
        }
    }

    /// Sends the close frame and drops the session, ending every stream on it.
    pub async fn close(&self) {
        let mut state = self.inner.state.lock().await;
        drop_session(&mut state, End::Disconnected);
    }

    /// How many IK handshakes this link has run, for tests.
    #[cfg(test)]
    pub async fn handshakes(&self) -> u64 {
        self.inner.state.lock().await.handshakes
    }

    /// The live session's writer, a fresh session when there is none or the last is an hour old.
    async fn ready(&self, state: &mut State) -> Result<TunnelWriter, End> {
        if let Some(session) = &state.session {
            if session.started.elapsed() < self.inner.lifetime {
                return Ok(session.writer.clone());
            }
            drop_session(state, End::Renewed);
        }
        let (writer, reader) =
            match tokio::time::timeout(HANDSHAKE_PATIENCE, self.handshake()).await {
                Ok(Ok(halves)) => halves,
                Ok(Err(why)) => return Err(End::Refused(why)),
                Err(_) => {
                    return Err(End::Refused(
                        "the relay session did not open in time".into(),
                    ))
                }
            };
        state.generation += 1;
        state.handshakes += 1;
        let generation = state.generation;
        let reader = tokio::spawn(read(self.inner.clone(), reader, generation));
        let timer = tokio::spawn(expire(self.inner.clone(), generation));
        state.session = Some(Session {
            writer: writer.clone(),
            started: Instant::now(),
            generation,
            reader,
            timer,
        });
        Ok(writer)
    }

    /// This computer opens with IK, already knowing the server's static key from pairing.
    async fn handshake(&self) -> Result<(TunnelWriter, TunnelReader), String> {
        let server = &self.inner.server;
        let mut socket = self
            .inner
            .dialer
            .dial(&server.relay_url, &server.relay_token)
            .await?;
        let mailbox = server.mailbox.clone();
        let opened = async {
            let mut handshake = Handshake::initiator(
                Pattern::IK,
                &server.private_key,
                Some(&server.runtime_static),
                None,
            )
            .map_err(|why| why.to_string())?;
            let first = handshake
                .write_message(&[])
                .map_err(|why| why.to_string())?;
            send_handshake(&socket.outgoing, &mailbox, &first)
                .await
                .map_err(|why| why.to_string())?;
            let second = receive_handshake(&mut socket.incoming, &mailbox)
                .await
                .map_err(|why| why.to_string())?;
            handshake
                .read_message(&second)
                .map_err(|why| why.to_string())?;
            if !handshake.is_finished().map_err(|why| why.to_string())? {
                return Err("the IK handshake did not finish in two messages".to_owned());
            }
            handshake.into_transport().map_err(|why| why.to_string())
        }
        .await;
        match opened {
            Ok(transport) => Ok(tunnel(socket, &mailbox, transport, self.inner.rekey_every)),
            Err(why) => {
                send_close(&socket.outgoing, &mailbox).await;
                Err(why)
            }
        }
    }
}

/// Reads the session until it ends, handing each line to the stream it answers.
async fn read(inner: Arc<Inner>, mut reader: TunnelReader, generation: u64) {
    loop {
        match reader.receive_line().await {
            Ok(line) => deliver(&inner, &line).await,
            Err(_) => {
                let mut state = inner.state.lock().await;
                if state
                    .session
                    .as_ref()
                    .is_some_and(|session| session.generation == generation)
                {
                    drop_session(&mut state, End::Disconnected);
                }
                return;
            }
        }
    }
}

/// Starts over an hour on even with nothing sent, so a quiet subscription never outlives its key.
async fn expire(inner: Arc<Inner>, generation: u64) {
    tokio::time::sleep(inner.lifetime).await;
    let mut state = inner.state.lock().await;
    if state
        .session
        .as_ref()
        .is_some_and(|session| session.generation == generation)
    {
        drop_session(&mut state, End::Renewed);
    }
}

/// One line to the stream whose id it carries, under the id that stream's caller gave; a line for no stream is dropped.
async fn deliver(inner: &Inner, line: &[u8]) {
    let Ok(mut parsed) = serde_json::from_slice::<Value>(line) else {
        return;
    };
    let Some(id) = parsed.get("id").and_then(Value::as_u64) else {
        return;
    };
    let mut state = inner.state.lock().await;
    let Some(route) = state.routes.get(&id) else {
        return;
    };
    parsed["id"] = route.caller_id.clone();
    if route.lines.send(parsed.to_string()).is_err() {
        // Nobody reads it any more, so the route goes.
        if let Some(route) = state.routes.remove(&id) {
            state.keys.remove(&route.key);
        }
    }
}

/// Ends the session and every stream on it, since the daemon forgets a session's requests with it.
fn drop_session(state: &mut State, reason: End) {
    let Some(session) = state.session.take() else {
        return;
    };
    session.reader.abort();
    session.timer.abort();
    let writer = session.writer;
    tokio::spawn(async move { writer.close().await });
    state.keys.clear();
    for (_, route) in state.routes.drain() {
        route.end(Err(reason.clone()));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::relay::socket::{pair, Dialing, RelaySocket};
    use crate::relay::tunnel::tunnel as make_tunnel;
    use memnox_desktop_noise::core::generate_keypair;
    use std::sync::atomic::{AtomicU64, Ordering};

    const MAILBOX: [u8; 16] = [5; 16];

    /// A relay in memory whose far end is a runtime answering every request with its id and method.
    struct FakeRuntime {
        private: Vec<u8>,
        dials: AtomicU64,
    }

    impl Dialer for FakeRuntime {
        fn dial(&self, _url: &str, token: &str) -> Dialing {
            self.dials.fetch_add(1, Ordering::SeqCst);
            let (ours, theirs) = pair();
            let private = self.private.clone();
            let refused = token != "rly_ok";
            Box::pin(async move {
                if refused {
                    return Err("the relay answered 401".to_owned());
                }
                tokio::spawn(answer(theirs, private));
                Ok(ours)
            })
        }
    }

    async fn answer(mut socket: RelaySocket, private: Vec<u8>) {
        let mut responder = Handshake::responder(Pattern::IK, &private, None).unwrap();
        let first = receive_handshake(&mut socket.incoming, &MAILBOX)
            .await
            .unwrap();
        responder.read_message(&first).unwrap();
        send_handshake(
            &socket.outgoing,
            &MAILBOX,
            &responder.write_message(b"").unwrap(),
        )
        .await
        .unwrap();
        let (writer, mut reader) =
            make_tunnel(socket, &MAILBOX, responder.into_transport().unwrap(), 2);
        while let Ok(line) = reader.receive_line().await {
            let request: Value = serde_json::from_slice(&line).unwrap();
            let reply =
                serde_json::json!({ "id": request["id"], "ok": true, "method": request["method"] });
            writer
                .send_line(reply.to_string().as_bytes())
                .await
                .unwrap();
            // A line for a request nobody made, which the link drops.
            writer
                .send_line(b"{\"id\":999,\"done\":{\"text\":\"for a phone\"}}")
                .await
                .unwrap();
        }
    }

    fn link(token: &str, lifetime: Duration) -> (RelayLink, Arc<FakeRuntime>) {
        let runtime = generate_keypair().unwrap();
        let phone = generate_keypair().unwrap();
        let fake = Arc::new(FakeRuntime {
            private: runtime.private,
            dials: AtomicU64::new(0),
        });
        let keys = ServerKeys {
            relay_url: "wss://relay.example".into(),
            relay_token: token.into(),
            mailbox: MAILBOX.to_vec(),
            runtime_static: runtime.public,
            private_key: phone.private,
        };
        (
            RelayLink::with_schedule(keys, fake.clone(), lifetime, 2),
            fake,
        )
    }

    #[tokio::test]
    async fn answers_come_back_under_the_callers_own_id_even_when_two_callers_share_one() {
        let (link, fake) = link("rly_ok", SESSION_LIFETIME);
        let mut first = link
            .stream(r#"{"id":1,"method":"ping"}"#, "island-1")
            .await
            .unwrap();
        let mut second = link
            .stream(r#"{"id":1,"method":"waiting"}"#, "settings-1")
            .await
            .unwrap();
        let one: Value = serde_json::from_str(&first.lines.recv().await.unwrap()).unwrap();
        let two: Value = serde_json::from_str(&second.lines.recv().await.unwrap()).unwrap();
        assert_eq!(
            (one["id"].as_u64(), one["method"].as_str()),
            (Some(1), Some("ping"))
        );
        assert_eq!(
            (two["id"].as_u64(), two["method"].as_str()),
            (Some(1), Some("waiting"))
        );
        link.forget("island-1").await;
        assert_eq!(first.ended.await.unwrap(), Ok(()));
        assert_eq!(link.handshakes().await, 1);
        assert_eq!(fake.dials.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn a_key_already_in_flight_is_refused() {
        let (link, _) = link("rly_ok", SESSION_LIFETIME);
        let _held = link
            .stream(r#"{"id":1,"method":"subscribe"}"#, "feed")
            .await
            .unwrap();
        assert!(matches!(
            link.stream(r#"{"id":2,"method":"subscribe"}"#, "feed")
                .await,
            Err(End::Refused(_))
        ));
    }

    #[tokio::test]
    async fn a_refused_token_opens_no_session() {
        let (link, _) = link("rly_stolen", SESSION_LIFETIME);
        assert!(matches!(
            link.stream(r#"{"id":1,"method":"ping"}"#, "a").await,
            Err(End::Refused(_))
        ));
        assert_eq!(link.handshakes().await, 0);
    }

    #[tokio::test]
    async fn the_hour_ends_every_stream_as_renewed_and_the_next_request_shakes_hands_again() {
        let (link, _) = link("rly_ok", Duration::from_millis(80));
        let subscription = link
            .stream(r#"{"id":1,"method":"subscribe"}"#, "feed")
            .await
            .unwrap();
        assert_eq!(subscription.ended.await.unwrap(), Err(End::Renewed));
        let mut again = link
            .stream(r#"{"id":2,"method":"ping"}"#, "ping")
            .await
            .unwrap();
        assert!(again.lines.recv().await.is_some());
        assert_eq!(link.handshakes().await, 2);
    }

    #[tokio::test]
    async fn closing_ends_every_stream_as_disconnected() {
        let (link, _) = link("rly_ok", SESSION_LIFETIME);
        let subscription = link
            .stream(r#"{"id":1,"method":"subscribe"}"#, "feed")
            .await
            .unwrap();
        link.close().await;
        assert_eq!(subscription.ended.await.unwrap(), Err(End::Disconnected));
    }
}
