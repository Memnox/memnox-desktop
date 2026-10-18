import { ASK_INTENT, DAEMON_EVENT, type DaemonEvent } from '@memnox/core/wire';
import { awaitsAnswer, isSaid, isShownOnly } from '../domain/announcing';
import type { Cue } from '../domain/chimes';
import { correctedWords, type WordCorrection } from '../domain/corrections';
import { backspacesFor, cleanedDictation, dictationFamily, familyStyle, fitted, liveDictation, liveRevision, replaced, type DictationWord } from '../domain/dictation-text';
import { chosenHints, FIRST_RECOGNIZER_HINTS } from '../domain/recognizer-hints';
import { GUESS_AFTER_PAUSE_MS, mayGuess } from '../domain/turn-taking';
import { withoutEchoRuns } from '../domain/echo';
import { PhoneConversation, type PhoneExchange } from '../domain/phone-conversation';
import { quietHere } from '../domain/quiet';
import { DictationKey, HoldKeys, type KeyReport } from '../domain/voice-keys';
import { afterWakeWord } from '../domain/wake-word';
import { WakeRest } from '../domain/wake-lines';
import { DictationPolish, EDIT_PATIENCE_MS } from './dictation-polish';
import { hear, type Heard } from './hearing';
import { ECHO_LINGERS_MS, type Mouth } from './mouth';
import type { Chimes } from './ports/chimes';
import type { Ear } from './ports/ear';
import type { Focus, Typist } from './ports/typist';
import type { Talking, Timer } from './talking';
import { TalkOverWatch } from './talk-over-watch';
import type { VoicePreferences } from './voice-preferences';

/** What the island shows of a turn of the person's own, beyond what `Talking` says of the reply. */
export interface VoiceTurnsState {
  /** A turn is under way, said or listened to, which opens the island on the orb. */
  readonly active: boolean;
  /** The microphone is open for the person, so the caret breathes. */
  readonly listening: boolean;
  /** Their words as they say them, while live words are on. */
  readonly live: string;
  /** Control and Alt are held, so the island says it is taking down a rule. */
  readonly ruling: boolean;
  /** What to say while dictating, undefined otherwise, so dictating never looks like talking to Memnox. */
  readonly dictating: string | undefined;
  /** Why the microphone could not be used, in words, until the next turn. */
  readonly problem: string | undefined;
  /** A paired phone's turn mirrored here without a sound, until a moment after it ends. */
  readonly phone: PhoneExchange | undefined;
  /** What the orb is doing when it is neither listening nor answering, as the Mac's "Testing my voice". */
  readonly caption: string | undefined;
}

export const IDLE_TURNS: VoiceTurnsState = { active: false, listening: false, live: '', ruling: false, dictating: undefined, problem: undefined, phone: undefined, caption: undefined };

/** The turn timings the Mac's `AppDelegate` keeps, in milliseconds. */
export const TURN_TIMING = {
  /** How long it waits for a first word after the orb opens. */
  firstWordMs: 10_000,
  /** How long the microphone stays open for a follow up after an answer, long enough to think one up. */
  followUpMs: 15_000,
  /** How long it waits for the rest when the brain thought they stopped mid thought. */
  restOfThoughtMs: 6_000,
  /** A request this long already says what to do, so a hold on it waits only a breath for more. */
  briefRestMs: 2_500,
  longRequestWords: 8,
  /** How long a key may be up before listening ends, enough for the last syllable to reach the recognizer. */
  releaseTailMs: 400,
  /** How often the person talking over the voice is looked for, quick so a cut in stops it at once. */
  talkOverLookMs: 120,
  /** The longest a cut in sentence is waited for once the voice stopped. */
  cutInWaitMs: 8_000,
  /** How long a phone's finished turn stays on the island. */
  phoneTurnForMs: 8_000,
  /** Long enough to fix a word just written, short enough that the field is still the same text. */
  correctionWatchMs: 20_000,
  /** Away this long, behind a locked screen, is long enough for something to have happened worth telling. */
  awayLongEnoughMs: 10 * 60 * 1_000,
} as const;

