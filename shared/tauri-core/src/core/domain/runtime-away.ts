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
} as const;

/** The Settings page that starts the service again. */
export const CONNECTION_PAGE = 'connection';
