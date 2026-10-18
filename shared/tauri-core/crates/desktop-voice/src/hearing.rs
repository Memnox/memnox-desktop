//! Hearing one thing the person says: the microphone until Silero hears them stop, then Parakeet
//! writes it down whole. One utterance per press, so the voice's own reply is never heard as theirs.

use std::sync::mpsc::{channel, RecvTimeoutError};
use std::time::{Duration, Instant};

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use sherpa_onnx::{
    LinearResampler, OfflineRecognizer, OfflineRecognizerConfig, OfflineTransducerModelConfig,
    SileroVadModelConfig, VadModelConfig, VoiceActivityDetector,
};

use crate::VoiceModels;

/// What Silero and Parakeet both take.
pub const HEARING_RATE: i32 = 16_000;
/// Silero's window at 16 kHz.
const VAD_WINDOW: usize = 512;
/// A pause this long ends what they were saying; shorter and a breath mid sentence would cut it.
const END_OF_SPEECH_SECONDS: f32 = 0.8;
/// How long the microphone waits for them to start before it gives up.
const WAIT_TO_START: Duration = Duration::from_secs(8);
/// The longest one utterance may run, so a room that never goes quiet still ends.
const LONGEST_UTTERANCE_SECONDS: f32 = 30.0;

/// Silero and Parakeet, loaded once, which takes a few seconds.
pub struct Hearing {
    models: VoiceModels,
    recognizer: OfflineRecognizer,
}

impl Hearing {
    pub fn new(models: VoiceModels) -> Result<Self, String> {
        let mut config = OfflineRecognizerConfig::default();
        config.model_config.transducer = OfflineTransducerModelConfig {
            encoder: Some(path(models.parakeet("encoder.int8.onnx"))),
            decoder: Some(path(models.parakeet("decoder.int8.onnx"))),
            joiner: Some(path(models.parakeet("joiner.int8.onnx"))),
        };
        config.model_config.tokens = Some(path(models.parakeet("tokens.txt")));
        config.model_config.model_type = Some("nemo_transducer".into());
        config.model_config.num_threads = 2;
        let recognizer =
            OfflineRecognizer::create(&config).ok_or("Parakeet could not be loaded")?;
        Ok(Self { models, recognizer })
    }

    /// What was said in these 16 kHz mono samples, trimmed; empty when nothing was.
    pub fn transcribe(&self, samples: &[f32]) -> String {
        let stream = self.recognizer.create_stream();
        stream.accept_waveform(HEARING_RATE, samples);
        self.recognizer.decode(&stream);
        stream
            .get_result()
            .map(|result| result.text.trim().to_string())
            .unwrap_or_default()
    }

    /// The first thing said in these 16 kHz samples, found by Silero as the microphone path finds it.
    pub fn first_utterance(&self, samples: &[f32]) -> Result<Option<String>, String> {
        let detector = self.detector()?;
        for window in samples.chunks(VAD_WINDOW) {
            detector.accept_waveform(window);
        }
        detector.flush();
        Ok(detector
            .front()
            .map(|segment| self.transcribe(segment.samples()))
            .filter(|text| !text.is_empty()))
    }

    fn detector(&self) -> Result<VoiceActivityDetector, String> {
        VoiceActivityDetector::create(&vad_config(&self.models), LONGEST_UTTERANCE_SECONDS + 5.0)
            .ok_or_else(|| "Silero could not be loaded".to_string())
    }

    /// Opens the microphone, waits for the person to speak and stop, and writes it down. None when they
    /// said nothing before the wait ran out. `on_level` hears the loudness of every chunk the microphone
    /// hands over, so the orb ripples with the person's voice while they speak.
    pub fn listen_once(&self, mut on_level: impl FnMut(f32)) -> Result<Option<String>, String> {
        let detector = VoiceActivityDetector::create(
            &vad_config(&self.models),
            LONGEST_UTTERANCE_SECONDS + 5.0,
        )
        .ok_or("Silero could not be loaded")?;
        let (input, rate) = Microphone::open()?;
        let resampler = LinearResampler::create(rate, HEARING_RATE)
            .ok_or("the microphone's rate cannot be read")?;
        let started = Instant::now();
        let mut pending: Vec<f32> = Vec::new();
        loop {
            match input.samples.recv_timeout(Duration::from_millis(100)) {
                Ok(chunk) => {
                    on_level(loudness(&chunk));
                    pending.extend(resampler.resample(&chunk, false));
                }
                Err(RecvTimeoutError::Timeout) => {}
                Err(RecvTimeoutError::Disconnected) => return Err("the microphone stopped".into()),
            }
            while pending.len() >= VAD_WINDOW {
                let window: Vec<f32> = pending.drain(..VAD_WINDOW).collect();
                detector.accept_waveform(&window);
            }
            if let Some(segment) = detector.front() {
                return Ok(Some(self.transcribe(segment.samples())).filter(|text| !text.is_empty()));
            }
            if !detector.detected() && started.elapsed() > WAIT_TO_START {
                return Ok(None);
            }
        }
    }
}

