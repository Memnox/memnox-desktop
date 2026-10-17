//! The voice of Memnox on Windows and Linux, all on this computer: Silero finds where the person
//! spoke, Parakeet writes down what they said, and Kokoro says the reply in the voice the Mac uses.
//! Nothing heard or said leaves the machine; the words go whole to the daemon, which decides.

mod hearing;
mod models;
mod speaking;

pub use hearing::{Hearing, HEARING_RATE};
pub use models::{Progress, VoiceModels};
pub use speaking::{Speaking, Voice, VOICES};
