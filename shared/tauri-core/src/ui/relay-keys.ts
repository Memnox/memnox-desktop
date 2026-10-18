/** The server the voice talks to, by machine id, empty for this computer; Settings writes it and the island follows. */
export const TALKING_TO = 'memnox.talkingTo';
/** Bumped by Settings when a server is paired or forgotten, so the island opens or drops its link. */
export const SERVERS_CHANGED = 'memnox.servers.changed';
/** Bumped when the person signs in or out of their workspace, so the island reads the inbox again or stops. */
export const TEAM_CHANGED = 'memnox.team.changed';
