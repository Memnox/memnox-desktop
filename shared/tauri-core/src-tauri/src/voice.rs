//! The voice as the webview reaches it: install the models once, hear one utterance per press, and say
//! sentences in order with a stop. The core decides what is said and when; this only hears and speaks.

use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use memnox_desktop_voice::{
    Chimes, Cue, Ear, EarEvent, Hearing, Level, Speaking, Voice as Kokoro, VoiceModels, VOICES,
};
use serde::Serialize;
use tauri::ipc::Channel;
use tauri::{AppHandle, Emitter};

/// The models and the loaded engines, each loaded on first use since loading takes seconds.
pub struct Voice {
    models: VoiceModels,
    hearing: Mutex<Option<Arc<Hearing>>>,
    speaking: Mutex<Option<Arc<Speaking>>>,
    /// One microphone at a time, so a second press waits rather than opening it twice.
    listening: Mutex<()>,
    /// The file the chosen Kokoro voice is kept in, so it lasts past a restart.
    chosen: PathBuf,
    /// The microphone left open, for talking over the voice, live words and the wake word.
    ear: Mutex<Option<Ear>>,
    /// How loud the voice plays now, kept here so it outlives a change of voice.
    playing: Level,
    /// Started on the first chime, so a computer that never chimes never opens an output for them.
    chimes: Mutex<Option<Chimes>>,
}

impl Voice {
    pub fn new(models: VoiceModels, chosen: PathBuf) -> Self {
        Self {
            models,
            hearing: Mutex::new(None),
            speaking: Mutex::new(None),
            listening: Mutex::new(()),
            chosen,
            ear: Mutex::new(None),
            playing: Level::default(),
            chimes: Mutex::new(None),
        }
    }

    /// Tells the webview how loud the voice plays, about thirty times a second while it speaks and once
    /// more at nothing when it stops, so the orb rings with each syllable. Parked while the voice is quiet.
    pub fn report_levels(&self, app: AppHandle) {
        let playing = self.playing.clone();
        std::thread::spawn(move || {
            playing.wake_me();
            let mut was_playing = false;
            loop {
                let level = playing.get();
                if level > 0.0 || was_playing {
                    let _ = app.emit(LEVEL_EVENT, level);
                }
                was_playing = level > 0.0;
                if was_playing {
                    std::thread::sleep(LEVEL_EVERY);
                } else {
                    std::thread::park();
                }
            }
        });
    }

    fn close_ear(&self) {
        let open = self.ear.lock().ok().and_then(|mut ear| ear.take());
        if let Some(mut ear) = open {
            ear.close();
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
        let speaking = Arc::new(Speaking::start(
            Kokoro::new(&self.installed()?, self.choice().as_deref())?,
            self.playing.clone(),
        ));
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

/// The event the voice's loudness goes out on, and how often while it speaks.
const LEVEL_EVENT: &str = "voice-level";
const LEVEL_EVERY: std::time::Duration = std::time::Duration::from_millis(33);

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

/// What the person said in one utterance, or None when they said nothing before the wait ran out. The
/// microphone's loudness goes down `levels` as it is heard, for the orb; a send nobody hears is dropped.
#[tauri::command]
pub async fn listen_once(
    voice: tauri::State<'_, Arc<Voice>>,
    levels: Channel<f32>,
) -> Result<Option<String>, String> {
    let voice = voice.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        let _one = voice
            .listening
            .lock()
            .map_err(|_| "the microphone failed")?;
        voice.hearing()?.listen_once(|level| {
            let _ = levels.send(level);
        })
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

/// What the open ear heard, as the webview reads it.
#[derive(Clone, Serialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum HeardEvent {
    Level {
        heard: f32,
        playing: f32,
    },
    Speech,
    Words {
        text: String,
        #[serde(rename = "final")]
        last: bool,
    },
    Closed {
        error: Option<String>,
    },
}

impl From<EarEvent> for HeardEvent {
    fn from(event: EarEvent) -> Self {
        match event {
            EarEvent::Level { heard, playing } => HeardEvent::Level { heard, playing },
            EarEvent::Speech => HeardEvent::Speech,
            EarEvent::Words { text, last } => HeardEvent::Words { text, last },
            EarEvent::Closed { error } => HeardEvent::Closed { error },
        }
    }
}

/// Opens the microphone and keeps it open, reporting levels, the start of speech and words down `events`
/// until `ear_close`; an ear already open is closed first. Returns once the microphone is open.
#[tauri::command]
pub async fn ear_open(
    voice: tauri::State<'_, Arc<Voice>>,
    events: Channel<HeardEvent>,
    partials: bool,
) -> Result<(), String> {
    let voice = voice.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        voice.close_ear();
        let hearing = voice.hearing()?;
        let ear = Ear::open(hearing, voice.playing.clone(), partials, move |event| {
            let _ = events.send(event.into());
        })?;
        if let Ok(mut open) = voice.ear.lock() {
            *open = Some(ear);
        }
        Ok(())
    })
    .await
    .map_err(|error| error.to_string())?
}

/// Finishes what is being said, reports its words and `closed`, and returns after; nothing open is fine.
#[tauri::command]
pub async fn ear_close(voice: tauri::State<'_, Arc<Voice>>) -> Result<(), String> {
    let voice = voice.inner().clone();
    tauri::async_runtime::spawn_blocking(move || voice.close_ear())
        .await
        .map_err(|error| error.to_string())
}

/// Plays a cue by the Mac's name for it, quietly and over whatever is being said.
#[tauri::command]
pub fn chime(voice: tauri::State<'_, Arc<Voice>>, cue: String) -> Result<(), String> {
    let cue = Cue::named(&cue).ok_or_else(|| format!("{cue} is not a chime"))?;
    let mut chimes = voice.chimes.lock().map_err(|_| "the chimes failed")?;
    chimes.get_or_insert_with(Chimes::start).play(cue);
    Ok(())
}

fn loaded_speaking(voice: &Voice) -> Option<Arc<Speaking>> {
    voice
        .speaking
        .lock()
        .ok()
        .and_then(|speaking| speaking.clone())
}

/// Holds the voice where it is, since somebody may be talking over it.
#[tauri::command]
pub fn speak_hush(voice: tauri::State<'_, Arc<Voice>>) {
    if let Some(speaking) = loaded_speaking(&voice) {
        speaking.hush();
    }
}

/// Carries the voice on from where it was held.
#[tauri::command]
pub fn speak_carry_on(voice: tauri::State<'_, Arc<Voice>>) {
    if let Some(speaking) = loaded_speaking(&voice) {
        speaking.carry_on();
    }
}

#[tauri::command]
pub fn speak_stop(voice: tauri::State<'_, Arc<Voice>>) {
    if let Some(speaking) = loaded_speaking(&voice) {
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
    // The old voice is silenced first, since a sentence it is still saying would talk over the new one.
    if let Ok(mut loaded) = voice.speaking.lock() {
        if let Some(old) = loaded.take() {
            old.stop();
        }
    }
    Ok(())
}