/** Said when the microphone cannot be opened, since a silent orb that cannot hear looks like one not listening. */
export const CANNOT_HEAR = 'I cannot hear you yet. Check that a microphone is connected and that Memnox may use it, then ask me again.';
/** Said from the launcher's Say a rule, which teaches the keys rather than listening at once. */
export const RULE_HOW = 'Hold Control and Alt, say the rule, then let go. I will ask where it should hold.';
export const RULE_KEYS_UNSEEN = 'This desktop does not let me see the rule keys, so I cannot take a rule down here yet.';
/** The voice test, apart from listening and the daemon. */
export const VOICE_TEST = 'This is Memnox. If you can hear me, my voice works.';
/** Shown on the orb while the voice test plays, as the Mac's. */
export const VOICE_TEST_CAPTION = 'Testing my voice';
/** Shown on the orb while their brain tells them what happened while they were away. */
export const CATCHING_UP_CAPTION = 'Catching up';
const DICTATION_HINT = 'Speak, and it types where your cursor is';
const SELECTION_HINT = 'Say what to do with the selection';

export interface VoiceTurnsParts {
  readonly talking: Talking;
  readonly mouth: Mouth;
  readonly ear: Ear;
  readonly preferences: VoicePreferences;
  readonly timer: Timer;
  readonly chimes?: Chimes;
  readonly typist?: Typist;
  readonly polish?: DictationPolish;
  /** Whether the voice's models are on this computer, without which nothing can be heard. */
  readonly ready?: () => boolean;
  /** The person's own spellings and spoken shortcuts, for dictation. */
  readonly dictionary?: () => { spellings: readonly string[]; replacements: readonly DictationWord[] };
  /** Each dictation as it went, for the Dictation page's history. */
  readonly dictated?: (entry: { readonly heard: string; readonly written: string; readonly app: string | undefined }) => void;
  /** Words the person fixed after dictating, so the dictionary writes them their way next time. */
  readonly corrected?: (corrections: readonly WordCorrection[]) => void;
  /** The names to hint to the recognizer, learnt from the daemon each listen. */
  readonly hints?: (names: readonly string[]) => void;
  readonly now?: () => number;
}

/**
 * The turns the voice takes, one at a time, ported from what the Mac's `AppDelegate` does around its
 * `Conversation`: talk from anywhere and follow ups, talking over the voice, saying its name, saying a
 * rule with Control and Alt held, dictating with right Alt, and what waits on the person said and then
 * listened for. What the person said always goes whole to `ask`; nothing here acts on a word.
 */
export class VoiceTurns {
  readonly dictationKey: DictationKey;
  readonly holdKeys: HoldKeys;
  private current: VoiceTurnsState = IDLE_TURNS;
  private readonly listeners = new Set<() => void>();
  private tail: Promise<void> = Promise.resolve();
  private turns = 0;
  private phoneHolds = false;
  /** Ends the listen under way early, as a tap or a held key does. */
  private cutListen: (() => void) | undefined;
  private dictationReleased: (() => void) | undefined;
  private ruleReleased: (() => void) | undefined;
  private waking = false;
  private wakeEar: Promise<void> | undefined;
  private readonly wakeRest = new WakeRest();
  private readonly phoneTurns = new PhoneConversation();
  private phoneEnd: (() => void) | undefined;
  private readonly now: () => number;
  /** When the screen locked, so coming back after long enough is caught up on. */
  private awaySince: number | undefined;

  constructor(private readonly parts: VoiceTurnsParts) {
    this.now = parts.now ?? Date.now;
    this.dictationKey = new DictationKey(parts.timer, this.now);
    this.holdKeys = new HoldKeys(parts.timer);
    this.dictationKey.began = () => this.dictationHeld();
    this.dictationKey.ended = () => {
      this.dictationReleased?.();
      this.dictationReleased = undefined;
    };
    this.holdKeys.began = () => this.ruleHeld();
    this.holdKeys.ended = () => {
      this.update({ ruling: false });
      this.ruleReleased?.();
      this.ruleReleased = undefined;
    };
    this.dictationKey.enabled = parts.preferences.choices.dictation;
    this.dictationKey.key = parts.preferences.dictationKey;
    parts.preferences.observe(() => {
      this.dictationKey.enabled = parts.preferences.choices.dictation;
      this.dictationKey.key = parts.preferences.dictationKey;
      if (!parts.preferences.choices.liveWords && this.current.live !== '') this.update({ live: '' });
      if (parts.preferences.choices.wake) this.listenForName();
      else void this.stopWake();
    });
  }

