import type { SessionCard } from '@memnox/core/wire';
import { ago, repositoryName } from './session-text';

/** A repository an agent has worked in, as the sessions tell it, newest first. */
export interface SeenWorkspace {
  readonly path: string;
  readonly name: string;
  readonly agents: readonly { readonly kind: string; readonly name: string }[];
  readonly sessions: number;
  readonly lastActiveAt: string | undefined;
  /** "2 hours ago", taken at the moment the list was made. */
  readonly lastActive: string | undefined;
}

/** Sessions grouped by the repository they ran in; a session with none belongs to no workspace. */
export function workspacesFrom(cards: readonly SessionCard[], now: number): SeenWorkspace[] {
  const byPath = new Map<string, SessionCard[]>();
  for (const card of cards) {
    if (card.repository === undefined || card.repository === '') continue;
    byPath.set(card.repository, [...(byPath.get(card.repository) ?? []), card]);
  }
  const seen = [...byPath].map(([path, held]) => workspaceOf(path, held, now));
  return seen.sort((a, b) => (b.lastActiveAt ?? '').localeCompare(a.lastActiveAt ?? ''));
}

function workspaceOf(path: string, cards: readonly SessionCard[], now: number): SeenWorkspace {
  const agents = new Map<string, string>();
  for (const card of cards) agents.set(card.agent, card.agentName);
  const lastActiveAt = cards
    .map((card) => card.lastActive)
    .filter((at): at is string => at !== undefined)
    .sort()
    .at(-1);
  return {
    path,
    name: repositoryName(path) ?? path,
    agents: [...agents].map(([kind, name]) => ({ kind, name })),
    sessions: cards.length,
    lastActiveAt,
    lastActive: ago(lastActiveAt, now),
  };
}
