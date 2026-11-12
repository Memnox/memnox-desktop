/**
 * What a page says while the runtime is not answering, in place of an all clear: with the service away nothing an agent
 * asks can reach the person and no agent can be read, so "nothing waits" or "no agents" would be false comfort. Each
 * says it is away and opens Connection, where Check again installs or starts the service. Mirrors the Mac's wording.
 */
export const RuntimeAwayLines = {
  title: 'The Memnox service is not answering',
  approvals: 'Nothing an agent asks can reach you until it runs again.',
  agents: 'Memnox is not running, so the agents here cannot be read.',
  agentsCaption: 'Open Connection in Settings, where Check again starts it.',
  openConnection: 'Open Connection',
  /** Said while the service is still being put on this computer, in place of every line above. */
  starting: 'Starting Memnox',
  startingDetail: 'Memnox is setting itself up on this computer. The first time takes a minute or two, and there is nothing you need to do.',
} as const;

/**
 * Where the service stands, as a page says it: answering, still being started, away, or not asked yet. A window that
 * has never read it is still starting for a while after it opens, since the island installs and starts the service
 * by itself at launch, and a red line over a computer that is only being set up would send somebody looking for a
 * fault that is not there. Once it has answered, or the wait has run out, a service that is away is said to be away.
 */
export type RuntimeStanding = 'up' | 'starting' | 'away' | 'reaching';

/** Long enough for a first run to fetch, install, wire and start the service on a slow connection. */
export const START_GRACE_MS = 180_000;
/** How often a window still waiting on the service asks again. */
export const START_RETRY_MS = 2_000;

export function runtimeStanding(home: { readonly unavailable: boolean; readonly read: boolean }, openForMs: number): RuntimeStanding {
  if (!home.unavailable) return home.read ? 'up' : 'reaching';
  return !home.read && openForMs < START_GRACE_MS ? 'starting' : 'away';
}

/** The Settings page that starts the service again. */
export const CONNECTION_PAGE = 'connection';
