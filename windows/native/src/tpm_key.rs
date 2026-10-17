//! The confirm key in the TPM, through the Platform Crypto Provider, used only after Windows Hello.
//!
//! The private half is generated inside the TPM and never leaves it, so a copy of the disk or of this
//! process's memory cannot sign. Windows Hello is asked before every signature with the call named.
//! Unlike the Secure Enclave, the TPM key itself does not demand Hello, so a process of the same user
//! that calls NCrypt directly could sign without it; the phone and the Mac stay the stronger places to
//! say yes, and the README says so.

use memnox_desktop_key::{
    der_from_raw, point_from_coordinates, ConfirmKey, KeyError, Signed, POINT_BYTES,
};
use sha2::{Digest, Sha256};
use windows::core::{factory, HSTRING};
use windows::Security::Credentials::UI::{UserConsentVerificationResult, UserConsentVerifier};
use windows::Win32::Foundation::{HWND, NTE_BAD_KEYSET};
use windows::Win32::Security::Cryptography::{
    NCryptCreatePersistedKey, NCryptExportKey, NCryptFinalizeKey, NCryptFreeObject, NCryptOpenKey,
    NCryptOpenStorageProvider, NCryptSignHash, BCRYPT_ECCPUBLIC_BLOB, BCRYPT_ECDSA_P256_ALGORITHM,
    CERT_KEY_SPEC, MS_PLATFORM_CRYPTO_PROVIDER, NCRYPT_FLAGS, NCRYPT_HANDLE, NCRYPT_KEY_HANDLE,
    NCRYPT_PROV_HANDLE,
};
use windows::Win32::System::WinRT::IUserConsentVerifierInterop;
use windows_future::IAsyncOperation;

/// The name the key is kept under in the TPM, one per Windows user.
const KEY_NAME: &str = "Memnox Confirm Key";
/// `BCRYPT_ECCKEY_BLOB`: a four byte magic and a four byte key length before X and Y.
const ECC_BLOB_HEADER: usize = 8;
const COORDINATE_BYTES: usize = 32;

/// The TPM key, and the window Windows Hello is raised over so it never opens behind the island.
pub struct TpmKey {
    window: isize,
}

impl TpmKey {
    /// `window` is the island's HWND, as the app's raw window handle gives it.
    pub fn new(window: isize) -> Self {
        Self { window }
    }
}

impl ConfirmKey for TpmKey {
    fn public_point(&self) -> Result<Option<[u8; POINT_BYTES]>, KeyError> {
        // A computer with no TPM 2.0 has no key Memnox trusts, so every allow stays in the terminal.
        let Ok(provider) = Provider::open() else {
            return Ok(None);
        };
        let key = provider.key()?;
        Ok(Some(key.point()?))
    }

    fn sign(&self, message: &[u8], reason: &str) -> Result<Signed, KeyError> {
        if !hello_says_yes(self.window, reason)? {
            return Ok(Signed::Declined);
        }
        let provider = Provider::open()
            .map_err(|_| KeyError("this computer has no TPM to sign with".into()))?;
        let raw = provider.key()?.sign(&Sha256::digest(message))?;
        Ok(Signed::Signature(der_from_raw(&raw)?))
    }
}

/// Windows Hello over this window, naming the call; false when the person cancelled or Hello is not set up.
fn hello_says_yes(window: isize, reason: &str) -> Result<bool, KeyError> {
    let interop = factory::<UserConsentVerifier, IUserConsentVerifierInterop>().map_err(failed)?;
    let message = HSTRING::from(format!("Memnox: {reason}"));
    let asked: IAsyncOperation<UserConsentVerificationResult> =
        unsafe { interop.RequestVerificationForWindowAsync(HWND(window as *mut _), &message) }
            .map_err(failed)?;
    Ok(asked.get().map_err(failed)? == UserConsentVerificationResult::Verified)
}

fn failed(error: windows::core::Error) -> KeyError {
    KeyError(error.message().to_string())
}

/// The Platform Crypto Provider, freed when dropped.
struct Provider(NCRYPT_PROV_HANDLE);

impl Provider {
    fn open() -> windows::core::Result<Self> {
        let mut handle = NCRYPT_PROV_HANDLE::default();
        unsafe { NCryptOpenStorageProvider(&mut handle, MS_PLATFORM_CRYPTO_PROVIDER, 0)? };
        Ok(Self(handle))
    }

    /// The key under its name, made inside the TPM the first time.
    fn key(&self) -> Result<Key, KeyError> {
        let name = HSTRING::from(KEY_NAME);
        let mut handle = NCRYPT_KEY_HANDLE::default();
        let opened = unsafe {
            NCryptOpenKey(
                self.0,
                &mut handle,
                &name,
                CERT_KEY_SPEC(0),
                NCRYPT_FLAGS(0),
            )
        };
        match opened {
            Ok(()) => Ok(Key(handle)),
            Err(error) if error.code() == NTE_BAD_KEYSET => self.create(&name),
            Err(error) => Err(failed(error)),
        }
    }

    fn create(&self, name: &HSTRING) -> Result<Key, KeyError> {
        let mut handle = NCRYPT_KEY_HANDLE::default();
        unsafe {
            NCryptCreatePersistedKey(
                self.0,
                &mut handle,
                BCRYPT_ECDSA_P256_ALGORITHM,
                name,
                CERT_KEY_SPEC(0),
                NCRYPT_FLAGS(0),
            )
            .map_err(failed)?;
        }
        let key = Key(handle);
        unsafe { NCryptFinalizeKey(key.0, NCRYPT_FLAGS(0)).map_err(failed)? };
        Ok(key)
    }
}

impl Drop for Provider {
    fn drop(&mut self) {
        let _ = unsafe { NCryptFreeObject(NCRYPT_HANDLE(self.0 .0)) };
    }
}

/// One opened key, freed when dropped.
struct Key(NCRYPT_KEY_HANDLE);

impl Key {
    fn point(&self) -> Result<[u8; POINT_BYTES], KeyError> {
        let blob = self.call(|output, size| unsafe {
            NCryptExportKey(
                self.0,
                None,
                BCRYPT_ECCPUBLIC_BLOB,
                None,
                output,
                size,
                NCRYPT_FLAGS(0),
            )
        })?;
        let coordinates = blob
            .get(ECC_BLOB_HEADER..ECC_BLOB_HEADER + 2 * COORDINATE_BYTES)
            .ok_or_else(|| KeyError("the TPM gave a short public key".into()))?;
        point_from_coordinates(
            &coordinates[..COORDINATE_BYTES],
            &coordinates[COORDINATE_BYTES..],
        )
    }

    /// Raw r||s over a SHA-256 digest, as CNG signs.
    fn sign(&self, digest: &[u8]) -> Result<Vec<u8>, KeyError> {
        self.call(|output, size| unsafe {
            NCryptSignHash(self.0, None, digest, output, size, NCRYPT_FLAGS(0))
        })
    }

    /// NCrypt's two step call: ask the size, then fill a buffer of it.
    fn call(
        &self,
        mut run: impl FnMut(Option<&mut [u8]>, *mut u32) -> windows::core::Result<()>,
    ) -> Result<Vec<u8>, KeyError> {
        let mut size = 0u32;
        run(None, &mut size).map_err(failed)?;
        let mut buffer = vec![0u8; size as usize];
        run(Some(&mut buffer), &mut size).map_err(failed)?;
        buffer.truncate(size as usize);
        Ok(buffer)
    }
}

impl Drop for Key {
    fn drop(&mut self) {
        let _ = unsafe { NCryptFreeObject(NCRYPT_HANDLE(self.0 .0)) };
    }
}
