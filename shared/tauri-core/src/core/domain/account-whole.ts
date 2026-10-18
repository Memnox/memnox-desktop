import { DONE, needs, WAITING, type StepState } from './step-state';

/**
 * Where one of the daemon's two sign ins stands, as the Mac's `DaemonAccountStep`: the person, which the
 * voice acts through, or this computer's connection to its workspace, which carries rules, memory and phones.
 */
export type DaemonAccountStep =
  /** Not asked yet. */
  | { kind: 'unknown' }
  | { kind: 'signed-out' }
  | { kind: 'starting' }
  | { kind: 'showing-code'; code: string }
  | { kind: 'signed-in'; name: string }
  | { kind: 'failed'; why: string }
  /** This Memnox is from before the daemon could sign anyone in, so the button updates it. */
  | { kind: 'too-old' };

/**
 * The one sign in as the person sees it, ported from the Mac's `AccountWhole`. The Mac signs in its own app
 * as well; here the daemon's person sign in stands in for that, so the page is signed in only when the
 * person and this computer's connection both are, and never says so while the voice still cannot reach
 * the person's tools.
 */
export type AccountWhole =
  | { kind: 'signed-out' }
  | { kind: 'working'; doing: string }
  | { kind: 'showing-code'; code: string }
  | { kind: 'incomplete'; name: string; why: string }
  | { kind: 'too-old' }
  | { kind: 'signed-in'; name: string; workspace: string | undefined }
  | { kind: 'failed'; why: string };

export const AccountWholeLines = {
  reading: 'Asking Memnox where you stand.',
  asking: 'Asking Memnox Cloud for a code.',
  settingUp: 'Connecting Memnox on this computer to your workspace.',
  notYet: 'Memnox on this computer is not connected to your workspace yet.',
  tooOld: 'The Memnox running on this computer is older than the app. Update brings it up to date, with no terminal.',
  unreachable: 'The Memnox daemon did not answer. Check Connection and try again.',
  expired: 'The code ran out before it was approved. Sign in again for a new one.',
} as const;

export function accountWhole(person: DaemonAccountStep, machine: DaemonAccountStep): AccountWhole {
  switch (person.kind) {
    case 'unknown':
      return { kind: 'working', doing: AccountWholeLines.reading };
    case 'starting':
      return { kind: 'working', doing: AccountWholeLines.asking };
    case 'showing-code':
      return { kind: 'showing-code', code: person.code };
    case 'failed':
      return { kind: 'failed', why: person.why };
    case 'too-old':
      return { kind: 'too-old' };
    case 'signed-out':
      return { kind: 'signed-out' };
    case 'signed-in':
      return rest(person.name, machine);
  }
}

/** The person is in, so this computer's connection decides what is left. */
function rest(name: string, machine: DaemonAccountStep): AccountWhole {
  switch (machine.kind) {
    case 'too-old':
      return { kind: 'too-old' };
    case 'showing-code':
      return { kind: 'showing-code', code: machine.code };
    case 'unknown':
    case 'starting':
      return { kind: 'working', doing: AccountWholeLines.settingUp };
    case 'failed':
      return { kind: 'incomplete', name, why: machine.why };
    case 'signed-out':
      return { kind: 'incomplete', name, why: AccountWholeLines.notYet };
    case 'signed-in':
      return { kind: 'signed-in', name, workspace: machine.name.trim() === '' ? undefined : machine.name };
  }
}

export function accountState(whole: AccountWhole): StepState {
  switch (whole.kind) {
    case 'signed-in':
      return DONE;
    case 'failed':
      return needs(whole.why);
    case 'incomplete':
      return needs(whole.why);
    case 'too-old':
      return needs(AccountWholeLines.tooOld);
    case 'signed-out':
    case 'working':
    case 'showing-code':
      return WAITING;
  }
}

export function accountTitle(whole: AccountWhole): string {
  switch (whole.kind) {
    case 'signed-out':
    case 'failed':
      return 'Not signed in';
    case 'working':
      return 'Signing in';
    case 'showing-code':
      return 'Approve this computer';
    case 'incomplete':
      return `Signed in as ${whole.name}`;
    case 'too-old':
      return 'Memnox needs an update';
    case 'signed-in':
      return whole.workspace === undefined ? `Signed in as ${whole.name}` : `Signed in as ${whole.name}, ${whole.workspace}`;
  }
}

export function accountDetail(whole: AccountWhole): string {
  switch (whole.kind) {
    case 'signed-out':
    case 'failed':
      return 'One approval in your browser signs in Memnox on this computer and connects it to your workspace.';
    case 'working':
      return whole.doing;
    case 'showing-code':
      return 'The console is open in your browser. Approve this computer there, once.';
    case 'incomplete':
      return 'Memnox on this computer is not fully signed in yet. Finish completes it.';
    case 'too-old':
      return 'Update brings it up to date, with no terminal, and then signing in completes.';
    case 'signed-in':
      return 'Signing out signs out Memnox on this computer, and keeps the rules already here.';
  }
}

/** "482913" as "482 913", the way both screens show the digits. */
export function groupedDigits(code: string): string {
  const plain = code.replace(/\s+/g, '');
  return plain.length === 6 ? `${plain.slice(0, 3)} ${plain.slice(3)}` : plain;
}
