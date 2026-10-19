//! The voice as the webview reaches it: install the models once, hear one utterance per press, and say
//! sentences in order with a stop. The core decides what is said and when; this only hears and speaks.

use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use memnox_desktop_voice::{
    held_speed, Chimes, Cue, Ear, EarEvent, FarEnd, Hearing, Level, Speaking, SystemVoice,
    Voice as Kokoro, VoiceModels, SYSTEM_VOICE, USUAL_SPEED, VOICES,
};
use serde::Serialize;
use tauri::ipc::Channel;
use tauri::{AppHandle, Emitter};

/// The models and the loaded engines, each loaded on first use since loading takes seconds.
pub struct Voice {
    models: VoiceModels,
    hearing: Mutex<Option<Arc<Hearing>>>,
    /// The voice that speaks, and whether it is Kokoro, so a system voice standing in is replaced once Kokoro is in.
    speaking: Mutex<Option<(Arc<Speaking>, bool)>>,
    /// The names hinted to the recognizer, learnt from the daemon each listen.
    hints: Mutex<Vec<String>>,
    /// What the speakers play, for the echo canceller, and the person's switch for it.
    far: FarEnd,
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
            hints: Mutex::new(Vec::new()),
            far: FarEnd::default(),
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

    /// The voice the person chose: a Kokoro id or the computer's own, None for the Mac's default.
    fn choice(&self) -> Option<String> {
        let kept = std::fs::read_to_string(&self.chosen).ok()?;
        let id = kept.trim();
        (id == SYSTEM_VOICE || VOICES.iter().any(|(each, _)| *each == id)).then(|| id.to_string())
    }

    /// Where the speed is kept, beside the chosen voice.
    fn speed_file(&self) -> PathBuf {
        self.chosen.with_file_name("voice-speed.txt")
    }

    /// The speed the person chose, the Mac's unhurried pace when none was.
    fn speed(&self) -> f32 {
        std::fs::read_to_string(self.speed_file())
            .ok()
            .and_then(|kept| kept.trim().parse::<f32>().ok())
            .map(held_speed)
            .unwrap_or(USUAL_SPEED)
    }

    fn hearing(&self) -> Result<Arc<Hearing>, String> {
        let mut loaded = self.hearing.lock().map_err(|_| "the voice failed")?;
        if let Some(hearing) = loaded.as_ref() {
            return Ok(hearing.clone());
        }
        let hints = self
            .hints
            .lock()
            .map(|hints| hints.clone())
            .unwrap_or_default();
        let hearing = Arc::new(Hearing::with_hints(self.installed()?, &hints)?);
        *loaded = Some(hearing.clone());
        Ok(hearing)
    }

    /// Kokoro in the chosen voice once it is in; the computer's own voice when chosen, until Kokoro is in,
    /// or when Kokoro will not load, so the island is never silent while the download runs.
    fn speaking(&self) -> Result<Arc<Speaking>, String> {
        let mut loaded = self.speaking.lock().map_err(|_| "the voice failed")?;
        let choice = self.choice();
        let wants_kokoro =
            choice.as_deref() != Some(SYSTEM_VOICE) && self.models.kokoro_installed();
        if let Some((speaking, kokoro)) = loaded.as_ref() {
            // A stand in is kept only until Kokoro is in; a chosen system voice is kept for good.
            if *kokoro || !wants_kokoro {
                return Ok(speaking.clone());
            }
        }
        let speed = self.speed();
        let kokoro = wants_kokoro
            .then(|| Kokoro::new(&self.models, choice.as_deref(), speed))
            .and_then(Result::ok);
        let is_kokoro = kokoro.is_some();
        let speaking = Arc::new(match kokoro {
            Some(voice) => Speaking::start(voice, self.playing.clone(), self.far.clone()),
            None if SystemVoice::available() => Speaking::start(
                SystemVoice::new(speed),
                self.playing.clone(),
                self.far.clone(),
            ),
            None => return Err("the voice is not installed yet".into()),
        });
        if let Some((old, _)) = loaded.replace((speaking.clone(), is_kokoro)) {
            old.stop();
        }
        Ok(speaking)
    }

