import type { DrivenBy, VoiceOn } from '@memnox/core/wire';

/**
 * A phone driving this computer until a time, as the island shows it for the whole of the grant, and
 * the phone holding the voice, ported from the Mac's `DriveGrant` and `PhoneVoice`.
 */
export interface DriveGrant {
  readonly deviceId: string;
  readonly name: string;
  /** Milliseconds since the epoch. */
  readonly until: number;
}

/** The grant a notice names, or undefined when it says the grant ended: no until, one unreadable, or one already past. */
export function driveGrant(drivenBy: DrivenBy, now: number): DriveGrant | undefined {
  if (drivenBy.until === undefined) return undefined;
  const until = Date.parse(drivenBy.until);
  if (Number.isNaN(until) || until <= now) return undefined;
  return { deviceId: drivenBy.deviceId, name: drivenBy.name, until };
}

/** Still live at this moment, so the island stops saying it the instant the time comes. */
export function isLive(grant: DriveGrant, now: number): boolean {
  return now < grant.until;
}

/** A plain word where the phone gave no name. */
function phoneName(name: string): string {
  const trimmed = name.trim();
  return trimmed === '' ? 'your phone' : trimmed;
}

/** What the island says for as long as a drive lasts. */
export function driveLabel(grant: Pick<DriveGrant, 'name'>): string {
  return `Driven from ${phoneName(grant.name)}`;
}

/** The phone holding the voice, or undefined once it gave it back. */
export function phoneVoice(voiceOn: VoiceOn): { deviceId: string; name: string } | undefined {
  return voiceOn.holding ? { deviceId: voiceOn.deviceId, name: voiceOn.name } : undefined;
}

/** What the island says while a phone talks, so somebody at the computer knows why it stays silent. */
export function phoneVoiceLabel(phone: { name: string }): string {
  return `Talking on ${phoneName(phone.name)}`;
}