  get state(): VoiceTurnsState {
    return this.current;
  }

  observe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** What the platform saw of the keyboard, for the dictation key and the rule keys. */
  keys(report: KeyReport): void {
    // Read each time, since Settings picks the key in a window of its own.
    this.dictationKey.key = this.parts.preferences.dictationKey;
    this.dictationKey.saw(report);
    this.holdKeys.saw(report);
  }

  /** What the platform read of the keyboard layout, which picks the dictation key nobody chose. */
  layout(hasAltGr: boolean): void {
    this.parts.preferences.layoutHasAltGr(hasAltGr);
  }

  /** The talk key, the menu and the resting orb end here: open the orb and listen, or stop what is said. */
  talk(): void {
    if (this.current.active) {
      this.cutListen?.();
      void this.parts.talking.interrupt();
      return;
    }
    this.enqueue(() => this.converse());
  }

  /** A tap on the island while talking ends the turn; otherwise it talks. */
  tap(): void {
    this.talk();
  }

  /** Starts listening for its name, when the person turned it on and nothing else is going on. */
  listenForName(): void {
    if (this.turns > 0 || this.phoneHolds || !this.parts.preferences.choices.wake || this.waking || !this.ready()) return;
    this.waking = true;
    void this.wakeRound();
  }

  /**
   * Something from the live feed: said in its turn and listened to for the answer when it waits on the
   * person, shown only when a phone holds the voice, and left to `Talking` when it is not said at all.
   */
  arrived(event: DaemonEvent): void {
    const { talking, preferences } = this.parts;
    if (event.voiceOn !== undefined) {
      this.phoneHolds = event.voiceOn.holding;
      if (this.phoneHolds) void this.stopWake();
      else this.listenForName();
    }
    if (event.phoneTurn !== undefined) this.showPhone(event.phoneTurn);
    // A drive grant, a phone's turn and the voice moving are shown rather than said, so they never wait behind speech.
    if (isShownOnly(event) || event.kind === DAEMON_EVENT.PROPOSAL || event.kind === DAEMON_EVENT.SETTLED || quietHere(event, this.phoneHolds)) {
      void talking.handle(event);
      return;
    }
    if (!isSaid(event, preferences.choices.speakUp, this.phoneHolds)) return;
    this.enqueue(async () => {
      this.update({ active: true, problem: undefined });
      const cutIn = await this.overVoice(() => talking.handle(event));
      // Only something waiting on their answer keeps the microphone open; news is said and the orb goes back.
      const live = event.kind !== DAEMON_EVENT.HELD || talking.stillAsking(event.subject);
      if (cutIn !== undefined || (awaitsAnswer(event, this.phoneHolds) && live)) await this.converse(cutIn ?? '');
      else this.update({ active: false, live: '' });
    });
  }

  /** A phone's turn as it stands: shown like the person's own, with no sound, and put away a moment after it ends. */
  private showPhone(turn: NonNullable<DaemonEvent['phoneTurn']>): void {
    const shown = this.phoneTurns.take(turn, this.now());
    if (shown === undefined) return;
    this.phoneEnd?.();
    this.phoneEnd = undefined;
    this.update({ phone: shown });
    if (shown.exchange.answeredAt === undefined) return;
    this.phoneEnd = this.parts.timer(TURN_TIMING.phoneTurnForMs, () => {
      if (this.current.phone?.id === shown.id) this.update({ phone: undefined });
    });
  }

  /** Say a rule from the launcher: how to hold the keys, or why they cannot be seen here. */
  sayRule(keysSeen = true): void {
    this.sayInTurn(keysSeen ? RULE_HOW : RULE_KEYS_UNSEEN);
  }