fn vad_config(models: &VoiceModels) -> VadModelConfig {
    VadModelConfig {
        silero_vad: SileroVadModelConfig {
            model: Some(path(models.silero())),
            threshold: 0.5,
            min_silence_duration: END_OF_SPEECH_SECONDS,
            min_speech_duration: 0.25,
            window_size: VAD_WINDOW as i32,
            max_speech_duration: LONGEST_UTTERANCE_SECONDS,
        },
        sample_rate: HEARING_RATE,
        num_threads: 1,
        ..Default::default()
    }
}

fn path(path: std::path::PathBuf) -> String {
    path.to_string_lossy().into_owned()
}

/// The default microphone, its samples made mono and handed over a channel, closed when dropped.
struct Microphone {
    samples: std::sync::mpsc::Receiver<Vec<f32>>,
    _stream: cpal::Stream,
}

impl Microphone {
    fn open() -> Result<(Self, i32), String> {
        let device = cpal::default_host()
            .default_input_device()
            .ok_or("this computer has no microphone")?;
        let config = device
            .default_input_config()
            .map_err(|error| error.to_string())?;
        let channels = usize::from(config.channels());
        let rate = config.sample_rate().0 as i32;
        let (sender, samples) = channel();
        let stream = device
            .build_input_stream(
                &config.into(),
                move |data: &[f32], _| {
                    let _ = sender.send(mono(data, channels));
                },
                |error| eprintln!("Memnox: the microphone failed: {error}"),
                None,
            )
            .map_err(|error| error.to_string())?;
        stream.play().map_err(|error| error.to_string())?;
        Ok((
            Self {
                samples,
                _stream: stream,
            },
            rate,
        ))
    }
}

/// Amplitude to decibels is twenty times the base ten log.
const DECIBELS_PER_DECADE: f32 = 20.0;
/// The quietest amplitude counted, so silence is a finite number of decibels.
const SILENCE_FLOOR: f32 = 0.000_01;
/// The decibels shown as nothing, and the span above them shown as one, as the Mac measures a voice.
const QUIETEST_DECIBELS: f32 = -55.0;
const DECIBEL_SPAN: f32 = 45.0;

/// Loudness from nothing to one on a decibel scale, because that is how a voice sounds; ported from the Mac's `loudness(of:)`.
pub fn loudness(samples: &[f32]) -> f32 {
    if samples.is_empty() {
        return 0.0;
    }
    let rms =
        (samples.iter().map(|sample| sample * sample).sum::<f32>() / samples.len() as f32).sqrt();
    let decibels = DECIBELS_PER_DECADE * rms.max(SILENCE_FLOOR).log10();
    ((decibels - QUIETEST_DECIBELS) / DECIBEL_SPAN).clamp(0.0, 1.0)
}

/// Every frame's channels averaged into one.
fn mono(data: &[f32], channels: usize) -> Vec<f32> {
    if channels <= 1 {
        return data.to_vec();
    }
    data.chunks(channels)
        .map(|frame| frame.iter().sum::<f32>() / frame.len() as f32)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::{loudness, mono};

    #[test]
    fn averages_every_frame_into_one_channel() {
        assert_eq!(mono(&[0.2, 0.4, -1.0, 1.0], 2), vec![0.3, 0.0]);
        assert_eq!(mono(&[0.5, 0.25], 1), vec![0.5, 0.25]);
    }

    #[test]
    fn measures_loudness_on_the_decibel_scale_the_mac_draws_with() {
        assert_eq!(loudness(&[]), 0.0);
        assert_eq!(loudness(&[0.0; 64]), 0.0);
        assert_eq!(loudness(&[1.0, -1.0]), 1.0);
        // An RMS of 0.01 is -40 dB, a third of the way up from -55.
        assert!((loudness(&[0.01, -0.01]) - 15.0 / 45.0).abs() < 1e-4);
    }
}
