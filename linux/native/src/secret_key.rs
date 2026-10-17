//! The confirm key in the Secret Service, used only after polkit has asked the person.
//!
//! The private half is kept in the login keyring, encrypted at rest, and read only to sign. polkit
//! asks before every signature, with a fingerprint where fprintd is set up and the password where it
//! is not. The keyring is open to every process of the same user while the session is unlocked, so a
//! process that reads it directly could sign without polkit: this is the weakest of the desktop keys,
//! and a paired phone stays the stronger place to say yes on Linux, as the README says.

use std::collections::HashMap;
use std::process::Command;

use memnox_desktop_key::{ConfirmKey, KeyError, Signed, POINT_BYTES};
use p256::ecdsa::signature::Signer;
use p256::ecdsa::{Signature, SigningKey};
use rand_core::OsRng;
use secret_service::blocking::SecretService;
use secret_service::EncryptionType;

/// The polkit action `linux/packaging/org.memnox.desktop.policy` declares, asked with no grace period.
const ACTION: &str = "org.memnox.desktop.confirm";
/// How the item is found again in the keyring.
const ATTRIBUTE: (&str, &str) = ("memnox", "confirm-key");
const LABEL: &str = "Memnox confirm key";
const CONTENT_TYPE: &str = "application/octet-stream";

#[derive(Default)]
pub struct SecretKey;

impl SecretKey {
    pub fn new() -> Self {
        Self
    }

    /// The signing key from the keyring, made and stored the first time.
    fn signing_key(&self) -> Result<SigningKey, KeyError> {
        let service = SecretService::connect(EncryptionType::Dh).map_err(failed)?;
        let collection = service.get_default_collection().map_err(failed)?;
        collection.unlock().map_err(failed)?;
        let attributes = HashMap::from([ATTRIBUTE]);
        if let Some(item) = collection
            .search_items(attributes.clone())
            .map_err(failed)?
            .first()
        {
            let secret = item.get_secret().map_err(failed)?;
            return SigningKey::from_slice(&secret)
                .map_err(|_| KeyError("the stored confirm key is not P-256".into()));
        }
        let key = SigningKey::random(&mut OsRng);
        collection
            .create_item(LABEL, attributes, &key.to_bytes(), false, CONTENT_TYPE)
            .map_err(failed)?;
        Ok(key)
    }
}

impl ConfirmKey for SecretKey {
    fn public_point(&self) -> Result<Option<[u8; POINT_BYTES]>, KeyError> {
        // No Secret Service running, as on a bare window manager, is a computer with no key.
        let Ok(key) = self.signing_key() else {
            return Ok(None);
        };
        let encoded = key.verifying_key().to_encoded_point(false);
        let point: [u8; POINT_BYTES] = encoded
            .as_bytes()
            .try_into()
            .map_err(|_| KeyError("the confirm key gave a point that is not P-256".into()))?;
        Ok(Some(point))
    }

    fn sign(&self, message: &[u8], reason: &str) -> Result<Signed, KeyError> {
        if !polkit_says_yes(reason)? {
            return Ok(Signed::Declined);
        }
        let signature: Signature = self.signing_key()?.sign(message);
        Ok(Signed::Signature(signature.to_der().as_bytes().to_vec()))
    }
}

/// polkit's own prompt for this process, which names the call through the `reason` detail.
fn polkit_says_yes(reason: &str) -> Result<bool, KeyError> {
    let status = Command::new("pkcheck")
        .args([
            "--action-id",
            ACTION,
            "--process",
            &std::process::id().to_string(),
        ])
        .args(["--detail", "reason", reason, "--allow-user-interaction"])
        .status()
        .map_err(|error| KeyError(format!("polkit could not ask: {error}")))?;
    Ok(status.success())
}

fn failed(error: secret_service::Error) -> KeyError {
    KeyError(format!("the keyring refused: {error}"))
}