  /** Say something: checks the voice on its own, apart from listening and the daemon. */
  saySomething(): void {
    this.sayInTurn(VOICE_TEST, VOICE_TEST_CAPTION);
  }

  /** Says one line in its turn, as Settings' voice test and a voice change do, so the mute and the echo memory hold. */
  sayInTurn(line: string, caption?: string): void {
    this.enqueue(async () => {
      this.update({ active: true, caption });
      await this.say(line);
      this.update({ active: false, caption: undefined });
    });
  }

  /** The screen locked, which is the person leaving. */
  locked(): void {
    this.awaySince ??= this.now();
  }

  /**
   * The screen unlocked: after ten minutes away, with Catch me up on, their brain tells them what waits on
   * them, and the microphone stays open for an answer; when nothing does, the orb goes back unheard.
   */
  unlocked(): void {
    const since = this.awaySince;
    this.awaySince = undefined;
    if (since === undefined || this.now() - since < TURN_TIMING.awayLongEnoughMs || !this.parts.preferences.choices.catchUp) return;
    this.enqueue(async () => {
      this.update({ active: true, caption: CATCHING_UP_CAPTION, problem: undefined });
      let caughtUp = false;
      const cutIn = await this.overVoice(async () => {
        caughtUp = await this.parts.talking.welcomeBack(since);
      });
      this.update({ caption: undefined });
      if (cutIn !== undefined || caughtUp) await this.converse(cutIn ?? '');
      else this.update({ active: false });
    });
  }

  private ready(): boolean {
    return this.parts.ready?.() ?? true;
  }

  private chime(cue: Cue): void {
    if (this.parts.preferences.choices.chimes) this.parts.chimes?.play(cue);
  }

  private async say(line: string): Promise<void> {
    this.parts.mouth.queue(line);
    await this.parts.mouth.drained();
  }

  /** One turn after another, and the name is not listened for while any runs, so it never wakes on its own voice. */
  private enqueue(work: () => Promise<void>): void {
    this.turns += 1;
    const stopped = this.stopWake();
    this.tail = this.tail
      .then(() => stopped)
      .then(work)
      .catch(() => undefined)
      .finally(() => {
        this.turns -= 1;
        this.listenForName();
      });
  }

  /** Open the orb and listen, answer, and listen again for a follow up until the brain ends it. */
  private async converse(opening = '', greet = false, openingIntent?: typeof ASK_INTENT.RULE): Promise<void> {
    const { talking } = this.parts;
    this.update({ active: true, problem: undefined });
    if (!this.ready()) {
      this.update({ active: false, problem: 'The voice is not installed yet' });
      return;
    }
    // Called by name alone, it answers the way a person would before they ask.
    if (greet) await this.say(talking.answerToCall());
    let next: string | undefined = opening === '' ? undefined : opening;
    let intent = opening === '' ? undefined : openingIntent;
    let held: string | undefined;
    let waiting: number = TURN_TIMING.firstWordMs;
    // Started while they are still talking, so the answer does not wait on a cold start.
    void talking.warm();
    // Learnt alongside rather than before, so the microphone is heard from the first word.
    void this.learnNames();
    this.chime('listening');
    for (;;) {
      let heard: string | undefined;
      if (next !== undefined) {
        heard = next;
      } else {
        const result = await this.listen({ waitMs: waiting, guesses: true });
        if (result.kind === 'failed') {
          await this.cannotHear(result.why);
          break;
        }
        heard = result.kind === 'words' ? this.ownWordsOnly(result.words) : undefined;
      }
      const finished = heard === undefined && held !== undefined;
      const said = heard ?? held;
      if (said === undefined) break;
      this.update({ live: '' });
      next = await this.overVoice(() => talking.heard(said, finished || intent !== undefined, intent === undefined ? {} : { intent }));
      intent = undefined;
      // They carried on before any answer was said, so it is one question in two breaths, not two.
      if (next !== undefined && !talking.spokeThisTurn) next = `${said} ${next}`;
      const holding = talking.takeHold() && !talking.spokeThisTurn;
      // Held once on words already marked whole is a brain ignoring the note, and asking again would loop.
      held = holding && !finished ? said : undefined;
      if (next === undefined && talking.takeEnd()) break;
      waiting = holding ? restOfThought(said) : TURN_TIMING.followUpMs;
    }
    this.chime('closed');
    this.update({ active: false, listening: false, live: '' });
  }

