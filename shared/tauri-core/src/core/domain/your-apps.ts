import type { DaemonResponse, ToolConnection } from '@memnox/core/wire';
import { toolkitName } from './tool-brand';

/**
 * The Your apps screen: the tools the person connected as themselves, the ones this computer already
 * reaches, and the catalogue searched for more. Nothing here asks for a Memnox account, since the
 * daemon connects a tool for whoever sits at this computer.
 */

/** One row of connections-list; `local` marks a tool this computer reaches itself, which an older wire leaves out. */
export type YourConnection = ToolConnection & { readonly local?: true };

/** One tool the catalogue offers, by the slug connections-sign-in takes. */
export type CatalogueTool = NonNullable<DaemonResponse['toolkits']>[number];

/** How a tool stands for the person, which decides its line and its button. */
export type AppStanding = 'local' | 'connected' | 'signed-out' | 'waiting';

/** What each standing says under the tool's name. */
export const STANDING_LINE: Record<AppStanding, string> = {
  local: 'Already on this computer',
  connected: 'Connected as you',
  'signed-out': 'Signed out, so sign in again to use it',
  waiting: 'Finish signing in in your browser',
};

/** What a catalogue card says under a tool nobody has connected yet. */
export const CONNECT_LINE = 'Sign in with your own account';

/** The catalogue answers at most this many tools to one search. */
export const CATALOGUE_PAGE = 30;

export interface ConnectedCard {
  readonly toolkit: string;
  readonly name: string;
  readonly standing: AppStanding;
  readonly line: string;
  /** A local tool is removed from the agent or signed out where it runs, never disconnected here. */
  readonly canDisconnect: boolean;
  readonly canSignInAgain: boolean;
}

export interface CatalogueCard {
  readonly slug: string;
  readonly name: string;
  readonly logo: string | undefined;
  /** Connect for a tool not yet connected; a tool already here says so instead of offering a second press. */
  readonly standing: AppStanding | 'new';
  readonly line: string;
}

export function standingOf(connection: YourConnection, waitingFor: string | undefined): AppStanding {
  if (connection.local === true) return 'local';
  if (waitingFor === connection.toolkit) return 'waiting';
  return connection.connected ? 'connected' : 'signed-out';
}

/** The person's tools in the daemon's order, each with its line and what can be done to it. */
export function connectedCards(connections: readonly YourConnection[], waitingFor: string | undefined): ConnectedCard[] {
  return connections.map((connection) => {
    const standing = standingOf(connection, waitingFor);
    return {
      toolkit: connection.toolkit,
      name: toolkitName(connection.toolkit),
      standing,
      line: STANDING_LINE[standing],
      canDisconnect: standing !== 'local',
      canSignInAgain: standing === 'signed-out',
    };
  });
}

/** The catalogue's answer as cards, each marked where the person already has that tool. */
export function catalogueCards(found: readonly CatalogueTool[], connections: readonly YourConnection[], waitingFor: string | undefined): CatalogueCard[] {
  const mine = new Map(connections.map((each) => [each.toolkit, each]));
  return found.map((tool) => {
    const have = mine.get(tool.slug);
    const standing = have === undefined ? (waitingFor === tool.slug ? 'waiting' : 'new') : standingOf(have, waitingFor);
    return { slug: tool.slug, name: tool.name, logo: tool.logo, standing, line: standing === 'new' ? CONNECT_LINE : STANDING_LINE[standing] };
  });
}

/** The line over the catalogue's cards: a count of what it found, or why there is nothing to count yet. */
export function resultCountLine(state: { query: string; count: number; searching: boolean; note: string | undefined }): string {
  if (state.note !== undefined) return state.note;
  if (state.searching) return 'Looking';
  const words = state.query.trim();
  const noun = state.count === 1 ? 'app' : 'apps';
  if (state.count === 0) return words === '' ? 'No apps to show' : `No app matches "${words}"`;
  if (words === '') return `${state.count} ${noun} you can connect`;
  if (state.count >= CATALOGUE_PAGE) return `The first ${state.count} apps matching "${words}", so type more to narrow it`;
  return `${state.count} ${noun} matching "${words}"`;
}

/** The heading's count over the person's own tools: "3 connected, 2 already on this computer". */
export function connectedSummary(cards: readonly ConnectedCard[]): string {
  const local = cards.filter((card) => card.standing === 'local').length;
  const connected = cards.length - local;
  const parts = [...(connected > 0 ? [`${connected} connected`] : []), ...(local > 0 ? [`${local} already on this computer`] : [])];
  return parts.length === 0 ? 'Nothing connected yet' : parts.join(', ');
}
