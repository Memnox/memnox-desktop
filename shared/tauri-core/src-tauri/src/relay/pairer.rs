//! The pairing ceremony with a server, ported from the Mac's `RelayPairer` and `PairingInvitation`: XXpsk0
//! with the link's secret, the server's static key checked against the link, this computer's name and
//! signing point, the proof signed by the confirm key, and the one line that says whether the person typed
//! the matching digits into `memnox pair` there. The digits are the human check; nothing here trusts the relay.

use std::sync::Arc;
use std::time::Duration;

use base64::engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD};
use base64::Engine;
use memnox_desktop_noise::core::{
    generate_keypair, pairing_code, Handshake, Pattern, KEY_LEN, PSK_LEN,
};
use serde::{Deserialize, Serialize};

use super::framing::MAILBOX_LEN;
use super::socket::Dialer;
use super::store::PairedServer;
use super::tunnel::{receive_handshake, send_close, send_handshake, tunnel};

/// Long enough for the person to walk to the server, type the digits and press return.
pub const VERDICT_WAIT: Duration = Duration::from_secs(5 * 60);
/// The only link version this app reads.
const VERSION: u64 = 1;
/// The kind this computer names itself with in message 3, as remote-contract.md spells it.
const DESKTOP: &str = "desktop";

/// What a `memnox pair` link carries: where to meet the server and how to know it is the right one.
#[derive(Clone, Debug)]
pub struct Invitation {
    pub machine_id: String,
    pub machine: String,
    pub relay_url: String,
    pub mailbox: Vec<u8>,
    /// The rlp_ token, single use, scoped to this mailbox: it opens the relay and proves nothing more.
    pub pairing_token: String,
    pub runtime_static: Vec<u8>,
    pub secret: Vec<u8>,
}

/// Why pairing stopped short of a paired server, in the kinds the webview turns into words.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
pub enum PairFailure {
    NotALink,
    Unreadable,
    UnsupportedVersion {
        version: u64,
    },
    /// The server's static key is not the one in the link, so somebody else answered.
    WrongMachine,
    Declined,
    /// The person cancelled the system's prompt, so no proof was sent.
    Cancelled,
    /// This computer holds no confirm key to prove itself with.
    NoKey,
    /// Paired, but the record could not be kept in the credential store.
    NotKept {
        why: String,
    },
    Broken {
        why: String,
    },
}