  /** Said, since a silent orb that cannot hear looks exactly like one that is not listening. */
  private async cannotHear(why: string): Promise<void> {
    this.update({ problem: why });
    this.chime('failed');
    await this.say(CANNOT_HEAR);
  }

  /** One listen for the person, with their words shown as they come while live words are on. */
  private async listen(options: { waitMs: number; holding?: { released: Promise<void>; tailMs: number }; guesses?: boolean }): Promise<Heard> {
    const { talking, preferences, ear, timer } = this.parts;
    const cut = new Promise<void>((resolve) => {
      this.cutListen = resolve;
    });
    this.update({ listening: true, live: '' });
    talking.listening(true);
    // At a short pause the words so far are sent as a guess, so the answer can start before they finish.
    let guessed = '';
    let pause: () => void = () => undefined;
    const paused = (soFar: string) => {
      pause();
      if (options.guesses !== true || options.holding !== undefined) return;
      const changed = this.now();
      pause = timer(GUESS_AFTER_PAUSE_MS, () => {
        if (soFar === guessed || !mayGuess(soFar, this.now() - changed)) return;
        guessed = soFar;
        const mine = this.ownWordsOnly(soFar);
        if (mine !== undefined) void talking.guess(mine);
      });
    };
    try {
      return await hear(ear, timer, {
        waitMs: options.waitMs,
        ...(options.holding === undefined ? {} : { holding: options.holding }),
        cut,
        onWords: (soFar) => {
          if (preferences.choices.liveWords) this.update({ live: soFar });
          paused(soFar);
        },
        onLevel: (level) => this.onLevel?.(level),
      });
    } finally {
      pause();
      this.cutListen = undefined;
      talking.listening(false);
      this.update({ listening: false });
      this.onLevel?.(0);
    }
  }

  /** How loud the person is while they are heard, for the orb; the island sets it. */
  onLevel: ((level: number) => void) | undefined;

  /** What was heard less the tail of its own voice still in the room as the microphone opened. */
  private ownWordsOnly(heard: string): string | undefined {
    const mine = withoutEchoRuns(heard, this.parts.mouth.spoken(ECHO_LINGERS_MS));
    return /\p{L}/u.test(mine) ? mine : undefined;
  }

  /**
   * Anything spoken, with an ear open the whole time: the moment the person talks over it the voice
   * stops and the brain stops, and their whole sentence is returned once they pause.
   */
  private async overVoice(speaking: () => Promise<void>): Promise<string | undefined> {
    const { preferences, ear, mouth, talking, timer } = this.parts;
    if (!preferences.choices.talkOver || !this.ready()) {
      await speaking();
      return undefined;
    }
    let cutting: Promise<void> | undefined;
    const watch = new TalkOverWatch({
      spoken: () => mouth.spoken(ECHO_LINGERS_MS),
      speaking: () => mouth.speaking,
      hush: () => mouth.hush(),
      carryOn: () => mouth.carryOn(),
      cutIn: () => {
        cutting = talking.interrupt();
      },
      now: this.now,
    });
    let decided: ((words: string | undefined) => void) | undefined;
    const handed = new Promise<string | undefined>((resolve) => {
      decided = resolve;
    });
    let looking: () => void = () => undefined;
    const lookAgain = () => {
      looking = timer(TURN_TIMING.talkOverLookMs, () => {
        const words = watch.look();
        if (words !== undefined) decided?.(words === '' ? undefined : words);
        else lookAgain();
      });
    };
    let opened = false;
    try {
      await ear.open(
        (event) => {
          if (event.kind === 'level') {
            watch.level(event.heard, event.playing);
            if (watch.barged) this.onLevel?.(event.heard);
          } else if (event.kind === 'words') watch.heard(event.text, event.final);
          else if (event.kind === 'closed') decided?.(undefined);
        },
        { partials: true },
      );
      opened = true;
      lookAgain();
    } catch {
      // Without a microphone the voice is only heard out, as with talking over turned off.
    }
    await speaking();
    // The old answer's cancel must reach the daemon before the next question does, or it cancels that one.
    await cutting;
    let words: string | undefined;
    if (opened && watch.barged) {
      this.update({ listening: true });
      let cancelWait: () => void = () => undefined;
      const late = new Promise<undefined>((resolve) => {
        cancelWait = timer(TURN_TIMING.cutInWaitMs, () => resolve(undefined));
      });
      words = await Promise.race([handed, late]);
      cancelWait();
      this.update({ listening: false });
    }
    looking();
    watch.end();
    if (opened) await ear.close().catch(() => undefined);
    return words;
  }

