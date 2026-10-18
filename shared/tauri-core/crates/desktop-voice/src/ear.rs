//! An ear left open: the microphone runs through Silero for as long as it is open, so the person can be
//! heard while the voice talks, words show as they are said, and one listen carries on into the next.
//! It only reports what it heard and how loud; whoever opened it decides what any of that means.

use std::collections::VecDeque;
use std::sync::mpsc::{channel, RecvTimeoutError, Sender, TryRecvError};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use sherpa_onnx::LinearResampler;

use crate::hearing::{loudness, Microphone, HEARING_RATE, VAD_WINDOW};
use crate::speaking::Level;
use crate::Hearing;

/// What the ear reports, in the order it happened.
#[derive(Clone, Debug, PartialEq)]
pub enum EarEvent {
    /// How loud the room is and how loud the voice is playing at that moment, both on the zero to one scale.
    Level { heard: f32, playing: f32 },
    /// Somebody started talking, which begins a new stretch of speech.
    Speech,
    /// The words of the stretch being said: a guess while it goes on, then the whole of it once it ends.
    Words { text: String, last: bool },
    /// The ear closed, on purpose or because the microphone went; always the final event.
    Closed { error: Option<String> },
}

/// At most this often a level is reported, since the orb draws at sixty frames and the webview needs no more.
const LEVEL_EVERY: Duration = Duration::from_millis(40);
/// How often the words said so far are written down again while somebody talks.
const PARTIAL_EVERY: Duration = Duration::from_millis(400);
/// Kept from before Silero noticed speech, so the first syllable is not lost to its reaction time.
const PRE_ROLL_SECONDS: f32 = 0.3;
/// Shorter than this a guess is mostly breath and comes back empty.
const SHORTEST_PARTIAL_SECONDS: f32 = 0.4;
/// A guess only looks at the newest stretch, so a long monologue never makes each guess slower.
const LONGEST_PARTIAL_SECONDS: f32 = 20.0;
/// How long one look at the microphone waits, short so a close is answered at once.
const LOOK: Duration = Duration::from_millis(50);

fn seconds(samples: f32) -> usize {
    (samples * HEARING_RATE as f32) as usize
}

/// The open microphone; closing it finishes the stretch being said and reports it before `Closed`.
pub struct Ear {
    stop: Option<Sender<()>>,
    worker: Option<JoinHandle<()>>,
}

impl Ear {
    /// Opens the microphone on a thread of its own and returns once it is open, or why it could not be.
    pub fn open(
        hearing: Arc<Hearing>,
        playing: Level,
        partials: bool,
        mut report: impl FnMut(EarEvent) + Send + 'static,
    ) -> Result<Self, String> {
        let (stop, stopped) = channel::<()>();
        let (opened, ready) = channel::<Result<(), String>>();
        let worker = thread::spawn(move || {
            let (microphone, rate) = match Microphone::open() {
                Ok(open) => open,
                Err(why) => {
                    let _ = opened.send(Err(why));
                    return;
                }
            };
            let Some(resampler) = LinearResampler::create(rate, HEARING_RATE) else {
                let _ = opened.send(Err("the microphone's rate cannot be read".into()));
                return;
            };
            let detector = match hearing.detector() {
                Ok(detector) => detector,
                Err(why) => {
                    let _ = opened.send(Err(why));
                    return;
                }
            };
            let _ = opened.send(Ok(()));
            let mut state = Stretch::new(partials);
            let mut pending: Vec<f32> = Vec::new();
            let mut loudest = 0.0_f32;
            let mut levelled = Instant::now() - LEVEL_EVERY;
            let error = loop {
                match stopped.try_recv() {
                    Ok(()) | Err(TryRecvError::Disconnected) => break None,
                    Err(TryRecvError::Empty) => {}
                }
                match microphone.samples.recv_timeout(LOOK) {
                    Ok(chunk) => {
                        loudest = loudest.max(loudness(&chunk));
                        if levelled.elapsed() >= LEVEL_EVERY {
                            report(EarEvent::Level {
                                heard: loudest,
                                playing: playing.get(),
                            });
                            loudest = 0.0;
                            levelled = Instant::now();
                        }
                        pending.extend(resampler.resample(&chunk, false));
                    }
                    Err(RecvTimeoutError::Timeout) => {}
                    Err(RecvTimeoutError::Disconnected) => {
                        break Some("the microphone stopped".to_string())
                    }
                }
                while pending.len() >= VAD_WINDOW {
                    let window: Vec<f32> = pending.drain(..VAD_WINDOW).collect();
                    detector.accept_waveform(&window);
                    state.heard(&window, detector.detected(), &mut report);
                    while let Some(segment) = detector.front() {
                        detector.pop();
                        state.ended(hearing.transcribe(segment.samples()), &mut report);
                    }
                    if !detector.detected() {
                        state.quiet();
                    }
                }
                state.guess(&hearing, &mut report);
            };
            // What was still being said is finished as it stands, so letting go never loses the last words.
            detector.flush();
            while let Some(segment) = detector.front() {
                detector.pop();
                state.ended(hearing.transcribe(segment.samples()), &mut report);
            }
            report(EarEvent::Closed { error });
        });
        match ready.recv() {
            Ok(Ok(())) => Ok(Self {
                stop: Some(stop),
                worker: Some(worker),
            }),
            Ok(Err(why)) => {
                let _ = worker.join();
                Err(why)
            }
            Err(_) => {
                let _ = worker.join();
                Err("the microphone failed".into())
            }
        }
    }

