//! Says a sentence with Kokoro, writes it back down with Parakeet, then finds it again in silence as the
//! microphone path does, the whole voice on this computer with no microphone and no speaker:
//! `cargo run --release --example round_trip -- <models folder>`.

use memnox_desktop_voice::{Hearing, Renders, Voice, VoiceModels, HEARING_RATE, USUAL_SPEED};

fn main() {
    let dir = std::env::args().nth(1).expect("the models folder");
    let models = VoiceModels::new(dir);
    assert!(models.installed(), "the models folder is missing a file");
    let sentence = "Codex wants to push to main. Allow it, or deny?";
    let voice = Voice::new(&models, None, USUAL_SPEED).expect("Kokoro");
    let (samples, rate) = voice.render(sentence).expect("rendered");
    println!(
        "said {:.1} seconds at {rate} Hz",
        samples.len() as f32 / rate as f32
    );
    let resampler =
        sherpa_onnx::LinearResampler::create(rate as i32, HEARING_RATE).expect("resampler");
    let spoken = resampler.resample(&samples, true);
    let hearing = Hearing::new(models).expect("Parakeet");
    println!("heard: {}", hearing.transcribe(&spoken));
    // A second of silence either side, as a microphone would hear it, so Silero has to find the words.
    let silence = vec![0.0f32; HEARING_RATE as usize];
    let room: Vec<f32> = silence
        .iter()
        .chain(&spoken)
        .chain(&silence)
        .copied()
        .collect();
    println!(
        "found: {:?}",
        hearing.first_utterance(&room).expect("Silero")
    );
}