  /** Control and Alt held: whatever was going on gives way, and the rule is listened to for as long as they are down. */
  private ruleHeld(): void {
    this.update({ ruling: true });
    if (this.current.active) {
      this.cutListen?.();
      void this.parts.talking.interrupt();
    }
    const released = new Promise<void>((resolve) => {
      this.ruleReleased = resolve;
    });
    this.enqueue(() => this.converseRule(released));
  }

  /** A rule, heard until the keys are let go and then sent with the rule intent; the brain asks where it holds. */
  private async converseRule(released: Promise<void>): Promise<void> {
    // Let go before this turn began: nothing was said for it, so there is nothing to take down.
    if (!this.holdKeys.holding) {
      this.update({ ruling: false });
      return;
    }
    if (!this.ready()) {
      this.update({ ruling: false, problem: 'The voice is not installed yet' });
      return;
    }
    this.update({ active: true, ruling: true, problem: undefined });
    void this.parts.talking.warm();
    this.chime('listening');
    const result = await this.listen({ waitMs: 0, holding: { released, tailMs: TURN_TIMING.releaseTailMs } });
    this.update({ ruling: false });
    if (result.kind === 'failed') {
      await this.cannotHear(result.why);
      this.update({ active: false });
      return;
    }
    const said = result.kind === 'words' ? this.ownWordsOnly(result.words) : undefined;
    if (said === undefined) {
      this.chime('closed');
      this.update({ active: false, live: '' });
      return;
    }
    this.update({ live: '' });
    const cutIn = await this.overVoice(() => this.parts.talking.heard(said, true, { intent: ASK_INTENT.RULE }));
    // The place can be said as well as picked, so the microphone stays open for the answer.
    await this.converse(cutIn ?? '');
  }

  /** Right Alt held or tapped twice: what is said is written where the cursor is. */
  private dictationHeld(): void {
    if (this.current.active || this.parts.typist === undefined) {
      this.dictationKey.stop();
      return;
    }
    const released = new Promise<void>((resolve) => {
      this.dictationReleased = resolve;
    });
    // Started while they are still talking, so the polish skips Claude Code's cold start.
    if (this.parts.preferences.choices.polish) this.parts.polish?.warm();
    this.enqueue(() => this.dictate(released));
  }