    /// Finishes what is being said, reports it, sends `Closed`, and returns once all of that is done.
    pub fn close(&mut self) {
        if let Some(stop) = self.stop.take() {
            let _ = stop.send(());
        }
        if let Some(worker) = self.worker.take() {
            let _ = worker.join();
        }
    }
}

impl Drop for Ear {
    fn drop(&mut self) {
        self.close();
    }
}

/// One stretch of speech as it is heard: the samples since it began, and the last guess at its words.
struct Stretch {
    partials: bool,
    speaking: bool,
    before: VecDeque<f32>,
    said: Vec<f32>,
    guessed: String,
    guessed_at: Instant,
}

impl Stretch {
    fn new(partials: bool) -> Self {
        Self {
            partials,
            speaking: false,
            before: VecDeque::with_capacity(seconds(PRE_ROLL_SECONDS)),
            said: Vec::new(),
            guessed: String::new(),
            guessed_at: Instant::now(),
        }
    }

    fn heard(&mut self, window: &[f32], detected: bool, report: &mut impl FnMut(EarEvent)) {
        if detected && !self.speaking {
            self.speaking = true;
            self.said = self.before.drain(..).collect();
            self.guessed.clear();
            self.guessed_at = Instant::now();
            report(EarEvent::Speech);
        }
        if self.speaking {
            self.said.extend_from_slice(window);
        } else {
            self.before.extend(window.iter().copied());
            let extra = self.before.len().saturating_sub(seconds(PRE_ROLL_SECONDS));
            self.before.drain(..extra);
        }
    }

    fn ended(&mut self, text: String, report: &mut impl FnMut(EarEvent)) {
        self.quiet();
        if !text.is_empty() {
            report(EarEvent::Words { text, last: true });
        }
    }

    fn quiet(&mut self) {
        self.speaking = false;
        self.said.clear();
        self.guessed.clear();
    }

    fn guess(&mut self, hearing: &Hearing, report: &mut impl FnMut(EarEvent)) {
        if !self.partials
            || !self.speaking
            || self.guessed_at.elapsed() < PARTIAL_EVERY
            || self.said.len() < seconds(SHORTEST_PARTIAL_SECONDS)
        {
            return;
        }
        self.guessed_at = Instant::now();
        let from = self
            .said
            .len()
            .saturating_sub(seconds(LONGEST_PARTIAL_SECONDS));
        let text = hearing.transcribe(&self.said[from..]);
        if !text.is_empty() && text != self.guessed {
            self.guessed = text.clone();
            report(EarEvent::Words { text, last: false });
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{seconds, EarEvent, Stretch, PRE_ROLL_SECONDS};

    #[test]
    fn keeps_a_moment_from_before_speech_and_reports_its_start_once() {
        let mut stretch = Stretch::new(false);
        let mut events = Vec::new();
        let quiet = vec![0.0; seconds(1.0)];
        stretch.heard(&quiet, false, &mut |event| events.push(event));
        assert_eq!(stretch.before.len(), seconds(PRE_ROLL_SECONDS));
        stretch.heard(&[0.5; 512], true, &mut |event| events.push(event));
        stretch.heard(&[0.5; 512], true, &mut |event| events.push(event));
        assert_eq!(events, vec![EarEvent::Speech]);
        assert_eq!(stretch.said.len(), seconds(PRE_ROLL_SECONDS) + 1024);
    }

    #[test]
    fn reports_finished_words_and_drops_empty_ones() {
        let mut stretch = Stretch::new(true);
        let mut events = Vec::new();
        stretch.heard(&[0.5; 512], true, &mut |event| events.push(event));
        stretch.ended(String::new(), &mut |event| events.push(event));
        stretch.ended("hello there".into(), &mut |event| events.push(event));
        assert_eq!(
            events,
            vec![
                EarEvent::Speech,
                EarEvent::Words {
                    text: "hello there".into(),
                    last: true
                }
            ]
        );
        assert!(!stretch.speaking);
    }
}
