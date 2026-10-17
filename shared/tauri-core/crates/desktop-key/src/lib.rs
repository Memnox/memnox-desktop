//! The key a yes is signed with on Windows and Linux. Each platform keeps the private half where
//! the operating system guards it and asks the person before every signature; this crate holds
//! what they share: the trait, the error, and the DER encoding the daemon's `verifiesSigned` reads.

use base64::engine::general_purpose::STANDARD;
use base64::Engine;

/// An uncompressed P-256 point: the 0x04 marker and two 32 byte coordinates, as the daemon registers it.
pub const POINT_BYTES: usize = 65;
/// One P-256 coordinate or signature half.
const SCALAR_BYTES: usize = 32;

/// Why a key could not be used, in words the island shows.
#[derive(Debug)]
pub struct KeyError(pub String);

impl std::fmt::Display for KeyError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for KeyError {}

/// What the person answered when asked to sign.
pub enum Signed {
    /// A DER encoded ECDSA P-256 signature over SHA-256 of the message.
    Signature(Vec<u8>),
    /// The person said no or closed the prompt, so nothing was signed.
    Declined,
}

/// The confirm key on one platform. Created on first use; never exported.
pub trait ConfirmKey: Send + Sync {
    /// The public half, creating the key when there is none yet. None where this computer cannot hold one.
    fn public_point(&self) -> Result<Option<[u8; POINT_BYTES]>, KeyError>;
    /// Asks the person, saying `reason`, then signs exactly `message`.
    fn sign(&self, message: &[u8], reason: &str) -> Result<Signed, KeyError>;
}

/// A computer with no key the operating system guards, so every allow stays in the terminal or on a phone.
pub struct NoKey;

impl ConfirmKey for NoKey {
    fn public_point(&self) -> Result<Option<[u8; POINT_BYTES]>, KeyError> {
        Ok(None)
    }

    fn sign(&self, _message: &[u8], _reason: &str) -> Result<Signed, KeyError> {
        Err(KeyError("this computer has no confirm key".into()))
    }
}

/// The point as the daemon's REGISTER_KEY takes it.
pub fn point_base64(point: &[u8; POINT_BYTES]) -> String {
    STANDARD.encode(point)
}

/// A signature as CONFIRM carries it.
pub fn signature_base64(der: &[u8]) -> String {
    STANDARD.encode(der)
}

/// The X9.63 point from the two coordinates a key store hands over.
pub fn point_from_coordinates(x: &[u8], y: &[u8]) -> Result<[u8; POINT_BYTES], KeyError> {
    if x.len() != SCALAR_BYTES || y.len() != SCALAR_BYTES {
        return Err(KeyError(
            "the key store gave a point that is not P-256".into(),
        ));
    }
    let mut point = [0u8; POINT_BYTES];
    point[0] = 0x04;
    point[1..=SCALAR_BYTES].copy_from_slice(x);
    point[SCALAR_BYTES + 1..].copy_from_slice(y);
    Ok(point)
}

/// DER `SEQUENCE { INTEGER r, INTEGER s }` from the raw r||s that CNG and most key stores return.
pub fn der_from_raw(raw: &[u8]) -> Result<Vec<u8>, KeyError> {
    if raw.len() != 2 * SCALAR_BYTES {
        return Err(KeyError("a P-256 signature is 64 bytes".into()));
    }
    let r = der_integer(&raw[..SCALAR_BYTES]);
    let s = der_integer(&raw[SCALAR_BYTES..]);
    let mut der = vec![0x30, (r.len() + s.len()) as u8];
    der.extend(r);
    der.extend(s);
    Ok(der)
}

/// One unsigned DER INTEGER: leading zeros dropped, and one put back when the top bit would read as negative.
fn der_integer(value: &[u8]) -> Vec<u8> {
    let first = value
        .iter()
        .position(|byte| *byte != 0)
        .unwrap_or(value.len() - 1);
    let digits = &value[first..];
    let padded = digits[0] & 0x80 != 0;
    let mut integer = vec![0x02, (digits.len() + usize::from(padded)) as u8];
    if padded {
        integer.push(0);
    }
    integer.extend_from_slice(digits);
    integer
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The runtime's signature vector, the same one every client checks, from `shared/vectors`.
    fn vector() -> serde_json::Value {
        let text = include_str!("../../../../vectors/protocol.json");
        serde_json::from_str::<serde_json::Value>(text).unwrap()["signature"].clone()
    }

    fn field(name: &str) -> Vec<u8> {
        STANDARD.decode(vector()[name].as_str().unwrap()).unwrap()
    }

    #[test]
    fn encodes_the_runtime_vector_exactly_as_the_daemon_verifies_it() {
        assert_eq!(der_from_raw(&field("p1363")).unwrap(), field("der"));
    }

    #[test]
    fn drops_leading_zeros_and_pads_a_high_bit() {
        let mut raw = [0u8; 64];
        raw[2] = 0x01; // r is 0x01 followed by 29 zero bytes, after two leading zeros
        raw[32] = 0x80; // s has its top bit set
        let der = der_from_raw(&raw).unwrap();
        assert_eq!(&der[2..4], &[0x02, 30]);
        assert_eq!(der[4], 0x01);
        assert_eq!(&der[34..37], &[0x02, 33, 0x00]);
        assert_eq!(der[1] as usize, der.len() - 2);
    }

    #[test]
    fn keeps_a_zero_as_one_byte() {
        let der = der_from_raw(&[0u8; 64]).unwrap();
        assert_eq!(der, vec![0x30, 6, 0x02, 1, 0, 0x02, 1, 0]);
    }

    #[test]
    fn refuses_what_is_not_a_p256_signature() {
        assert!(der_from_raw(&[1u8; 63]).is_err());
        assert!(point_from_coordinates(&[1u8; 31], &[1u8; 32]).is_err());
    }

    #[test]
    fn rebuilds_the_vector_point_from_its_coordinates() {
        let point = field("point");
        let rebuilt = point_from_coordinates(&point[1..33], &point[33..]).unwrap();
        assert_eq!(rebuilt.to_vec(), point);
    }
}