  private async dictate(released: Promise<void>): Promise<void> {
    const typist = this.parts.typist;
    // Let go before this turn began: nothing was said for it.
    if (typist === undefined || !this.dictationKey.active) return;
    if (!this.ready()) {
      this.dictationKey.stop();
      this.update({ problem: 'The voice is not installed yet' });
      return;
    }
    const focus = await typist.focus().catch((): Focus => ({ secure: false }));
    if (focus.secure) {
      // A password field is never written into by voice, whatever was said.
      this.dictationKey.stop();
      this.chime('failed');
      return;
    }
    const selection = focus.selection === undefined || focus.selection === '' ? undefined : focus.selection;
    this.update({ active: true, dictating: selection === undefined ? DICTATION_HINT : SELECTION_HINT, problem: undefined });
    this.chime('listening');
    const live = selection === undefined && this.parts.preferences.choices.typesLive ? new LiveTyping(typist) : undefined;
    const dictionary = this.parts.dictionary?.() ?? { spellings: [], replacements: [] };
    const watching = this.observeLive(live, dictionary);
    const result = await this.listen({ waitMs: 0, holding: { released, tailMs: TURN_TIMING.releaseTailMs } });
    watching();
    this.dictationKey.stop();
    const said = result.kind === 'words' && /\p{L}/u.test(result.words) ? result.words : undefined;
    if (said === undefined) {
      // Words typed live and then heard as nothing are taken back, so a cough leaves no trace.
      await live?.show('').catch(() => undefined);
      this.update({ active: false, dictating: undefined, live: '' });
      if (result.kind === 'failed') await this.cannotHear(result.why);
      else this.chime('closed');
      return;
    }
    const family = dictationFamily(focus.app, focus.title);
    const text = await this.dictationText(said, family, selection, dictionary);
    this.update({ active: false, dictating: undefined, live: '' });
    if (text === undefined) {
      // Editing a selection needs the model, and without its answer the selection is left untouched.
      this.chime('failed');
      return;
    }
    // Fitted to what is around the cursor, so it is spaced and capitalised as the sentence it lands in.
    const written = selection === undefined ? fitted(text, focus.before, focus.after) : text;
    const landed = await this.put(written, focus, live);
    this.parts.dictated?.({ heard: said, written, app: focus.app });
    if (!landed) {
      this.chime('failed');
      return;
    }
    this.watchForCorrections(written, focus);
  }

  /**
   * Reads the field again a while later, and what the person changed in the words just written is learned:
   * the dictionary writes it their way next time, and the recognizer hears it better. Only when the text
   * around what was written is still exactly as it was, so a different field never teaches anything.
   */
  private watchForCorrections(written: string, focus: Focus): void {
    const typist = this.parts.typist;
    if (typist === undefined || focus.value === undefined || focus.caret === undefined) return;
    const prefix = focus.value.slice(0, focus.caret);
    const suffix = focus.value.slice(focus.selectionEnd ?? focus.caret);
    this.parts.timer(TURN_TIMING.correctionWatchMs, () => {
      void typist
        .focus()
        .then((now) => {
          const value = now.value;
          if (now.app !== focus.app || value === undefined || !value.startsWith(prefix) || !value.endsWith(suffix) || value.length < prefix.length + suffix.length) return;
          const edited = value.slice(prefix.length, value.length - suffix.length).trim();
          const typed = written.trim();
          if (edited === typed || edited === '') return;
          const corrections = correctedWords(typed, edited);
          if (corrections.length === 0) return;
          this.parts.corrected?.(corrections);
          void this.parts.talking.learn(typed, edited);
        })
        .catch(() => undefined);
    });
  }

  /** The agents, CLIs and servers on this machine, so the recognizer hears "Railway" and not "right away". */
  private async learnNames(): Promise<void> {
    if (this.parts.hints === undefined) return;
    const words = await this.parts.talking.vocabulary();
    this.parts.hints(chosenHints([FIRST_RECOGNIZER_HINTS, words]));
  }

  /** Types the words live as they come, while the key is held, when the person chose live typing. */
  private observeLive(live: LiveTyping | undefined, dictionary: { spellings: readonly string[]; replacements: readonly DictationWord[] }): () => void {
    if (live === undefined) return () => undefined;
    return this.observe(() => {
      const heard = this.current.live;
      if (heard !== '') void live.show(liveDictation(heard, false, { dictionary: dictionary.spellings, replacements: dictionary.replacements })).catch(() => undefined);
    });
  }

