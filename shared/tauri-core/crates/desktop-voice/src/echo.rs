//! The voice's own sound taken back out of the microphone, so Parakeet hears the person and not Kokoro
//! coming out of laptop speakers. WebRTC's echo canceller (AEC3, through the pure Rust port in `sonora`,
//! which needs no C++ toolchain on Windows or Linux) is fed what the speakers play as the far end, ten
//! milliseconds at a time, beside the microphone's own ten. Off for a headset, where there is no echo.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

use sonora::config::EchoCanceller;
use sonora::{AudioProcessing, Config, StreamConfig};

use crate::hearing::HEARING_RATE;

/// WebRTC processes audio in frames of ten milliseconds.
const FRAMES_PER_SECOND: u32 = 100;
/// The most far end kept waiting for the microphone, so a voice played while no ear is open is dropped
/// rather than heard against the next listen. AEC3 itself finds delays well inside this.
const FAR_END_KEPT_SECONDS: u32 = 1;

/// What the speakers are playing, as it goes out, shared between the voice and the ear.
#[derive(Clone)]
pub struct FarEnd {
    inner: Arc<Mutex<FarInner>>,
    /// The person's switch: off for a headset whose own microphone hears no echo.
    cancels: Arc<AtomicBool>,
}

struct FarInner {
    samples: VecDeque<f32>,
    rate: u32,
}

impl Default for FarEnd {
    fn default() -> Self {
        Self {
            inner: Arc::new(Mutex::new(FarInner {
                samples: VecDeque::new(),
                rate: 0,
            })),
            cancels: Arc::new(AtomicBool::new(true)),
        }
    }
}

impl FarEnd {
    /// Samples the speakers are about to play, mono at `rate`.
    pub fn played(&self, samples: &[f32], rate: u32) {
        let Ok(mut far) = self.inner.lock() else {
            return;
        };
        if far.rate != rate {
            far.samples.clear();
            far.rate = rate;
        }
        far.samples.extend(samples.iter().copied());
        let most = (rate * FAR_END_KEPT_SECONDS) as usize;
        let extra = far.samples.len().saturating_sub(most);
        far.samples.drain(..extra);
    }

    /// One frame of what was played, silence where nothing was, and the rate it is at.
    fn frame(&self) -> Option<(Vec<f32>, u32)> {
        let mut far = self.inner.lock().ok()?;
        if far.rate == 0 {
            return None;
        }
        let wanted = (far.rate / FRAMES_PER_SECOND) as usize;
        let take = wanted.min(far.samples.len());
        let mut frame: Vec<f32> = far.samples.drain(..take).collect();
        frame.resize(wanted, 0.0);
        Some((frame, far.rate))
    }

    pub fn set_cancelling(&self, on: bool) {
        self.cancels.store(on, Ordering::Relaxed);
    }

    pub fn cancelling(&self) -> bool {
        self.cancels.load(Ordering::Relaxed)
    }
}

/// The canceller for one open ear, over 16 kHz mono microphone samples.
pub struct Canceller {
    far: FarEnd,
    apm: Option<(AudioProcessing, u32)>,
    pending: Vec<f32>,
}

impl Canceller {
    pub fn new(far: FarEnd) -> Self {
        Self {
            far,
            apm: None,
            pending: Vec::new(),
        }
    }

    /// The microphone's samples less the voice's echo, in whole frames; a part frame waits for the rest.
    /// With the switch off the samples pass through untouched.
    pub fn clean(&mut self, captured: &[f32]) -> Vec<f32> {
        if !self.far.cancelling() {
            self.apm = None;
            let mut all = std::mem::take(&mut self.pending);
            all.extend_from_slice(captured);
            return all;
        }
        self.pending.extend_from_slice(captured);
        let frame = (HEARING_RATE as u32 / FRAMES_PER_SECOND) as usize;
        let mut cleaned = Vec::with_capacity(self.pending.len());
        while self.pending.len() >= frame {
            let near: Vec<f32> = self.pending.drain(..frame).collect();
            let mut out = vec![0.0_f32; frame];
            let far = self.far.frame();
            let Some(apm) = self.processing(far.as_ref().map(|(_, rate)| *rate)) else {
                cleaned.extend_from_slice(&near);
                continue;
            };
            if let Some((far, _)) = far.as_ref() {
                let mut ignored = vec![0.0_f32; far.len()];
                let _ = apm.process_render_f32(&[far], &mut [&mut ignored]);
            }
            if apm.process_capture_f32(&[&near], &mut [&mut out]).is_ok() {
                cleaned.extend_from_slice(&out);
            } else {
                cleaned.extend_from_slice(&near);
            }
        }
        cleaned
    }

    /// The processor for this far end rate, built again when the voice changes rate.
    fn processing(&mut self, far_rate: Option<u32>) -> Option<&mut AudioProcessing> {
        let rate = far_rate.unwrap_or(HEARING_RATE as u32);
        if self.apm.as_ref().map(|(_, at)| *at) != Some(rate) {
            let config = Config {
                echo_canceller: Some(EchoCanceller::default()),
                ..Default::default()
            };
            let apm = AudioProcessing::builder()
                .config(config)
                .capture_config(StreamConfig::new(HEARING_RATE as u32, 1))
                .render_config(StreamConfig::new(rate, 1))
                .build();
            self.apm = Some((apm, rate));
        }
        self.apm.as_mut().map(|(apm, _)| apm)
    }
}

#[cfg(test)]
mod tests {
    use super::{Canceller, FarEnd};

    /// A tone at 16 kHz, standing in for the voice heard back through the microphone.
    fn tone(count: usize, from: usize) -> Vec<f32> {
        (from..from + count)
            .map(|n| 0.3 * (n as f32 * 2.0 * std::f32::consts::PI * 440.0 / 16_000.0).sin())
            .collect()
    }

    #[test]
    fn passes_whole_frames_and_keeps_the_rest_for_the_next_look() {
        let mut canceller = Canceller::new(FarEnd::default());
        assert_eq!(canceller.clean(&[0.0; 250]).len(), 160);
        assert_eq!(canceller.clean(&[0.0; 70]).len(), 160);
    }

    #[test]
    fn takes_the_voice_back_out_of_what_the_microphone_hears() {
        let far = FarEnd::default();
        let mut canceller = Canceller::new(far.clone());
        let mut heard = 0.0_f32;
        let mut played = 0.0_f32;
        for second in 0..4 {
            for frame in 0..100 {
                let at = (second * 100 + frame) * 160;
                let voice = tone(160, at);
                far.played(&voice, 16_000);
                let echo: Vec<f32> = voice.iter().map(|sample| sample * 0.5).collect();
                let out = canceller.clean(&echo);
                if second == 3 {
                    heard += out.iter().map(|sample| sample * sample).sum::<f32>();
                    played += echo.iter().map(|sample| sample * sample).sum::<f32>();
                }
            }
        }
        // Once AEC3 has found the echo path, most of the echo is gone.
        assert!(heard < played * 0.25, "heard {heard} of {played}");
    }

    #[test]
    fn leaves_the_microphone_alone_with_the_switch_off() {
        let far = FarEnd::default();
        far.set_cancelling(false);
        let mut canceller = Canceller::new(far);
        assert_eq!(canceller.clean(&[0.25; 160]), vec![0.25; 160]);
    }
}
