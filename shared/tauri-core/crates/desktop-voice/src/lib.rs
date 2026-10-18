//! The voice of Memnox on Windows and Linux, all on this computer: Silero finds where the person
//! spoke, Parakeet writes down what they said, and Kokoro says the reply in the voice the Mac uses.
//! Nothing heard or said leaves the machine; the words go whole to the daemon, which decides.

mod chimes;
mod ear;
mod echo;
mod hearing;
mod models;
mod speaking;
mod system;
mod wav;

pub use chimes::{chime_samples, Chimes, Cue, CHIME_RATE, CHIME_VOLUME};
pub use ear::{Ear, EarEvent};
pub use echo::{Canceller, FarEnd};
pub use hearing::{loudness, loudness_of_rms, Hearing, HEARING_RATE};
pub use models::{Progress, VoiceModels};
pub use speaking::{held_speed, Level, Renders, Speaking, Voice, USUAL_SPEED, VOICES};
pub use system::{SystemVoice, SYSTEM_VOICE};
pub use wav::wav_samples;
