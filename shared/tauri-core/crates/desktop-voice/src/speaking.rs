//! Speaking in the person's Kokoro voice: each sentence rendered on this computer and played in order,
//! with a stop that silences what plays and drops what waits, because they talked over it.

use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::sync::mpsc::{channel, Sender};
use std::sync::{Arc, Mutex};
use std::thread::{self, Thread};
use std::time::Duration;

use rodio::buffer::SamplesBuffer;
use rodio::{OutputStream, Sink, Source};
use sherpa_onnx::{
    GenerationConfig, OfflineTts, OfflineTtsConfig, OfflineTtsKokoroModelConfig,
    OfflineTtsModelConfig,
};

use crate::echo::FarEnd;
use crate::hearing::loudness_of_rms;
use crate::VoiceModels;

/// The voices the Mac offers, in its picker's order, by Kokoro id, with each one's speaker number in
/// sherpa-onnx's v1.0 archive, which numbers its voices in the order of the model's own `speaker_names`.
pub const VOICES: [(&str, i32); 11] = [
    ("af_sky", 10),
    ("af_heart", 3),
    ("af_bella", 2),
    ("af_nicole", 6),
    ("af_sarah", 9),
    ("am_adam", 11),
    ("am_michael", 16),
    ("bf_emma", 21),
    ("bf_isabella", 22),
    ("bm_george", 26),
    ("bm_lewis", 27),
];
/// A British voice's id starts with this, and it reads with British spellings and sounds.
const BRITISH: char = 'b';
/// The Mac's own default, so a person hears the same voice on every computer.
const DEFAULT_VOICE: &str = "af_sky";
/// The Mac's unhurried pace from Kokoro.swift, and the speeds a chosen one is held between: half speed
/// and normal, slow enough to hear every word without dragging.
pub const USUAL_SPEED: f32 = 0.85;
pub const SLOWEST_SPEED: f32 = 0.5;
pub const FASTEST_SPEED: f32 = 1.0;

/// A speed the person chose, held between half speed and normal as the Mac holds `voiceSpeed`.
pub fn held_speed(speed: f32) -> f32 {
    if speed.is_finite() {
        speed.clamp(SLOWEST_SPEED, FASTEST_SPEED)
    } else {
        USUAL_SPEED
    }
}

/// Whatever turns a sentence into sound: Kokoro, or the computer's own voice until Kokoro is in.
pub trait Renders: Send + 'static {
    /// One sentence as mono samples and their rate; None when it could not be said, or was said already
    /// by a voice that plays itself.
    fn render(&self, sentence: &str) -> Option<(Vec<f32>, u32)>;
    /// What stops a voice that plays itself, since the sink never held its sound; nothing for the rest.
    fn halter(&self) -> Arc<dyn Fn() + Send + Sync> {
        Arc::new(|| {})
    }
}

/// Kokoro, loaded once, which takes a second or two.
pub struct Voice {
    tts: OfflineTts,
    speaker: i32,
    speed: f32,
}