    /// Loads Parakeet and Kokoro on a thread of their own at launch and after an install, as the Mac
    /// prefetches its recognizer, so the first turn does not wait seconds for them.
    pub fn warm_up(self: &Arc<Self>) {
        let voice = self.clone();
        std::thread::spawn(move || {
            if voice.models.installed() {
                let _ = voice.hearing();
            }
            let _ = voice.speaking();
        });
    }

    /// Drops the loaded voice so the next sentence loads it again with a new voice or speed.
    fn reload_speaking(&self) {
        if let Ok(mut loaded) = self.speaking.lock() {
            // The old voice is silenced first, since a sentence it is still saying would talk over the new one.
            if let Some((old, _)) = loaded.take() {
                old.stop();
            }
        }
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
    let warming = voice.inner().clone();
    let installed = tauri::async_runtime::spawn_blocking(move || {
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
    .map_err(|error| format!("the voice could not be installed: {error}"));
    if installed.is_ok() {
        warming.warm_up();
    }
    installed
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
        let ear = Ear::open(
            hearing,
            voice.playing.clone(),
            voice.far.clone(),
            partials,
            move |event| {
                let _ = events.send(event.into());
            },
        )?;
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
        .and_then(|speaking| speaking.as_ref().map(|(speaking, _)| speaking.clone()))
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

/// The voices on offer, the computer's own first when it has one as the Mac lists its own, then the
/// Kokoro ids; the one chosen, the Mac's default when none was; and the speed.
#[derive(Serialize)]
pub struct VoiceChoice {
    voices: Vec<&'static str>,
    chosen: Option<String>,
    speed: f32,
}

#[tauri::command]
pub fn voice_choice(voice: tauri::State<'_, Arc<Voice>>) -> VoiceChoice {
    let system = SystemVoice::available().then_some(SYSTEM_VOICE);
    VoiceChoice {
        voices: system
            .into_iter()
            .chain(VOICES.iter().map(|(id, _)| *id))
            .collect(),
        chosen: voice.choice(),
        speed: voice.speed(),
    }
}

/// Keeps the chosen voice and lets the next sentence load it; an id not on offer is refused.
#[tauri::command]
pub fn choose_voice(voice: tauri::State<'_, Arc<Voice>>, id: String) -> Result<(), String> {
    if id != SYSTEM_VOICE && !VOICES.iter().any(|(each, _)| *each == id) {
        return Err(format!("{id} is not a voice on offer"));
    }
    keep(&voice.chosen, &id)?;
    voice.reload_speaking();
    Ok(())
}

/// Keeps the speed, held between half speed and normal, and lets the next sentence speak at it.
#[tauri::command]
pub fn set_voice_speed(voice: tauri::State<'_, Arc<Voice>>, speed: f32) -> Result<(), String> {
    keep(&voice.speed_file(), &held_speed(speed).to_string())?;
    voice.reload_speaking();
    Ok(())
}

/// Turns the echo canceller on or off, off for a headset; an ear open now follows at once.
#[tauri::command]
pub fn echo_cancel(voice: tauri::State<'_, Arc<Voice>>, on: bool) {
    voice.far.set_cancelling(on);
}

/// The names this machine uses, hinted to Parakeet the next time it loads when the model takes hints.
#[tauri::command]
pub fn ear_hints(voice: tauri::State<'_, Arc<Voice>>, names: Vec<String>) {
    let Ok(mut hints) = voice.hints.lock() else {
        return;
    };
    if *hints == names {
        return;
    }
    *hints = names;
    // An open ear keeps its own recognizer; the next open loads one with the new names.
    if let Ok(mut hearing) = voice.hearing.lock() {
        *hearing = None;
    }
}

fn keep(file: &std::path::Path, value: &str) -> Result<(), String> {
    if let Some(dir) = file.parent() {
        std::fs::create_dir_all(dir).map_err(|error| error.to_string())?;
    }
    std::fs::write(file, value).map_err(|error| error.to_string())
}
