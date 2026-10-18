import type { VoiceAgentStatus } from '@memnox/core/wire';
import type { SettingsPage } from './settings-pages';
import { DONE, needs, WAITING, type StepState } from './step-state';

/** One setup step as the overview lists it: its title, where it stands, the page it lives on, and what to do. */
export interface OverviewStep {
  readonly title: string;
  readonly state: StepState;
  readonly page: SettingsPage;
  /** What to do next, or the reason it needs the person in place of the general line. */
  readonly hint: string;
}

/** Everything the checklist reads, gathered by the window from the daemon, Rust and the person's own settings. */
export interface SetupFacts {
  readonly name: StepState;
  readonly hear: StepState;
  readonly type: StepState;
  readonly see: StepState;
  readonly service: StepState;
  readonly serviceDetail: string;
  readonly key: StepState;
  readonly agents: StepState;
  readonly agentsDetail: string;
  readonly voice: StepState;
  readonly voiceDetail: string;
}

/** The eight steps in the Mac's order, "n of 8" counting the done ones. */
export function overviewSteps(facts: SetupFacts): readonly OverviewStep[] {
  return [
    step('Tell Memnox your name', facts.name, 'account', 'So it greets you and speaks to you by name.'),
    step('Let it hear you', facts.hear, 'permissions', 'The microphone, heard on this computer only.'),
    step('Let it type for you', facts.type, 'permissions', 'Type what you confirm into your agents, and read back that it landed.'),
    step('Let it see your screen', facts.see, 'permissions', 'Read the window you ask about, and check that what it sent landed.'),
    step('Start the Memnox service', facts.service, 'connection', facts.serviceDetail),
    step('Register your confirm key', facts.key, 'connection', 'Your approval signs anything outside a session’s repository.'),
    step('Choose who answers for you', facts.agents, 'voice', facts.agentsDetail),
    step('Pick a voice', facts.voice, 'voice', facts.voiceDetail),
  ];
}

function step(title: string, state: StepState, page: SettingsPage, general: string): OverviewStep {
  return { title, state, page, hint: state.kind === 'needs' ? state.why : general };
}

/** The first step still open, which the card offers with its own button. */
export function openStep(steps: readonly OverviewStep[]): OverviewStep | undefined {
  return steps.find((each) => each.state.kind !== 'done');
}

export function readyCount(steps: readonly OverviewStep[]): number {
  return steps.filter((each) => each.state.kind === 'done').length;
}

/** The name as a step: done once there is one. */
export function nameStep(name: string): StepState {
  return name.trim() === '' ? WAITING : DONE;
}

/** "Hi Sam" from "Sam Smith", or Memnox before a name is given. */
export function greeting(name: string): string {
  const first = name.trim().split(/\s+/)[0] ?? '';
  return first === '' ? 'Memnox' : `Hi ${first}`;
}

/** The first name alone, for "You're set, Sam." */
export function firstName(name: string): string | undefined {
  const first = name.trim().split(/\s+/)[0] ?? '';
  return first === '' ? undefined : first;
}

const NO_AGENT =
  'Memnox brings no model of its own, so it answers through an agent you already use. Install and sign in to one of Claude Code, Codex, Cursor, Hermes or OpenClaw, then check again. No API key needed';

/** The voice's agents as a step, as the Mac's `agentsState` decides it. */
export function agentsStep(found: readonly VoiceAgentStatus[]): StepState {
  const installed = found.filter((agent) => agent.installed);
  if (installed.length === 0) return needs(NO_AGENT);
  const chosen = found.find((agent) => agent.chosen);
  if (chosen?.works === true) return DONE;
  if (installed.every((agent) => agent.works === undefined)) return WAITING;
  if (installed.some((agent) => agent.works === true)) return needs('Choose the agent that answers for you');
  return needs('None of your agents answered. Fix one below, then check again');
}

/** What the step under the voice agents says: which one thinks, and whether it is kept to reading. */
export function agentsDetail(found: readonly VoiceAgentStatus[], checking: boolean): string {
  const chosen = found.find((agent) => agent.chosen);
  if (chosen === undefined) {
    return checking
      ? 'Asking each of your agents one question to see which answers.'
      : 'The agent you already use thinks for the voice, such as Claude Code, Codex, Cursor or Hermes, signed in with its own account. No API key needed.';
  }
  if (chosen.sealed) return `${chosen.label}, kept to reading, so it never edits a file or runs a command.`;
  return `${chosen.label} can run shell commands without asking, used because no agent kept to reading answered.`;
}

/** Where the natural voice stands on this computer: installed, on its way, or failed with why. */
export type VoiceInstall = { kind: 'idle' } | { kind: 'installing'; percent: number | undefined } | { kind: 'done' } | { kind: 'failed'; why: string };

/** The voice as a step: done once it is in; the system voice stands in until then, so idle only waits. */
export function voiceStep(install: VoiceInstall): StepState {
  switch (install.kind) {
    case 'done':
      return DONE;
    case 'failed':
      return needs(install.why);
    case 'installing':
    case 'idle':
      return WAITING;
  }
}

export function voiceDetail(install: VoiceInstall): string {
  switch (install.kind) {
    case 'done':
      return 'A natural voice, running on this computer.';
    case 'installing':
      return 'Fetching a more natural voice. Your computer’s own voice speaks until it arrives, so carry on with the rest.';
    case 'idle':
    case 'failed':
      return 'The voice installs itself the first time. Your computer’s own voice speaks until then.';
  }
}

/** The service as a step and its line, from the setup row's own state. */
export function serviceStep(ready: boolean | undefined, doing: string | undefined, failed: string | undefined): { state: StepState; detail: string } {
  const detail = doing !== undefined ? `${doing}…` : 'What your agents already talk to. Installed, started and updated for you.';
  if (ready === true) return { state: DONE, detail };
  if (doing === undefined && ready === false) return { state: needs(failed ?? 'The Memnox service is not answering yet'), detail };
  return { state: WAITING, detail };
}

/** The Memnox terminals extension, which the daemon puts into VS Code, Cursor and Windsurf by itself. */
export interface EditorRow {
  /** Shown only where an editor is, so a computer with none is never told of a gap. */
  readonly shown: boolean;
  readonly state: StepState;
  readonly detail: string;
}

/** The editor row as the Mac's first run says it: waiting until the daemon's install lands, then done. */
export function editorRow(editors: { readonly present: boolean; readonly withExtension: readonly string[] } | undefined): EditorRow {
  const landed = (editors?.withExtension.length ?? 0) > 0;
  return {
    shown: editors?.present === true,
    state: landed ? DONE : WAITING,
    detail: landed
      ? 'The Memnox terminals extension is in, so your voice reaches the session’s own tab. Restart the editor if it was open.'
      : 'The Memnox terminals extension goes into VS Code, Cursor and Windsurf by itself, so your voice reaches the session’s own tab.',
  };
}
