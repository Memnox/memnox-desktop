//! The short sounds that say what happened before a word of it is said, as the Mac confirms a sent message.
//! The Mac plays its own system sounds, which Windows and Linux do not have and which may not be shipped, so
//! each is drawn here from a few sine partials shaped to sound like the one the Mac plays for that moment.

use std::f32::consts::TAU;
use std::sync::mpsc::{channel, Sender};
use std::thread;

use rodio::buffer::SamplesBuffer;
use rodio::OutputStream;

/// A moment the person should notice without looking, named as the Mac's `Cue` names it.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Cue {
    /// The orb opened and the microphone is on, the Mac's Tink.
    Listening,
    /// What they said went to the brain, the Mac's Pop.
    Sent,
    /// An agent is waiting on them, the Mac's Glass.
    Held,
    /// An allow was signed and taken, the Mac's Hero.
    Allowed,
    /// Something was left as it was, the Mac's Bottle.
    Declined,
    /// Words were typed in or a session was started, the Mac's Ping.
    Done,
    /// Memnox could not be reached, or the turn broke, the Mac's Basso.
    Failed,
    /// The question was answered somewhere else, the Mac's Purr.
    Settled,
    /// The orb closed, the Mac's Blow.
    Closed,
}

impl Cue {
    pub const ALL: [Cue; 9] = [
        Cue::Listening,
        Cue::Sent,
        Cue::Held,
        Cue::Allowed,
        Cue::Declined,
        Cue::Done,
        Cue::Failed,
        Cue::Settled,
        Cue::Closed,
    ];

    /// The cue by the name the webview sends, which is the Mac's own name for it.
    pub fn named(name: &str) -> Option<Cue> {
        Some(match name {
            "listening" => Cue::Listening,
            "sent" => Cue::Sent,
            "held" => Cue::Held,
            "allowed" => Cue::Allowed,
            "declined" => Cue::Declined,
            "done" => Cue::Done,
            "failed" => Cue::Failed,
            "settled" => Cue::Settled,
            "closed" => Cue::Closed,
            _ => return None,
        })
    }
}

/// Low enough that the ear never takes a chime for the person talking, as the Mac plays its sounds.
pub const CHIME_VOLUME: f32 = 0.35;
/// The rate the chimes are drawn at; the output converts it to whatever the speakers run at.
pub const CHIME_RATE: u32 = 44_100;
/// A fade in this long keeps the first sample from clicking.
const ATTACK_SECONDS: f32 = 0.004;

/// One sine partial: its frequency, its share of the sound, and how fast it dies away.
struct Partial {
    hertz: f32,
    share: f32,
    decay: f32,
}

const fn partial(hertz: f32, share: f32, decay: f32) -> Partial {
    Partial {
        hertz,
        share,
        decay,
    }
}

/// A struck sound: partials that start together and each fade at its own rate, as a bell or a glass does.
fn struck(rate: u32, length: f32, partials: &[Partial]) -> Vec<f32> {
    let count = (length * rate as f32) as usize;
    (0..count)
        .map(|index| {
            let time = index as f32 / rate as f32;
            partials
                .iter()
                .map(|each| {
                    each.share * (-time * each.decay).exp() * (TAU * each.hertz * time).sin()
                })
                .sum()
        })
        .collect()
}

/// Notes one after another, each struck as it comes and ringing under the next, as Hero climbs.
fn arpeggio(rate: u32, notes: &[f32], step: f32, ring: f32) -> Vec<f32> {
    let length = step * notes.len() as f32 + ring;
    let count = (length * rate as f32) as usize;
    let mut samples = vec![0.0; count];
    for (position, hertz) in notes.iter().enumerate() {
        let start = (position as f32 * step * rate as f32) as usize;
        let note = struck(
            rate,
            length - position as f32 * step,
            &[partial(*hertz, 1.0, 5.0), partial(hertz * 2.0, 0.3, 9.0)],
        );
        for (offset, sample) in note.into_iter().enumerate() {
            if let Some(slot) = samples.get_mut(start + offset) {
                *slot += sample;
            }
        }
    }
    samples
}

/// A tone sliding from one pitch to another, for the Pop's drop and the Bottle's hollow fall.
fn glide(rate: u32, length: f32, from: f32, to: f32, decay: f32, hollow: f32) -> Vec<f32> {
    let count = (length * rate as f32) as usize;
    let mut phase = 0.0_f32;
    (0..count)
        .map(|index| {
            let time = index as f32 / rate as f32;
            let hertz = from + (to - from) * (time / length);
            phase += TAU * hertz / rate as f32;
            (-time * decay).exp() * (phase.sin() + hollow * (3.0 * phase).sin())
        })
        .collect()
}

/// A breath: noise from a fixed seed, smoothed so it hisses rather than crackles, swelling then fading.
fn breath(rate: u32, length: f32) -> Vec<f32> {
    let count = (length * rate as f32) as usize;
    let mut seed: u32 = 0x9E37_79B9;
    let mut smooth = 0.0_f32;
    (0..count)
        .map(|index| {
            seed = seed.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
            let noise = (seed >> 8) as f32 / (1u32 << 24) as f32 * 2.0 - 1.0;
            smooth += 0.08 * (noise - smooth);
            let share = index as f32 / count as f32;
            smooth * (share * std::f32::consts::PI).sin()
        })
        .collect()
}

