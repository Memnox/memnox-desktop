//! The voice as the webview reaches it: install the models once, hear one utterance per press, and say
//! sentences in order with a stop. The core decides what is said and when; this only hears and speaks.

use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use memnox_desktop_voice::{Hearing, Speaking, Voice as Kokoro, VoiceModels, VOICES};
use serde::Serialize;
use tauri::ipc::Channel;

/// The models and the loaded engines, each loaded on first use since loading takes seconds.
pub struct Voice {
    models: VoiceModels,
    hearing: Mutex<Option<Arc<Hearing>>>,
    speaking: Mutex<Option<Arc<Speaking>>>,
    /// One microphone at a time, so a second press waits rather than opening it twice.
    listening: Mutex<()>,
    /// The file the chosen Kokoro voice is kept in, so it lasts past a restart.
    chosen: PathBuf,
}

impl Voice {
    pub fn new(models: VoiceModels, chosen: PathBuf) -> Self {
        Self {
            models,
            hearing: Mutex::new(None),
            speaking: Mutex::new(None),
            listening: Mutex::new(()),
            chosen,
        }
    }

    /// The Kokoro voice the person chose, None for the Mac's default.
    fn choice(&self) -> Option<String> {
        let kept = std::fs::read_to_string(&self.chosen).ok()?;
        let id = kept.trim();
        VOICES
            .iter()
            .any(|(each, _)| *each == id)
            .then(|| id.to_string())
    }

    fn hearing(&self) -> Result<Arc<Hearing>, String> {
        let mut loaded = self.hearing.lock().map_err(|_| "the voice failed")?;
        if let Some(hearing) = loaded.as_ref() {
            return Ok(hearing.clone());
        }
        let hearing = Arc::new(Hearing::new(self.installed()?)?);
        *loaded = Some(hearing.clone());
        Ok(hearing)
    }

    fn speaking(&self) -> Result<Arc<Speaking>, String> {
        let mut loaded = self.speaking.lock().map_err(|_| "the voice failed")?;
        if let Some(speaking) = loaded.as_ref() {
            return Ok(speaking.clone());
        }
        let speaking = Arc::new(Speaking::start(Kokoro::new(
            &self.installed()?,
            self.choice().as_deref(),
        )?));
        *loaded = Some(speaking.clone());
        Ok(speaking)
    }

    fn installed(&self) -> Result<VoiceModels, String> {
        if self.models.installed() {
            Ok(self.models.clone())
        } else {
            Err("the voice is not installed yet".into())
        }
    }
}

/// One step of the install, as the island draws it.
#[derive(Clone, Serialize)]
pub struct InstallStep {
    part: &'static str,
    done: u64,
    total: Option<u64>,
}

#[tauri::command]
pub fn voice_installed(voice: tauri::State<'_, Arc<Voice>>) -> bool {
    voice.models.installed()
}

/// Fetches the models, reporting each step, which runs to a few hundred megabytes.
#[tauri::command]
pub async fn voice_install(
    voice: tauri::State<'_, Arc<Voice>>,
    steps: Channel<InstallStep>,
) -> Result<(), String> {
    let models = voice.models.clone();
    tauri::async_runtime::spawn_blocking(move || {
        models.install(|step| {
            let _ = steps.send(InstallStep {
                part: step.part,
                done: step.done,
                total: step.total,
            });
        })
    })
    .await
    .map_err(|error| error.to_string())?
    .map_err(|error| format!("the voice could not be installed: {error}"))
}

/// What the person said in one utterance, or None when they said nothing before the wait ran out.
#[tauri::command]
pub async fn listen_once(voice: tauri::State<'_, Arc<Voice>>) -> Result<Option<String>, String> {
    let voice = voice.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        let _one = voice
            .listening
            .lock()
            .map_err(|_| "the microphone failed")?;
        voice.hearing()?.listen_once()
    })
    .await
    .map_err(|error| error.to_string())?
}

/// Says one sentence after whatever is queued, and returns once it was said or stopped.
#[tauri::command]
pub async fn speak(voice: tauri::State<'_, Arc<Voice>>, sentence: String) -> Result<(), String> {
    let voice = voice.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        let said = voice.speaking()?.say(sentence);
        let _ = said.recv();
        Ok(())
    })
    .await
    .map_err(|error| error.to_string())?
}

#[tauri::command]
pub fn speak_stop(voice: tauri::State<'_, Arc<Voice>>) {
    let loaded = voice
        .speaking
        .lock()
        .ok()
        .and_then(|speaking| speaking.clone());
    if let Some(speaking) = loaded {
        speaking.stop();
    }
}

/// The voices on offer by Kokoro id, and the one chosen, the Mac's default when none was.
#[derive(Serialize)]
pub struct VoiceChoice {
    voices: Vec<&'static str>,
    chosen: Option<String>,
}

#[tauri::command]
pub fn voice_choice(voice: tauri::State<'_, Arc<Voice>>) -> VoiceChoice {
    VoiceChoice {
        voices: VOICES.iter().map(|(id, _)| *id).collect(),
        chosen: voice.choice(),
    }
}

/// Keeps the chosen voice and lets the next sentence load it; an id not on offer is refused.
#[tauri::command]
pub fn choose_voice(voice: tauri::State<'_, Arc<Voice>>, id: String) -> Result<(), String> {
    if !VOICES.iter().any(|(each, _)| *each == id) {
        return Err(format!("{id} is not a voice on offer"));
    }
    if let Some(dir) = voice.chosen.parent() {
        std::fs::create_dir_all(dir).map_err(|error| error.to_string())?;
    }
    std::fs::write(&voice.chosen, &id).map_err(|error| error.to_string())?;
    if let Ok(mut loaded) = voice.speaking.lock() {
        *loaded = None;
    }
    Ok(())
}
