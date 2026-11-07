import { AGENT_HOME_KEYS, chosenHome, CLAUDE_CHAT_LINK, isAgentHome, type AgentHomeKind, type FoundHome } from '../domain/agent-homes';
import { Observed } from './observed';
import type { PreferenceStore } from './ports/preference-store';

/**
 * Where the person runs their agents, ported from the Mac's `AgentHomesModel`: the apps here, the one a session
 * opens in, kept so the island's launch reads the same choice, and the chat link tried once so it never asks mid task.
 */
export class AgentHomes extends Observed {
  private apps: readonly FoundHome[] | undefined;
  /** The editors whose chat link was just opened, waiting on the person to say whether it came up. */
  private readonly tried = new Set<AgentHomeKind>();

  constructor(
    private readonly store: PreferenceStore,
    private readonly find: () => Promise<readonly FoundHome[]>,
    private readonly openLink: (link: string) => void,
  ) {
    super();
  }

  /** Undefined until the first look. */
  get found(): readonly FoundHome[] | undefined {
    return this.apps;
  }

  get installed(): AgentHomeKind[] {
    return (this.apps ?? []).map((each) => each.kind);
  }

  get chosen(): AgentHomeKind | undefined {
    return chosenHome(this.store.load(AGENT_HOME_KEYS.chosen), this.answered, this.installed);
  }

  private get answered(): boolean {
    return this.store.load(AGENT_HOME_KEYS.answered) === 'true';
  }

  /** Reads every app again without asking anything, as the Mac's step looks every couple of seconds. */
  async look(): Promise<void> {
    this.apps = await this.find().catch(() => this.apps ?? []);
    this.changed();
  }

  /** Picks the app, or clears the pick when it was the one picked, as a tile on the Mac ticks and unticks. */
  toggle(home: AgentHomeKind): void {
    const next = this.chosen === home ? '' : home;
    this.store.save(AGENT_HOME_KEYS.chosen, next);
    this.store.save(AGENT_HOME_KEYS.answered, 'true');
    this.changed();
  }

  chatOpened(home: AgentHomeKind): boolean {
    return this.opened().includes(home);
  }

  isTrying(home: AgentHomeKind): boolean {
    return this.tried.has(home);
  }

  /** Opens Claude Code's chat through the same link a follow up uses, so the editor asks its one question now. */
  tryChat(home: AgentHomeKind): void {
    this.openLink(CLAUDE_CHAT_LINK);
    this.tried.add(home);
    this.changed();
  }

  chatCameUp(home: AgentHomeKind, yes: boolean): void {
    this.tried.delete(home);
    if (yes && !this.chatOpened(home)) this.store.save(AGENT_HOME_KEYS.chatOpened, [...this.opened(), home].join(','));
    this.changed();
  }

  open(link: string): void {
    this.openLink(link);
  }

  private opened(): AgentHomeKind[] {
    return (this.store.load(AGENT_HOME_KEYS.chatOpened) ?? '').split(',').filter(isAgentHome);
  }
}

/** The app a session opens in as the island reads it, by the same rule the page shows, with the apps asked fresh. */
export async function sessionHome(store: PreferenceStore, find: () => Promise<readonly FoundHome[]>): Promise<AgentHomeKind | undefined> {
  const installed = (await find().catch(() => [])).map((each) => each.kind);
  return chosenHome(store.load(AGENT_HOME_KEYS.chosen), store.load(AGENT_HOME_KEYS.answered) === 'true', installed);
}