/// The cue's sound at `rate`, mono, faded in and scaled so its loudest sample is the chime volume.
pub fn chime_samples(cue: Cue, rate: u32) -> Vec<f32> {
    let mut samples = match cue {
        // A tiny bright tap.
        Cue::Listening => struck(
            rate,
            0.16,
            &[partial(2_637.0, 1.0, 40.0), partial(5_274.0, 0.5, 60.0)],
        ),
        // A short drop in pitch, like a cork.
        Cue::Sent => glide(rate, 0.09, 1_100.0, 320.0, 30.0, 0.0),
        // A glass struck, its inharmonic partials ringing on.
        Cue::Held => struck(
            rate,
            0.9,
            &[
                partial(1_568.0, 1.0, 4.0),
                partial(2_352.0, 0.45, 6.0),
                partial(3_920.0, 0.25, 9.0),
            ],
        ),
        // A rising fanfare of four notes.
        Cue::Allowed => arpeggio(rate, &[523.25, 659.25, 783.99, 1_046.5], 0.075, 0.45),
        // A hollow blown note falling a little.
        Cue::Declined => glide(rate, 0.32, 420.0, 360.0, 9.0, 0.35),
        // One clear high ping.
        Cue::Done => struck(
            rate,
            0.6,
            &[partial(1_318.5, 1.0, 6.0), partial(2_637.0, 0.2, 12.0)],
        ),
        // A low buzz of odd harmonics.
        Cue::Failed => struck(
            rate,
            0.45,
            &[
                partial(110.0, 1.0, 6.0),
                partial(330.0, 0.33, 7.0),
                partial(550.0, 0.2, 8.0),
                partial(770.0, 0.14, 9.0),
            ],
        ),
        // A soft purr: a low note trembling quickly.
        Cue::Settled => struck(
            rate,
            0.4,
            &[partial(196.0, 1.0, 6.0), partial(392.0, 0.3, 8.0)],
        )
        .into_iter()
        .enumerate()
        .map(|(index, sample)| {
            let time = index as f32 / rate as f32;
            sample * (0.6 + 0.4 * (TAU * 28.0 * time).sin())
        })
        .collect(),
        Cue::Closed => breath(rate, 0.35),
    };
    let attack = ((ATTACK_SECONDS * rate as f32) as usize).max(1);
    for (index, sample) in samples.iter_mut().take(attack).enumerate() {
        *sample *= index as f32 / attack as f32;
    }
    let peak = samples
        .iter()
        .fold(0.0_f32, |most, sample| most.max(sample.abs()));
    if peak > 0.0 {
        for sample in &mut samples {
            *sample *= CHIME_VOLUME / peak;
        }
    }
    samples
}

/// The chimes on an output of their own, so they play whether or not the Kokoro voice is installed and
/// sound over a sentence rather than waiting behind it.
pub struct Chimes {
    queue: Sender<Cue>,
}

impl Chimes {
    pub fn start() -> Self {
        let (queue, cues) = channel::<Cue>();
        thread::spawn(move || {
            let Ok((_output, handle)) = OutputStream::try_default() else {
                return;
            };
            for cue in cues {
                let _ = handle.play_raw(SamplesBuffer::new(
                    1,
                    CHIME_RATE,
                    chime_samples(cue, CHIME_RATE),
                ));
            }
        });
        Self { queue }
    }

    pub fn play(&self, cue: Cue) {
        let _ = self.queue.send(cue);
    }
}

#[cfg(test)]
mod tests {
    use super::{chime_samples, Cue, CHIME_RATE, CHIME_VOLUME};

    #[test]
    fn every_cue_is_short_and_never_louder_than_the_chime_volume() {
        for cue in Cue::ALL {
            let samples = chime_samples(cue, CHIME_RATE);
            let seconds = samples.len() as f32 / CHIME_RATE as f32;
            assert!(seconds > 0.05 && seconds < 1.2, "{cue:?} lasts {seconds}");
            let peak = samples
                .iter()
                .fold(0.0_f32, |most, sample| most.max(sample.abs()));
            assert!(
                peak <= CHIME_VOLUME + 1e-6 && peak > CHIME_VOLUME * 0.9,
                "{cue:?} peaks at {peak}"
            );
            assert_eq!(samples[0], 0.0, "{cue:?} would click");
        }
    }

    #[test]
    fn every_cue_sounds_different() {
        let all: Vec<Vec<f32>> = Cue::ALL
            .iter()
            .map(|cue| chime_samples(*cue, CHIME_RATE))
            .collect();
        for (one, first) in all.iter().enumerate() {
            for second in &all[one + 1..] {
                assert_ne!(first, second);
            }
        }
    }

    #[test]
    fn names_every_cue_as_the_mac_does() {
        for (name, cue) in [
            "listening",
            "sent",
            "held",
            "allowed",
            "declined",
            "done",
            "failed",
            "settled",
            "closed",
        ]
        .iter()
        .zip(Cue::ALL)
        {
            assert_eq!(Cue::named(name), Some(cue));
        }
        assert_eq!(Cue::named("beep"), None);
    }
}
