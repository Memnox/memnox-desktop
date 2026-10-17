/** The oldest runtime this app works with, the same floor the Mac app holds. */
export const MINIMUM_RUNTIME = '0.13.14';

/** Where the daemon stands for this app. */
export type RuntimeState =
  | { kind: 'ready' }
  | { kind: 'unreachable' }
  /** It answers but predates something this app needs. */
  | { kind: 'too-old' }
  /** It said no in its own words. */
  | { kind: 'refused'; why: string };

/** Whether a version is this one or newer, by major, minor and patch as numbers; none at all is older. */
export function isAtLeast(version: string | undefined, minimum: string): boolean {
  if (version === undefined) return false;
  const parts = (text: string) => text.split(/[.+-]/).slice(0, 3).map((part) => Number.parseInt(part, 10) || 0);
  const have = parts(version);
  const need = parts(minimum);
  for (let at = 0; at < 3; at += 1) {
    const a = have[at] ?? 0;
    const b = need[at] ?? 0;
    if (a !== b) return a > b;
  }
  return true;
}

/** Why the daemon is still not there after setup tried, in words the person can act on. */
export function whyNotReady(state: RuntimeState): string | undefined {
  switch (state.kind) {
    case 'ready':
      return undefined;
    case 'too-old':
      return 'This Memnox is older than the app and would not update. Press Check again to try once more.';
    case 'refused':
      return `Memnox answered: ${state.why}. Press Check again to try once more.`;
    case 'unreachable':
      return 'The Memnox service would not start. Press Check again to try once more.';
  }
}
