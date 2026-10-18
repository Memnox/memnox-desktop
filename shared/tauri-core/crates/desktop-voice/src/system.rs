//! The computer's own voice, as the Mac falls back on its system voice: chosen in the picker, and the
//! voice that speaks until Kokoro is in or when Kokoro will not load. On Windows the best OneCore voice
//! through `Windows.Media.SpeechSynthesis`; on Linux espeak ng straight into the same sink, or Speech
//! Dispatcher, which plays itself, when espeak ng is not there. Both sound plainer than Kokoro.

use std::sync::Arc;

use crate::speaking::{held_speed, Renders, USUAL_SPEED};

/// The id the picker and `voice.txt` use for the computer's own voice.
pub const SYSTEM_VOICE: &str = "system";

/// The system voice at the person's speed.
pub struct SystemVoice {
    speed: f32,
}

impl SystemVoice {
    pub fn new(speed: f32) -> Self {
        Self {
            speed: held_speed(speed),
        }
    }

    /// How much faster or slower than the Mac's usual pace, as a factor on each system's own normal rate.
    fn pace(&self) -> f32 {
        self.speed / USUAL_SPEED
    }

    /// Whether this computer has a system voice to speak with at all, for the picker to say so.
    pub fn available() -> bool {
        platform::available()
    }
}

impl Renders for SystemVoice {
    fn render(&self, sentence: &str) -> Option<(Vec<f32>, u32)> {
        platform::render(sentence, self.pace())
    }

    fn halter(&self) -> Arc<dyn Fn() + Send + Sync> {
        Arc::new(platform::halt)
    }
}

#[cfg(windows)]
mod platform {
    use windows::core::HSTRING;
    use windows::Media::SpeechSynthesis::SpeechSynthesizer;
    use windows::Storage::Streams::DataReader;
    use windows::Win32::System::Com::{CoInitializeEx, COINIT_MULTITHREADED};

    use crate::wav::wav_samples;

    /// The language picked among the installed voices, the one the rest of Memnox speaks.
    const LANGUAGE: &str = "en";

    pub fn available() -> bool {
        SpeechSynthesizer::AllVoices()
            .and_then(|voices| voices.Size())
            .map(|count| count > 0)
            .unwrap_or(false)
    }

    /// The sentence rendered to a WAV stream by WinRT and read back into samples, so it plays through
    /// the sink like Kokoro and the meter, hush and echo canceller all still work.
    pub fn render(sentence: &str, pace: f32) -> Option<(Vec<f32>, u32)> {
        // The speaking thread is the app's own, so it joins the multithreaded apartment before WinRT.
        unsafe {
            let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
        }
        let synthesizer = SpeechSynthesizer::new().ok()?;
        if let Some(voice) = english_voice() {
            let _ = synthesizer.SetVoice(&voice);
        }
        if let Ok(options) = synthesizer.Options() {
            let _ = options.SetSpeakingRate(f64::from(pace));
        }
        let stream = synthesizer
            .SynthesizeTextToStreamAsync(&HSTRING::from(sentence))
            .ok()?
            .get()
            .ok()?;
        let size = u32::try_from(stream.Size().ok()?).ok()?;
        let reader = DataReader::CreateDataReader(&stream.GetInputStreamAt(0).ok()?).ok()?;
        reader.LoadAsync(size).ok()?.get().ok()?;
        let mut bytes = vec![0_u8; size as usize];
        reader.ReadBytes(&mut bytes).ok()?;
        wav_samples(&bytes)
    }

    /// The default voice when it speaks English, else the first English one installed.
    fn english_voice() -> Option<windows::Media::SpeechSynthesis::VoiceInformation> {
        let default = SpeechSynthesizer::DefaultVoice().ok()?;
        let english = |voice: &windows::Media::SpeechSynthesis::VoiceInformation| {
            voice
                .Language()
                .map(|language| language.to_string().starts_with(LANGUAGE))
                .unwrap_or(false)
        };
        if english(&default) {
            return Some(default);
        }
        SpeechSynthesizer::AllVoices()
            .ok()?
            .into_iter()
            .find(english)
    }

    /// Rendered into the sink, so the sink's own stop is enough.
    pub fn halt() {}
}

#[cfg(target_os = "linux")]
mod platform {
    use std::process::{Command, Stdio};

    use crate::wav::wav_samples;

    /// espeak ng's normal pace in words a minute, which the person's speed scales.
    const NORMAL_WORDS_PER_MINUTE: f32 = 175.0;
    /// Speech Dispatcher's rate runs from minus a hundred to a hundred around its normal pace.
    const DISPATCHER_RATE_SPAN: f32 = 100.0;

    fn has(tool: &str) -> bool {
        Command::new(tool)
            .arg("--version")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .is_ok()
    }

    pub fn available() -> bool {
        has("espeak-ng") || has("spd-say")
    }

    /// espeak ng writes the sentence as a WAV to stdout, played like Kokoro; without it Speech Dispatcher
    /// says it itself and nothing reaches the sink, so the orb cannot ring with it.
    pub fn render(sentence: &str, pace: f32) -> Option<(Vec<f32>, u32)> {
        let words_per_minute = (NORMAL_WORDS_PER_MINUTE * pace).round().to_string();
        if let Ok(output) = Command::new("espeak-ng")
            .args([
                "--stdout",
                "-v",
                "en-us",
                "-s",
                &words_per_minute,
                "--",
                sentence,
            ])
            .stderr(Stdio::null())
            .output()
        {
            if output.status.success() {
                return wav_samples(&output.stdout);
            }
        }
        let rate = (((pace - 1.0) * DISPATCHER_RATE_SPAN).round() as i32).to_string();
        let _ = Command::new("spd-say")
            .args(["--wait", "--rate", &rate, "--", sentence])
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
        None
    }

    /// Speech Dispatcher plays outside the sink, so a stop has to reach it too.
    pub fn halt() {
        let _ = Command::new("spd-say")
            .arg("--cancel")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    }
}

#[cfg(not(any(windows, target_os = "linux")))]
mod platform {
    /// The Mac has its own app; a build here is only for checks, and says nothing.
    pub fn available() -> bool {
        false
    }

    pub fn render(_sentence: &str, _pace: f32) -> Option<(Vec<f32>, u32)> {
        None
    }

    pub fn halt() {}
}
