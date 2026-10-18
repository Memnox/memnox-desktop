//! Where the voice's models live and how they get there: one folder under the app's data, filled once
//! from the memnox-assets mirror of sherpa-onnx's releases, or from another mirror when `MEMNOX_VOICE_PACK`
//! names one, since GitHub's release host is slow from some places and a mirror behind a CDN is not.

use std::fs;
use std::io::{self, Read};
use std::path::{Path, PathBuf};

/// sherpa-onnx's release files copied byte for byte, laid out as the releases are, so either host serves the same paths.
const MIRROR: &str = "https://assets.memnox.com/sherpa";
/// The releases themselves, asked when the mirror lacks a file, so a file not mirrored yet still installs.
const RELEASES: &str = "https://github.com/k2-fsa/sherpa-onnx/releases/download";
/// Parakeet TDT 0.6B v3 in int8: twenty five European languages, punctuated, about 490 MB.
const PARAKEET: &str = "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8";
/// Kokoro v1.0, the model the Mac speaks with, in int8: about 130 MB rather than 350.
const KOKORO: &str = "kokoro-int8-multi-lang-v1_0";
const SILERO: &str = "silero_vad.onnx";

/// One piece of the install, for the island to show.
#[derive(Clone, Debug)]
pub struct Progress {
    pub part: &'static str,
    pub done: u64,
    pub total: Option<u64>,
}

/// The voice's models under one folder.
#[derive(Clone, Debug)]
pub struct VoiceModels {
    dir: PathBuf,
}

impl VoiceModels {
    pub fn new(dir: impl Into<PathBuf>) -> Self {
        Self { dir: dir.into() }
    }

    pub fn silero(&self) -> PathBuf {
        self.dir.join(SILERO)
    }

    pub fn parakeet(&self, file: &str) -> PathBuf {
        self.dir.join(PARAKEET).join(file)
    }

    pub fn kokoro(&self, file: &str) -> PathBuf {
        self.dir.join(KOKORO).join(file)
    }

    /// Every file the voice opens, so a half finished install never counts as one.
    fn required(&self) -> Vec<PathBuf> {
        vec![
            self.silero(),
            self.parakeet("encoder.int8.onnx"),
            self.parakeet("decoder.int8.onnx"),
            self.parakeet("joiner.int8.onnx"),
            self.parakeet("tokens.txt"),
            self.kokoro("model.int8.onnx"),
            self.kokoro("voices.bin"),
            self.kokoro("tokens.txt"),
            self.kokoro("espeak-ng-data"),
        ]
    }

    pub fn installed(&self) -> bool {
        self.required().iter().all(|path| path.exists())
    }

    /// Kokoro alone, since the computer's own voice speaks until it is in.
    pub fn kokoro_installed(&self) -> bool {
        self.required()
            .iter()
            .filter(|path| path.starts_with(self.dir.join(KOKORO)))
            .all(|path| path.exists())
    }

    /// Fetches whatever is missing. Each archive unpacks into a folder of its own name beside the others,
    /// and only once whole, so a broken download is fetched again rather than half used.
    pub fn install(&self, mut progress: impl FnMut(Progress)) -> io::Result<()> {
        fs::create_dir_all(&self.dir)?;
        let base = std::env::var("MEMNOX_VOICE_PACK").unwrap_or_else(|_| MIRROR.to_string());
        if !self.silero().exists() {
            let bytes = fetch(
                &base,
                &format!("asr-models/{SILERO}"),
                "speech detection",
                &mut progress,
            )?;
            write_whole(&self.silero(), &bytes)?;
        }
        for (part, kind, name) in [
            ("hearing", "asr-models", PARAKEET),
            ("voice", "tts-models", KOKORO),
        ] {
            if self.dir.join(name).exists() {
                continue;
            }
            let bytes = fetch(
                &base,
                &format!("{kind}/{name}.tar.bz2"),
                part,
                &mut progress,
            )?;
            unpack(&bytes, &self.dir, name)?;
        }
        Ok(())
    }
}

/// One release file from `base`, then from sherpa-onnx's own releases when that host fails.
fn fetch(
    base: &str,
    path: &str,
    part: &'static str,
    progress: &mut impl FnMut(Progress),
) -> io::Result<Vec<u8>> {
    download(&format!("{base}/{path}"), part, progress).or_else(|first| {
        if base == RELEASES {
            Err(first)
        } else {
            download(&format!("{RELEASES}/{path}"), part, progress)
        }
    })
}

fn download(
    url: &str,
    part: &'static str,
    progress: &mut impl FnMut(Progress),
) -> io::Result<Vec<u8>> {
    let response = ureq::get(url)
        .call()
        .map_err(|error| io::Error::other(format!("{part}: {error}")))?;
    let total = response
        .header("content-length")
        .and_then(|length| length.parse().ok());
    let mut reader = response.into_reader();
    let mut bytes = Vec::with_capacity(total.unwrap_or(0) as usize);
    let mut buffer = vec![0u8; 1 << 16];
    loop {
        let read = reader.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        bytes.extend_from_slice(&buffer[..read]);
        progress(Progress {
            part,
            done: bytes.len() as u64,
            total,
        });
    }
    if total.is_some_and(|total| total != bytes.len() as u64) {
        return Err(io::Error::other(format!(
            "{part}: the download stopped short"
        )));
    }
    Ok(bytes)
}

/// Unpacks into a folder beside the target, renamed into place only once every file is out.
fn unpack(archive: &[u8], dir: &Path, name: &str) -> io::Result<()> {
    let staging = dir.join(format!(".{name}.partial"));
    let _ = fs::remove_dir_all(&staging);
    fs::create_dir_all(&staging)?;
    tar::Archive::new(bzip2::read::BzDecoder::new(archive)).unpack(&staging)?;
    fs::rename(staging.join(name), dir.join(name))?;
    fs::remove_dir_all(&staging)
}

fn write_whole(path: &Path, bytes: &[u8]) -> io::Result<()> {
    let partial = path.with_extension("partial");
    fs::write(&partial, bytes)?;
    fs::rename(partial, path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counts_an_empty_folder_as_not_installed() {
        let dir = std::env::temp_dir().join("memnox-voice-empty");
        let _ = fs::remove_dir_all(&dir);
        assert!(!VoiceModels::new(&dir).installed());
    }

    #[test]
    fn unpacks_an_archive_into_its_own_folder_only_once_whole() {
        let dir = std::env::temp_dir().join("memnox-voice-unpack");
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        let mut tarball = tar::Builder::new(Vec::new());
        let mut header = tar::Header::new_gnu();
        header.set_size(5);
        header.set_cksum();
        tarball
            .append_data(&mut header, "model/tokens.txt", &b"hello"[..])
            .unwrap();
        let mut compressed = Vec::new();
        let plain = tarball.into_inner().unwrap();
        let mut encoder = bzip2::read::BzEncoder::new(&plain[..], bzip2::Compression::fast());
        encoder.read_to_end(&mut compressed).unwrap();
        unpack(&compressed, &dir, "model").unwrap();
        assert_eq!(
            fs::read_to_string(dir.join("model/tokens.txt")).unwrap(),
            "hello"
        );
        assert!(!dir.join(".model.partial").exists());
    }
}
