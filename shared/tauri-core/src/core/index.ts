/** The core every desktop screen draws from: no DOM, no Tauri, only the daemon, the key and the voice through ports. */
export { HeldCalls, type HeldCallsOptions, type HeldOutcome, type HeldState } from './application/held-calls';
export { RequestIds } from './application/request-ids';
export { ProposalCards } from './application/proposal-cards';
export { NO_KEY_LINE, Signer, type Signing } from './application/signer';
export { Setup, type SetupState } from './application/setup';
export { VoiceSettings, type VoiceAgents } from './application/voice-settings';
export { ANSWER_WINDOW_MS, Talking, type Timer, type TalkingOptions, type TalkState } from './application/talking';
export { Wakefulness } from './application/wakefulness';
export type { ConfirmKey } from './application/ports/confirm-key';
export { DaemonClosed, requestOnce, type DaemonLink } from './application/ports/daemon-link';
export type { Power } from './application/ports/power';
export type { Runtime, RuntimeStep } from './application/ports/runtime';
export type { Speaker } from './application/ports/speaker';
export { consentReason, FROM_NOW_ON, THIS_COMPUTER, type HeldAnswer } from './domain/call-label';
export { agentColour, agentKind } from './domain/agent-colour';
export {
  countsDown,
  dwellFor,
  headerPastOrb,
  idleCountdown,
  isGrowing,
  isOpenMode,
  ISLAND,
  ISLAND_TIMING,
  ISLAND_WINDOW,
  islandSize,
  islandTitle,
  islandTop,
  orbSpot,
  RESTING,
  SATELLITE,
  settle,
  showsHeader,
  showsSatellites,
  STAND_IN_NOTCH,
  TILE,
  type IslandFacts,
  type IslandMode,
  type NotchGeometry,
  type OrbSpot,
  type Size,
} from './domain/island-layout';
export { finishedCard, type FinishedCard } from './domain/finished-card';
export { ELLIPSIS, middleCut } from './domain/middle-cut';
export { notchPath, notchRadius } from './domain/notch-shape';
export { settledLine, SETTLED_UNKNOWN } from './domain/settled-line';
export { atRest, cubicBezier, SHRINK, springConstants, springStep, SPRINGS, type Moving, type Spring } from './domain/spring';
export { EarlierAnswer } from './domain/earlier-answer';
export type { HeldCard } from './domain/held-card';
export { accountWarning, draftAudience, suggestedScope, typedAddresses, type ProposalCard } from './domain/proposal-card';
export { ANOTHER_KEY_LINE, type KeyStatus } from './domain/key-status';
export { isAtLeast, MINIMUM_RUNTIME, type RuntimeState } from './domain/runtime-state';
export { OrbMotion, orbFit, type OrbState, type OrbUniforms, type Reaction } from './domain/orb-motion';
export { WaitingCalls, type WaitingEntry } from './domain/waiting-calls';
export {
  avatarLetter,
  BRANDED_TOOLS,
  FALLBACK_LOOK,
  hasOwnMark,
  SHOWN_PEOPLE,
  shownPeople,
  SIGNED_IN_FOR_MS,
  signedInWords,
  signInLabel,
  signInLead,
  toolAsks,
  toolkitName,
  toolLook,
  toolPageHint,
  workFootnote,
  workLayout,
  workTitle,
  type ToolLook,
  type WorkLayout,
} from './domain/tool-brand';
export { agentInitial, agentLogo } from './domain/agent-logo';
export { Sessions, SESSIONS_REFRESH, type SessionsState } from './application/sessions';
export { AgentQuestions, type QuestionState } from './application/agent-questions';
export { CANNOT, cardSession, Displays, webLink, type DisplayOptions, type Presenter, type SummaryCard, type WalkCard } from './application/displays';
export { NO_TERMINAL_CONTROL, reasonOf, SessionFocus } from './application/session-focus';
export type { Shown, Terminals } from './application/ports/terminals';
export * from './domain/session-focus';
export { bestTab, isCertainTab } from './domain/tab-match';
export { agentInFront, isAgentProgram } from './domain/terminal-front';
export { HistoryKeeper, type HistoryStore, type TurnSource } from './application/history-keeper';
export { isActive, sessionStatus, statusLabel, statusTint, type SessionStatus } from './domain/session-status';
export {
  ago,
  badgeLabel,
  cardStatus,
  cardSubtitle,
  cardTitle,
  countsFor,
  currentAsk,
  detailPlace,
  diffLines,
  duration,
  excerptLines,
  fileName,
  folderOf,
  meaningful,
  onlyNetwork,
  readable,
  repositoryName,
  SEPARATOR,
  shortPath,
  stepLine,
  stepSymbol,
  stepTint,
  totals,
  traceStepName,
  viewContext,
  viewPlace,
  viewStatus,
  type DiffLine,
  type ExcerptLine,
  type StepSymbol,
} from './domain/session-text';
export { reactionTo } from './domain/reaction';
export {
  ask as askedExchange,
  currentExchange,
  exchangeDetail,
  historyDays,
  isAnswering,
  KEPT_EXCHANGES,
  matching,
  mentions,
  NO_HISTORY,
  parseHistory,
  type Exchange,
  type History,
  type HistoryDay,
} from './domain/history';
export { VoiceTurns, IDLE_TURNS, TURN_TIMING, CANNOT_HEAR, LiveTyping, type VoiceTurnsParts, type VoiceTurnsState } from './application/voice-turns';
export { VoicePreferences, VOICE_DEFAULTS, type VoiceChoices } from './application/voice-preferences';
export { Mouth, ECHO_LINGERS_MS, type Hushable } from './application/mouth';
export { DictationPolish } from './application/dictation-polish';
export { hear, type Heard, type HearOptions } from './application/hearing';
export { TalkOverWatch } from './application/talk-over-watch';
export type { Ear, EarEvent } from './application/ports/ear';
export type { Focus, Typist } from './application/ports/typist';
export type { PreferenceStore } from './application/ports/preference-store';
export type { AskOptions } from './application/talking';
export { afterWakeWord, nameAlone, withoutLeadingName, withoutTrailingName } from './domain/wake-word';
export { isBargeIn, mayBeCuttingIn, withoutEcho, withoutEchoRuns } from './domain/echo';
export { WakeLines, WakeRest } from './domain/wake-lines';
export { awaitsAnswer, isSaid, isShownOnly } from './domain/announcing';
export { cleanedDictation, cursorHints, dictationFamily, familyStyle, fitted, liveDictation, liveRevision, type DictationFamily, type DictationStyle, type DictationWord } from './domain/dictation-text';
export { DictationKey, HoldKeys, VOICE_KEY_TIMING, type KeyReport } from './domain/voice-keys';
export { endOfSpeechPause, joinedSpeech } from './domain/turn-taking';
export { clock as answerClock } from './domain/answer-clock';