  /** For a selection, the model's edit of it or nothing; otherwise this computer's cleanup, or the polish when it answers in time. */
  private async dictationText(
    said: string,
    family: ReturnType<typeof dictationFamily>,
    selection: string | undefined,
    dictionary: { spellings: readonly string[]; replacements: readonly DictationWord[] },
  ): Promise<string | undefined> {
    const { polish, preferences } = this.parts;
    const polishes = preferences.choices.polish && polish !== undefined;
    if (selection !== undefined) {
      return polishes ? polish.polish(said, family, dictionary.spellings, selection, EDIT_PATIENCE_MS) : undefined;
    }
    const local = cleanedDictation(said, { dictionary: dictionary.spellings, replacements: dictionary.replacements, style: familyStyle(family) });
    if (!polishes) return local;
    const polished = await polish.polish(said, family, dictionary.spellings);
    // The model writes their words; their own replacements still decide what a phrase becomes.
    return polished === undefined ? local : replaced(polished, dictionary.replacements);
  }

  /** The finished words where the cursor is, over what was typed live; on the clipboard when the app left the front. */
  private async put(written: string, focus: Focus, live: LiveTyping | undefined): Promise<boolean> {
    const typist = this.parts.typist;
    if (typist === undefined) return false;
    const front = await typist.focus().catch((): Focus => ({ secure: false }));
    if (front.app !== focus.app) {
      // They moved to another app mid sentence, so the whole of it waits on the clipboard.
      await typist.copy(written).catch(() => undefined);
      return false;
    }
    try {
      if (live !== undefined) await live.show(written);
      else await typist.type(written);
      return true;
    } catch {
      await typist.copy(written).catch(() => undefined);
      return false;
    }
  }

  /** One round of listening for its name; a failing microphone backs off rather than spinning all day. */
  private async wakeRound(): Promise<void> {
    while (this.waking) {
      let called: string | undefined;
      let failed = false;
      const closed = new Promise<void>((resolve) => {
        this.wakeEar = this.parts.ear
          .open(
            (event) => {
              if (event.kind === 'words' && event.final && called === undefined) {
                const after = afterWakeWord(event.text, this.parts.mouth.spoken(ECHO_LINGERS_MS));
                if (after !== undefined) {
                  called = after;
                  resolve();
                }
              } else if (event.kind === 'closed') {
                failed = event.error !== undefined && event.error !== null;
                resolve();
              }
            },
            { partials: false },
          )
          .catch(() => {
            failed = true;
            resolve();
          });
      });
      await closed;
      if (called !== undefined) {
        const after = called;
        this.waking = false;
        await this.parts.ear.close().catch(() => undefined);
        this.enqueue(() => this.converse(after, after === ''));
        return;
      }
      if (!this.waking) return;
      const rest = this.wakeRest.after(failed);
      await new Promise<void>((resolve) => this.parts.timer(rest, resolve));
    }
  }

  private async stopWake(): Promise<void> {
    if (!this.waking) return;
    this.waking = false;
    await this.wakeEar;
    await this.parts.ear.close().catch(() => undefined);
  }

  private update(change: Partial<VoiceTurnsState>): void {
    const next = { ...this.current, ...change };
    if ((Object.keys(change) as (keyof VoiceTurnsState)[]).every((key) => next[key] === this.current[key])) return;
    this.current = next;
    for (const listener of this.listeners) listener();
  }
}

/** How long to wait for the rest when the brain held for it: a breath after a long request, longer after a short one. */
function restOfThought(said: string): number {
  return said.split(/\s+/).filter((word) => word !== '').length >= TURN_TIMING.longRequestWords ? TURN_TIMING.briefRestMs : TURN_TIMING.restOfThoughtMs;
}

/**
 * Words typed as they are said and revised in place: only the part that differs is taken back and
 * typed again, one change at a time so two never interleave. Ported from the Mac's `LiveTyping`.
 */
export class LiveTyping {
  private typed = '';
  private chain: Promise<void> = Promise.resolve();

  constructor(private readonly typist: Typist) {}

  get text(): string {
    return this.typed;
  }

  /** Rejects when the keys could not be sent, so the finished words can go to the clipboard instead. */
  show(wanted: string): Promise<void> {
    const step = this.chain.then(async () => {
      const change = liveRevision(this.typed, wanted);
      if (change.removed === '' && change.added === '') return;
      await this.typist.revise(backspacesFor(change.removed), change.added);
      this.typed = wanted;
    });
    this.chain = step.catch(() => undefined);
    return step;
  }
}