impl Voice {
    pub fn new(models: &VoiceModels, voice: Option<&str>, speed: f32) -> Result<Self, String> {
        let model = |file: &str| Some(models.kokoro(file).to_string_lossy().into_owned());
        let chosen = voice.unwrap_or(DEFAULT_VOICE);
        // The language is the model's, not each sentence's, so a British voice loads it with British English.
        let (lexicon, lang) = if chosen.starts_with(BRITISH) {
            ("lexicon-gb-en.txt", "en-gb")
        } else {
            ("lexicon-us-en.txt", "en-us")
        };
        let config = OfflineTtsConfig {
            model: OfflineTtsModelConfig {
                kokoro: OfflineTtsKokoroModelConfig {
                    model: model("model.int8.onnx"),
                    voices: model("voices.bin"),
                    tokens: model("tokens.txt"),
                    data_dir: model("espeak-ng-data"),
                    lexicon: model(lexicon),
                    lang: Some(lang.into()),
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
            speaker: speaker_for(chosen),
            speed: held_speed(speed),
        })
    }
}

impl Renders for Voice {
    fn render(&self, sentence: &str) -> Option<(Vec<f32>, u32)> {
        let config = GenerationConfig {
            sid: self.speaker,
            speed: self.speed,
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

/// How loud the voice is playing right now, on the microphone's zero to one scale, shared with whoever
/// wants it: the ear to tell the person from the voice's own echo, and the orb to ring with each syllable.
/// A waiter parked on it is woken the moment the voice starts, so watching it costs nothing in silence.
#[derive(Clone, Default)]
pub struct Level {
    inner: Arc<LevelInner>,
}

#[derive(Default)]
struct LevelInner {
    bits: AtomicU32,
    waiter: Mutex<Option<Thread>>,
}

impl Level {
    pub fn get(&self) -> f32 {
        f32::from_bits(self.inner.bits.load(Ordering::Relaxed))
    }

    pub fn set(&self, level: f32) {
        let was = f32::from_bits(self.inner.bits.swap(level.to_bits(), Ordering::Relaxed));
        if was <= 0.0 && level > 0.0 {
            if let Some(waiter) = self
                .inner
                .waiter
                .lock()
                .ok()
                .and_then(|waiter| waiter.clone())
            {
                waiter.unpark();
            }
        }
    }

    /// Makes the calling thread the one woken when the voice starts; it then waits with `thread::park`.
    pub fn wake_me(&self) {
        if let Ok(mut waiter) = self.inner.waiter.lock() {
            *waiter = Some(thread::current());
        }
    }
}

/// About one video frame of audio, so the meter moves with each syllable and not with each sample.
const METER_SECONDS: f32 = 0.02;

/// A sentence's samples on their way to the speakers, measured as they go so the level is what is heard,
/// and handed to the echo canceller as the far end in the same blocks.
struct Metered<S> {
    inner: S,
    level: Level,
    far: FarEnd,
    block: usize,
    sum: f32,
    count: usize,
    going: Vec<f32>,
}

impl<S: Source<Item = f32>> Metered<S> {
    fn new(inner: S, level: Level, far: FarEnd) -> Self {
        let block = ((inner.sample_rate() as f32 * METER_SECONDS) as usize).max(1);
        Self {
            inner,
            level,
            far,
            block,
            sum: 0.0,
            count: 0,
            going: Vec::with_capacity(block),
        }
    }
}

impl<S: Source<Item = f32>> Iterator for Metered<S> {
    type Item = f32;

    fn next(&mut self) -> Option<f32> {
        let Some(sample) = self.inner.next() else {
            self.level.set(0.0);
            return None;
        };
        self.sum += sample * sample;
        self.count += 1;
        self.going.push(sample);
        if self.count >= self.block {
            self.level
                .set(loudness_of_rms((self.sum / self.count as f32).sqrt()));
            self.far.played(&self.going, self.inner.sample_rate());
            self.going.clear();
            self.sum = 0.0;
            self.count = 0;
        }
        Some(sample)
    }
}

impl<S: Source<Item = f32>> Source for Metered<S> {
    fn current_frame_len(&self) -> Option<usize> {
        self.inner.current_frame_len()
    }

    fn channels(&self) -> u16 {
        self.inner.channels()
    }

    fn sample_rate(&self) -> u32 {
        self.inner.sample_rate()
    }

    fn total_duration(&self) -> Option<Duration> {
        self.inner.total_duration()
    }
}

impl<S> Drop for Metered<S> {
    /// A sentence cut off is dropped half played, and the meter must not stay at its last syllable.
    fn drop(&mut self) {
        self.level.set(0.0);
    }
}

struct Line {
    sentence: String,
    epoch: u64,
    done: Sender<()>,
}

/// The voice on a thread of its own, which owns the audio output since it cannot cross threads. The sink
/// is shared, so a stop or a hush reaches the sentence playing now rather than after it ends.
pub struct Speaking {
    queue: Sender<Line>,
    /// Raised by every stop, so a sentence queued before it is dropped rather than said late.
    epoch: Arc<AtomicU64>,
    sink: Arc<Mutex<Option<Arc<Sink>>>>,
    level: Level,
    /// Told to stop as well, for a voice that plays itself rather than through the sink.
    halts: Arc<dyn Fn() + Send + Sync>,
}

impl Speaking {
    pub fn start(voice: impl Renders, level: Level, far: FarEnd) -> Self {
        let halts = voice.halter();
        let (queue, lines) = channel::<Line>();
        let epoch = Arc::new(AtomicU64::new(0));
        let sink: Arc<Mutex<Option<Arc<Sink>>>> = Arc::new(Mutex::new(None));
        let current = epoch.clone();
        let shared = sink.clone();
        let metered = level.clone();
        thread::spawn(move || {
            let Ok((_output, handle)) = OutputStream::try_default() else {
                return;
            };
            let Ok(made) = Sink::try_new(&handle) else {
                return;
            };
            let made = Arc::new(made);
            if let Ok(mut slot) = shared.lock() {
                *slot = Some(made.clone());
            }
            for line in lines {
                if line.epoch == current.load(Ordering::SeqCst) {
                    play(
                        &voice,
                        &made,
                        &line.sentence,
                        || line.epoch == current.load(Ordering::SeqCst),
                        &metered,
                        &far,
                    );
                }
                let _ = line.done.send(());
            }
        });
        Self {
            queue,
            epoch,
            sink,
            level,
            halts,
        }
    }

    /// Says one sentence after whatever is already queued; the receiver hears once it was said or dropped.
    pub fn say(&self, sentence: String) -> std::sync::mpsc::Receiver<()> {
        let (done, said) = channel();
        let epoch = self.epoch.load(Ordering::SeqCst);
        let _ = self.queue.send(Line {
            sentence,
            epoch,
            done,
        });
        said
    }

    /// Silences what plays now and drops everything waiting.
    pub fn stop(&self) {
        self.epoch.fetch_add(1, Ordering::SeqCst);
        (self.halts)();
        if let Some(sink) = self.sink() {
            sink.stop();
            // A hushed voice stopped must not stay hushed, or the next reply would never be heard.
            sink.play();
        }
        self.level.set(0.0);
    }

    /// Holds the voice where it is, because somebody may be talking over it.
    pub fn hush(&self) {
        if let Some(sink) = self.sink() {
            sink.pause();
        }
        self.level.set(0.0);
    }

    /// Carries on from where the hush held it.
    pub fn carry_on(&self) {
        if let Some(sink) = self.sink() {
            sink.play();
        }
    }

    fn sink(&self) -> Option<Arc<Sink>> {
        self.sink.lock().ok().and_then(|sink| sink.clone())
    }
}

fn play(
    voice: &dyn Renders,
    sink: &Sink,
    sentence: &str,
    still_wanted: impl Fn() -> bool,
    level: &Level,
    far: &FarEnd,
) {
    let Some((samples, rate)) = voice.render(sentence) else {
        return;
    };
    // Rendering takes a moment, and a stop during it means this sentence is no longer wanted.
    if !still_wanted() {
        return;
    }
    sink.append(Metered::new(
        SamplesBuffer::new(1, rate, samples),
        level.clone(),
        far.clone(),
    ));
    sink.sleep_until_end();
}

#[cfg(test)]
mod tests {
    use super::{held_speed, speaker_for, USUAL_SPEED};

    #[test]
    fn holds_a_chosen_speed_between_half_and_normal() {
        assert_eq!(held_speed(0.2), 0.5);
        assert_eq!(held_speed(1.4), 1.0);
        assert_eq!(held_speed(0.7), 0.7);
        assert_eq!(held_speed(f32::NAN), USUAL_SPEED);
    }

    #[test]
    fn speaks_with_the_mac_default_unless_a_known_voice_is_chosen() {
        assert_eq!(speaker_for("af_heart"), 3);
        assert_eq!(speaker_for("bm_lewis"), 27);
        assert_eq!(speaker_for("xx_unknown"), 10);
    }
}
