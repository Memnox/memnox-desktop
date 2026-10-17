//! Speaking in the person's Kokoro voice: each sentence rendered on this computer and played in order,
//! with a stop that silences what plays and drops what waits, because they talked over it.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{channel, Sender};
use std::sync::Arc;
use std::thread;

use rodio::buffer::SamplesBuffer;
use rodio::{OutputStream, Sink};
use sherpa_onnx::{
    GenerationConfig, OfflineTts, OfflineTtsConfig, OfflineTtsKokoroModelConfig,
    OfflineTtsModelConfig,
};

use crate::VoiceModels;

/// The voices the Mac offers, by Kokoro id, with each one's speaker number in sherpa-onnx's v1.0
/// archive, which numbers its voices in the order of the model's own voice list.
pub const VOICES: [(&str, i32); 5] = [
    ("af_bella", 2),
    ("af_heart", 3),
    ("af_nicole", 6),
    ("af_sarah", 9),
    ("af_sky", 10),
];
/// The Mac's own default, so a person hears the same voice on every computer.
const DEFAULT_VOICE: &str = "af_sky";
/// The Mac's unhurried pace from Kokoro.swift.
const USUAL_SPEED: f32 = 0.85;

/// Kokoro, loaded once, which takes a second or two.
pub struct Voice {
    tts: OfflineTts,
    speaker: i32,
}

impl Voice {
    pub fn new(models: &VoiceModels, voice: Option<&str>) -> Result<Self, String> {
        let model = |file: &str| Some(models.kokoro(file).to_string_lossy().into_owned());
        let config = OfflineTtsConfig {
            model: OfflineTtsModelConfig {
                kokoro: OfflineTtsKokoroModelConfig {
                    model: model("model.int8.onnx"),
                    voices: model("voices.bin"),
                    tokens: model("tokens.txt"),
                    data_dir: model("espeak-ng-data"),
                    lexicon: model("lexicon-us-en.txt"),
                    lang: Some("en-us".into()),
                    ..Default::default()
                },
                num_threads: 2,
                ..Default::default()
            },
            ..Default::default()
        };
        let tts = OfflineTts::create(&config).ok_or("Kokoro could not be loaded")?;
        Ok(Self {
            tts,
            speaker: speaker_for(voice.unwrap_or(DEFAULT_VOICE)),
        })
    }

    /// One sentence as mono samples and their rate.
    pub fn render(&self, sentence: &str) -> Option<(Vec<f32>, u32)> {
        let config = GenerationConfig {
            sid: self.speaker,
            speed: USUAL_SPEED,
            ..Default::default()
        };
        let audio =
            self.tts
                .generate_with_config(sentence, &config, None::<fn(&[f32], f32) -> bool>)?;
        Some((audio.samples().to_vec(), audio.sample_rate() as u32))
    }
}

/// The speaker number for a Kokoro id, the default voice for one this list does not know.
fn speaker_for(voice: &str) -> i32 {
    let find = |id: &str| {
        VOICES
            .iter()
            .find(|(each, _)| *each == id)
            .map(|(_, number)| *number)
    };
    find(voice).or_else(|| find(DEFAULT_VOICE)).unwrap_or(0)
}

enum Say {
    Line {
        sentence: String,
        epoch: u64,
        done: Sender<()>,
    },
    Stop,
}

/// The voice on a thread of its own, which owns the audio output since it cannot cross threads.
pub struct Speaking {
    queue: Sender<Say>,
    /// Raised by every stop, so a sentence queued before it is dropped rather than said late.
    epoch: Arc<AtomicU64>,
}

impl Speaking {
    pub fn start(voice: Voice) -> Self {
        let (queue, lines) = channel::<Say>();
        let epoch = Arc::new(AtomicU64::new(0));
        let current = epoch.clone();
        thread::spawn(move || {
            let Ok((_output, handle)) = OutputStream::try_default() else {
                return;
            };
            let Ok(sink) = Sink::try_new(&handle) else {
                return;
            };
            let sink = Arc::new(sink);
            for say in lines {
                match say {
                    Say::Stop => sink.stop(),
                    Say::Line {
                        sentence,
                        epoch,
                        done,
                    } => {
                        if epoch == current.load(Ordering::SeqCst) {
                            play(&voice, &sink, &sentence);
                        }
                        let _ = done.send(());
                    }
                }
            }
        });
        Self { queue, epoch }
    }

    /// Says one sentence after whatever is already queued; the receiver hears once it was said or dropped.
    pub fn say(&self, sentence: String) -> std::sync::mpsc::Receiver<()> {
        let (done, said) = channel();
        let epoch = self.epoch.load(Ordering::SeqCst);
        let _ = self.queue.send(Say::Line {
            sentence,
            epoch,
            done,
        });
        said
    }

    /// Silences what plays and drops everything waiting.
    pub fn stop(&self) {
        self.epoch.fetch_add(1, Ordering::SeqCst);
        let _ = self.queue.send(Say::Stop);
    }
}

fn play(voice: &Voice, sink: &Sink, sentence: &str) {
    let Some((samples, rate)) = voice.render(sentence) else {
        return;
    };
    sink.append(SamplesBuffer::new(1, rate, samples));
    sink.sleep_until_end();
}

#[cfg(test)]
mod tests {
    use super::speaker_for;

    #[test]
    fn speaks_with_the_mac_default_unless_a_known_voice_is_chosen() {
        assert_eq!(speaker_for("af_heart"), 3);
        assert_eq!(speaker_for("xx_unknown"), 10);
    }
}