/// The confirm key, asked to name its point and to sign, each of which may block on the system.
pub trait Prover: Send + Sync {
    fn point(&self) -> Result<Option<String>, String>;
    /// A base64 DER signature, or None when the person declined.
    fn sign(&self, message: &str, reason: &str) -> Result<Option<String>, String>;
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct WireInvitation {
    v: u64,
    machine_id: String,
    machine: String,
    relay_url: String,
    mailbox: String,
    pairing_token: String,
    runtime_noise_static: String,
    secret: String,
}

/// Reads a pasted link, refusing one that is malformed or from a newer runtime. Its expiry is the core's to check.
pub fn read_invitation(link: &str) -> Result<Invitation, PairFailure> {
    let link = link.trim();
    let rest = link
        .strip_prefix("memnox://pair")
        .ok_or(PairFailure::NotALink)?;
    let query = rest
        .trim_start_matches('/')
        .strip_prefix('?')
        .ok_or(PairFailure::NotALink)?;
    let payload = query
        .split('&')
        .find_map(|pair| pair.strip_prefix("d="))
        .ok_or(PairFailure::NotALink)?;
    let json = URL_SAFE_NO_PAD
        .decode(payload.trim_end_matches('='))
        .map_err(|_| PairFailure::Unreadable)?;
    let wire: WireInvitation =
        serde_json::from_slice(&json).map_err(|_| PairFailure::Unreadable)?;
    if wire.v != VERSION {
        return Err(PairFailure::UnsupportedVersion { version: wire.v });
    }
    let mailbox = URL_SAFE_NO_PAD
        .decode(wire.mailbox.trim_end_matches('='))
        .map_err(|_| PairFailure::Unreadable)?;
    let runtime_static = STANDARD
        .decode(&wire.runtime_noise_static)
        .map_err(|_| PairFailure::Unreadable)?;
    let secret = STANDARD
        .decode(&wire.secret)
        .map_err(|_| PairFailure::Unreadable)?;
    let usable = mailbox.len() == MAILBOX_LEN
        && runtime_static.len() == KEY_LEN
        && secret.len() == PSK_LEN
        && !wire.pairing_token.is_empty()
        && (wire.relay_url.starts_with("wss://") || wire.relay_url.starts_with("ws://"));
    if !usable {
        return Err(PairFailure::Unreadable);
    }
    Ok(Invitation {
        machine_id: wire.machine_id,
        machine: wire.machine,
        relay_url: wire.relay_url,
        mailbox,
        pairing_token: wire.pairing_token,
        runtime_static,
        secret,
    })
}

/// What a device signs at pairing to prove it holds the key it sent, byte for byte the runtime's `deviceProofMessage`.
pub fn device_proof_message(handshake_hash: &[u8]) -> String {
    format!("memnox-device:v1:{}", STANDARD.encode(handshake_hash))
}

#[derive(Deserialize)]
struct RuntimeHello {
    machine: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Introduction<'a> {
    name: &'a str,
    signing_point: &'a str,
    kind: &'a str,
}

#[derive(Serialize)]
struct DeviceProof {
    proof: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Verdict {
    paired: bool,
    device_id: Option<String>,
    relay_token: Option<String>,
    voice: Option<String>,
    speaks: Option<bool>,
}

fn broken(why: impl std::fmt::Display) -> PairFailure {
    PairFailure::Broken {
        why: why.to_string(),
    }
}

/// Runs the ceremony; `code` hears the six digits the moment both ends have them, for the person to type on the server.
pub async fn pair(
    invitation: &Invitation,
    name: &str,
    dialer: Arc<dyn Dialer>,
    prover: Arc<dyn Prover>,
    verdict_wait: Duration,
    now_ms: u64,
    code: impl Fn(String),
) -> Result<PairedServer, PairFailure> {
    let point = blocking({
        let prover = prover.clone();
        move || prover.point()
    })
    .await?
    .ok_or(PairFailure::NoKey)?;
    let mut socket = dialer
        .dial(&invitation.relay_url, &invitation.pairing_token)
        .await
        .map_err(broken)?;
    let mailbox = invitation.mailbox.clone();
    let ours = generate_keypair().map_err(broken)?;
    let mut handshake = Handshake::initiator(
        Pattern::XXpsk0,
        &ours.private,
        None,
        Some(&invitation.secret),
    )
    .map_err(broken)?;
    // Message 1 carries nothing; the PSK already binds it to this link.
    send_handshake(
        &socket.outgoing,
        &mailbox,
        &handshake.write_message(&[]).map_err(broken)?,
    )
    .await
    .map_err(broken)?;
    let hello = handshake
        .read_message(
            &receive_handshake(&mut socket.incoming, &mailbox)
                .await
                .map_err(broken)?,
        )
        .map_err(broken)?;
    if handshake.remote_static().map_err(broken)?.as_deref()
        != Some(invitation.runtime_static.as_slice())
    {
        send_close(&socket.outgoing, &mailbox).await;
        return Err(PairFailure::WrongMachine);
    }
    let machine = serde_json::from_slice::<RuntimeHello>(&hello)
        .map(|hello| hello.machine)
        .unwrap_or_else(|_| invitation.machine.clone());
    let introduction = serde_json::to_vec(&Introduction {
        name,
        signing_point: &point,
        kind: DESKTOP,
    })
    .map_err(broken)?;
    send_handshake(
        &socket.outgoing,
        &mailbox,
        &handshake.write_message(&introduction).map_err(broken)?,
    )
    .await
    .map_err(broken)?;
    if !handshake.is_finished().map_err(broken)? {
        return Err(broken(
            "the pairing handshake did not finish in three messages",
        ));
    }
    let hash = handshake.handshake_hash().map_err(broken)?;
    code(pairing_code(&hash).map_err(broken)?);
    let (writer, mut reader) = tunnel(
        socket,
        &mailbox,
        handshake.into_transport().map_err(broken)?,
        super::schedule::REKEY_INTERVAL,
    );
    let message = device_proof_message(&hash);
    let proof = blocking({
        let prover = prover.clone();
        move || prover.sign(&message, PROOF_REASON)
    })
    .await;
    let proof = match proof {
        Ok(Some(proof)) => proof,
        Ok(None) => {
            writer.close().await;
            return Err(PairFailure::Cancelled);
        }
        Err(why) => {
            writer.close().await;
            return Err(why);
        }
    };
    writer
        .send_line(&serde_json::to_vec(&DeviceProof { proof }).map_err(broken)?)
        .await
        .map_err(broken)?;
    let verdict = tokio::time::timeout(verdict_wait, async {
        loop {
            let line = reader.receive_line().await.map_err(broken)?;
            // Anything that is not the verdict is skipped, since only the verdict says how it went.
            if let Ok(verdict) = serde_json::from_slice::<Verdict>(&line) {
                return Ok::<Verdict, PairFailure>(verdict);
            }
        }
    })
    .await;
    writer.close().await;
    let verdict =
        verdict.map_err(|_| broken("the server did not answer the pairing in time"))??;
    let (true, Some(device_id), Some(relay_token)) =
        (verdict.paired, verdict.device_id, verdict.relay_token)
    else {
        return Err(PairFailure::Declined);
    };
    Ok(PairedServer {
        machine_id: invitation.machine_id.clone(),
        machine,
        relay_url: invitation.relay_url.clone(),
        mailbox: URL_SAFE_NO_PAD.encode(&mailbox),
        device_id,
        relay_token,
        runtime_static: STANDARD.encode(&invitation.runtime_static),
        private_key: STANDARD.encode(&ours.private),
        voice: verdict.voice,
        speaks: verdict.speaks,
        paired_at: now_ms,
    })
}

/// What the system's prompt says while the proof that this computer holds its key is signed.
pub const PROOF_REASON: &str = "pair this computer with your server";

/// The key's calls may wait on the person, so they run off the async threads.
async fn blocking<T: Send + 'static>(
    work: impl FnOnce() -> Result<T, String> + Send + 'static,
) -> Result<T, PairFailure> {
    tokio::task::spawn_blocking(work)
        .await
        .map_err(broken)?
        .map_err(broken)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::relay::socket::{pair as socket_pair, Dialing, RelaySocket};
    use memnox_desktop_noise::core::Keypair;
    use std::sync::Mutex;

    struct Key {
        declines: bool,
        signed: Mutex<Vec<String>>,
    }

    impl Prover for Key {
        fn point(&self) -> Result<Option<String>, String> {
            Ok(Some("BPOINT".into()))
        }
        fn sign(&self, message: &str, _reason: &str) -> Result<Option<String>, String> {
            self.signed.lock().unwrap().push(message.into());
            Ok((!self.declines).then(|| "sig".to_owned()))
        }
    }

    /// The server's side as the runtime's `PairingResponder` plays it, deciding by `accept`.
    struct Server {
        keys: Keypair,
        secret: Vec<u8>,
        accept: bool,
    }

    impl Dialer for Server {
        fn dial(&self, _url: &str, _token: &str) -> Dialing {
            let (ours, theirs) = socket_pair();
            let private = self.keys.private.clone();
            let secret = self.secret.clone();
            let accept = self.accept;
            tokio::spawn(respond(theirs, private, secret, accept));
            Box::pin(async move { Ok(ours) })
        }
    }

    async fn respond(mut socket: RelaySocket, private: Vec<u8>, secret: Vec<u8>, accept: bool) {
        let mailbox = [4u8; 16];
        let mut handshake = Handshake::responder(Pattern::XXpsk0, &private, Some(&secret)).unwrap();
        let Ok(first) = receive_handshake(&mut socket.incoming, &mailbox).await else {
            return;
        };
        handshake.read_message(&first).unwrap();
        send_handshake(
            &socket.outgoing,
            &mailbox,
            &handshake
                .write_message(br#"{"machine":"build-box"}"#)
                .unwrap(),
        )
        .await
        .unwrap();
        let Ok(third) = receive_handshake(&mut socket.incoming, &mailbox).await else {
            return;
        };
        let introduction: serde_json::Value =
            serde_json::from_slice(&handshake.read_message(&third).unwrap()).unwrap();
        assert_eq!(introduction["kind"], "desktop");
        let (writer, mut reader) =
            tunnel(socket, &mailbox, handshake.into_transport().unwrap(), 16);
        let Ok(proof) = reader.receive_line().await else {
            return;
        };
        assert_eq!(proof, br#"{"proof":"sig"}"#);
        let verdict = if accept {
            r#"{"paired":true,"deviceId":"dev_9","relayToken":"rly_9","speaks":false}"#
        } else {
            r#"{"paired":false}"#
        };
        writer.send_line(verdict.as_bytes()).await.unwrap();
    }

    fn invitation(server: &Keypair, secret: &[u8]) -> Invitation {
        Invitation {
            machine_id: "m_box".into(),
            machine: "box".into(),
            relay_url: "wss://relay.example/v1/relay".into(),
            mailbox: vec![4; 16],
            pairing_token: "rlp_1".into(),
            runtime_static: server.public.clone(),
            secret: secret.to_vec(),
        }
    }

    async fn run(
        accept: bool,
        declines: bool,
        expected: Option<&Keypair>,
    ) -> (Result<PairedServer, PairFailure>, Vec<String>, Arc<Key>) {
        let server = generate_keypair().unwrap();
        let secret = [8u8; 32];
        let key = Arc::new(Key {
            declines,
            signed: Mutex::new(Vec::new()),
        });
        let codes = Mutex::new(Vec::new());
        let invite = invitation(expected.unwrap_or(&server), &secret);
        let dialer = Arc::new(Server {
            keys: server,
            secret: secret.to_vec(),
            accept,
        });
        let result = pair(
            &invite,
            "Desk",
            dialer,
            key.clone(),
            Duration::from_secs(5),
            42,
            |code| codes.lock().unwrap().push(code),
        )
        .await;
        (result, codes.into_inner().unwrap(), key)
    }

    #[tokio::test]
    async fn pairs_shows_the_digits_and_signs_the_proof_over_the_handshake_hash() {
        let (result, codes, key) = run(true, false, None).await;
        let server = result.unwrap();
        assert_eq!(
            (
                server.machine.as_str(),
                server.device_id.as_str(),
                server.relay_token.as_str(),
                server.paired_at
            ),
            ("build-box", "dev_9", "rly_9", 42)
        );
        assert_eq!(codes.len(), 1);
        assert_eq!(codes[0].len(), 6);
        assert!(key.signed.lock().unwrap()[0].starts_with("memnox-device:v1:"));
    }

    #[tokio::test]
    async fn a_server_that_says_no_is_declined() {
        assert_eq!(run(false, false, None).await.0, Err(PairFailure::Declined));
    }

    #[tokio::test]
    async fn a_cancelled_prompt_sends_no_proof() {
        assert_eq!(run(true, true, None).await.0, Err(PairFailure::Cancelled));
    }

    #[tokio::test]
    async fn another_machine_answering_is_refused_before_anything_is_sent() {
        let someone = generate_keypair().unwrap();
        let (result, codes, key) = run(true, false, Some(&someone)).await;
        assert_eq!(result, Err(PairFailure::WrongMachine));
        assert!(codes.is_empty() && key.signed.lock().unwrap().is_empty());
    }

    #[test]
    fn the_proof_message_is_the_runtimes_vector() {
        let vectors: serde_json::Value =
            serde_json::from_str(include_str!("../../../../vectors/protocol.json")).unwrap();
        let vector = vectors["messages"]
            .as_array()
            .unwrap()
            .iter()
            .find(|m| m["name"] == "device-proof")
            .unwrap();
        let hash = STANDARD
            .decode(vector["inputs"]["handshakeHash"].as_str().unwrap())
            .unwrap();
        assert_eq!(
            device_proof_message(&hash),
            vector["message"].as_str().unwrap()
        );
    }

    #[test]
    fn reads_a_link_and_refuses_what_is_not_one() {
        let payload = serde_json::json!({
            "v": 1, "machineId": "m_1", "machine": "box", "relayUrl": "wss://relay.memnox.com/v1/relay",
            "mailbox": URL_SAFE_NO_PAD.encode([1u8; 16]), "pairingToken": "rlp_1",
            "runtimeNoiseStatic": STANDARD.encode([2u8; 32]), "secret": STANDARD.encode([3u8; 32]),
            "expiresAt": "2026-10-18T10:00:00.000Z"
        });
        let link = format!(
            "memnox://pair?d={}",
            URL_SAFE_NO_PAD.encode(payload.to_string())
        );
        let read = read_invitation(&format!("  {link}\n")).unwrap();
        assert_eq!((read.machine_id.as_str(), read.mailbox.len()), ("m_1", 16));
        assert_eq!(
            read_invitation("https://example.com").unwrap_err(),
            PairFailure::NotALink
        );
        assert_eq!(
            read_invitation("memnox://pair?d=!!!").unwrap_err(),
            PairFailure::Unreadable
        );
        let newer = serde_json::json!({ "v": 2, "machineId": "", "machine": "", "relayUrl": "", "mailbox": "", "pairingToken": "", "runtimeNoiseStatic": "", "secret": "" });
        let link = format!(
            "memnox://pair?d={}",
            URL_SAFE_NO_PAD.encode(newer.to_string())
        );
        assert_eq!(
            read_invitation(&link).unwrap_err(),
            PairFailure::UnsupportedVersion { version: 2 }
        );
    }
}
