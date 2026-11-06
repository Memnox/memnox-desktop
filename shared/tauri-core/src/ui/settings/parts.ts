import { useEffect, useReducer } from 'react';
import { Account } from '../../core/application/account';
import { AgentHomes } from '../../core/application/agent-homes';
import { AppConnections } from '../../core/application/app-connections';
import { Backup } from '../../core/application/backup';
import { CommunityIndex } from '../../core/application/community-index';
import { DaemonAccount, DaemonSignIn } from '../../core/application/daemon-sign-in';
import { DaemonSupport } from '../../core/application/daemon-support';
import { HeldCalls } from '../../core/application/held-calls';
import { Home } from '../../core/application/home';
import { McpHub } from '../../core/application/mcp-hub';
import { LocalNetwork } from '../../core/application/local-network';
import { Memory } from '../../core/application/memory';
import { PersonalSync } from '../../core/application/personal-sync';
import { Profiles } from '../../core/application/profiles';
import { Activity, Agents, Studio } from '../../core/application/studio';
import { Sessions } from '../../core/application/sessions';
import { SkillsHub } from '../../core/application/skills';
import { SkillCare } from '../../core/application/skill-care';
import { PhonePairing } from '../../core/application/pairing';
import { Projects } from '../../core/application/projects';
import type { ConfirmKey } from '../../core/application/ports/confirm-key';
import type { DaemonLink } from '../../core/application/ports/daemon-link';
import type { PreferenceStore } from '../../core/application/ports/preference-store';
import type { Runtime } from '../../core/application/ports/runtime';
import { Preferences } from '../../core/application/preferences';
import { RequestIds } from '../../core/application/request-ids';
import { Setup } from '../../core/application/setup';
import { Signer } from '../../core/application/signer';
import { Tools } from '../../core/application/tools';
import { VoicePreferences } from '../../core/application/voice-preferences';
import { DictationWords, VoiceSettings } from '../../core/application/voice-settings';
import { themeFor, type Look } from '../../core/domain/appearance';
import { platformWords, type PlatformWords } from '../../core/domain/platform';
import { CloudInbox } from '../../core/application/cloud-inbox';
import type { Pairer } from '../../core/application/ports/pairer';
import type { HttpTransport, PersonCredentialStore } from '../../core/application/ports/workspace-inbox';
import { ServerPairing } from '../../core/application/server-pairing';
import { WorkspaceSignIn } from '../../core/application/workspace-sign-in';
import { SERVERS_CHANGED, TALKING_TO, TEAM_CHANGED } from '../relay-keys';
import { onPreferenceChange, type SettingsHost } from './host';
import { TeamAccount } from './team-account';
import { SetupModel } from './setup-model';

/** Everything a Settings page or a first run step draws from, built once per window. */
export interface SettingsParts {
  readonly host: SettingsHost;
  readonly words: PlatformWords;
  readonly setup: Setup;
  readonly signer: Signer;
  readonly voiceSettings: VoiceSettings;
  /** The voice's own switches, the same class and keys the island reads. */
  readonly voice: VoicePreferences;
  readonly dictation: DictationWords;
  readonly preferences: Preferences;
  readonly account: Account;
  readonly pairing: PhonePairing;
  readonly home: Home;
  readonly tools: Tools;
  /** The terminal or editor a session opens in, picked under Where your agents run. */
  readonly homes: AgentHomes;
  /** Adding any app, signing in to one again and disconnecting it, read back through `tools`. */
  readonly apps: AppConnections;
  /** The servers paired over the relay, and which machine the voice talks to. */
  readonly servers: ServerPairing;
  /** The person's own sign in to their workspace, for the calls it routes to them. */
  readonly team: TeamAccount;
  /** Where every setup step stands, shared by the overview, the setup pages and the first run. */
  readonly steps: SetupModel;
  /** Which daemon methods this computer's runtime answers, so a tab needing a newer one stays hidden. */
  readonly support: DaemonSupport;
  /** The agents' sessions, for Home, Agents and Workspaces. */
  readonly sessions: Sessions;
  /** What waits on the person, answered here as on the island, signed the same way. */
  readonly calls: HeldCalls;
  /** The MCP servers set up once and given to the agents the person chose. */
  readonly hub: McpHub;
  /** The rules in force and what could be let go next. */
  readonly studio: Studio;
  /** What the agents did, a page at a time, and why. */
  readonly activity: Activity;
  /** The agents on this computer as the runtime sees them. */
  readonly agents: Agents;
  /** Skills kept once and written into each agent's own format. */
  readonly skills: SkillsHub;
  /** Each skill's use and its fixes, a suggested fix accepted through skill-put like any new version. */
  readonly skillCare: SkillCare;
  /** The projects on this computer and what each gives the agents opened in it. */
  readonly projects: Projects;
  /** The setup sealed under a passphrase, and put back once signed on the island. */
  readonly backup: Backup;
  /** The sources memory is read from, the Learn queue, and the facts a person confirmed. */
  readonly memory: Memory;
  /** Whether paired phones reach this computer over the local network, turned on only once signed. */
  readonly network: LocalNetwork;
  /** The person's own setup carried between their machines, the key moved only once signed. */
  readonly sync: PersonalSync;
  /** Skills and rule packs from the community index, installed only as held skills and proposed rules. */
  readonly index: CommunityIndex;
  /** Named bundles of skills, servers and a rule pack, applied through signed proposals. */
  readonly profiles: Profiles;
}

const sleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

/** The composition root of the Settings window and the first run: the one place adapters meet the core. */
/** What reaches past this computer's daemon: the relay's pairing and Memnox Cloud with the person's credential. */
export interface RelayAdapters {
  readonly pairer: Pairer;
  readonly cloud: HttpTransport;
  readonly credentials: PersonCredentialStore;
}

export function buildParts(link: DaemonLink, host: SettingsHost, runtime: Runtime, key: ConfirmKey, store: PreferenceStore, relay: RelayAdapters): SettingsParts {
  const ids = new RequestIds();
  const setup = new Setup(link, runtime, ids, sleep);
  const signer = new Signer(link, key, ids);
  const voiceSettings = new VoiceSettings(link, ids);
  const person = new DaemonAccount(new DaemonSignIn(link, 'person', ids, sleep), sleep, (url) => host.openPage(url));
  const machine = new DaemonAccount(new DaemonSignIn(link, 'machine', ids, sleep), sleep, (url) => host.openPage(url));
  const account = new Account(
    person,
    machine,
    async () => void (await setup.bringUpToDate()),
    () => host.computerName(),
  );
  const tools = new Tools(link, ids);
  const timer = (ms: number, fire: () => void) => {
    const handle = setTimeout(fire, ms);
    return () => clearTimeout(handle);
  };
  const parts: Omit<SettingsParts, 'steps'> = {
    support: new DaemonSupport(link, ids),
    sessions: new Sessions(link, ids, timer),
    calls: new HeldCalls(link, signer, ids, { timer }),
    hub: new McpHub(link, ids),
    studio: new Studio(link, ids),
    activity: new Activity(link, ids),
    agents: new Agents(link, ids),
    skills: new SkillsHub(link, ids),
    skillCare: new SkillCare(link, ids),
    projects: new Projects(link, ids),
    backup: new Backup(link, ids),
    memory: new Memory(link, ids),
    network: new LocalNetwork(link, ids),
    sync: new PersonalSync(link, ids),
    index: new CommunityIndex(link, ids, platformWords(host.platform).keyTitle),
    profiles: new Profiles(link, ids, platformWords(host.platform).keyTitle),
    host,
    words: platformWords(host.platform),
    setup,
    signer,
    voiceSettings,
    voice: new VoicePreferences(store),
    dictation: new DictationWords(store),
    preferences: new Preferences(store),
    account,
    pairing: new PhonePairing(link, signer, key, ids, () => host.computerName()),
    home: new Home(
      link,
      ids,
      () => setup.protectAgents(),
      (ms, fire) => {
        const handle = setTimeout(fire, ms);
        return () => clearTimeout(handle);
      },
      () => setup.restartService(),
    ),
    tools,
    homes: new AgentHomes(
      store,
      () => host.agentHomes?.() ?? Promise.resolve([]),
      (link) => (host.openAppLink ?? host.openPage)(link),
    ),
    apps: new AppConnections(
      link,
      ids,
      tools,
      (url) => host.openPage(url),
      sleep,
      (ms, fire) => {
        const handle = setTimeout(fire, ms);
        return () => clearTimeout(handle);
      },
      // The Account page's own sign in, as the Mac's Connect starts it, carrying this computer in on the same approval.
      async () => {
        if (!account.person.isSignedIn) await account.start();
        return account.person.isSignedIn;
      },
    ),
    servers: new ServerPairing(
      relay.pairer,
      () => host.computerName() ?? 'This computer',
      platformWords(host.platform).keyTitle,
      () => store.save(SERVERS_CHANGED, String(Date.now())),
      Date.now,
      undefined,
      { load: () => store.load(TALKING_TO) || undefined, save: (machineId) => store.save(TALKING_TO, machineId ?? '') },
    ),
    team: new TeamAccount(
      new WorkspaceSignIn(new CloudInbox(relay.cloud), relay.credentials, key, sleep),
      () => host.computerName() ?? 'This computer',
      (url) => host.openPage(url),
      () => store.save(TEAM_CHANGED, String(Date.now())),
    ),
  };
  const whole = parts as SettingsParts;
  (whole as { steps: SetupModel }).steps = new SetupModel(whole);
  return whole;
}

/** Redraws whenever a use case says it changed. */
export function useObserved(...observed: { observe(listener: () => void): () => void }[]): void {
  const [, redraw] = useReducer((count: number) => count + 1, 0);
  useEffect(() => {
    const stops = observed.map((each) => each.observe(redraw));
    return () => {
      for (const stop of stops) stop();
    };
    // The use cases are built once per window, so their identity never changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
}

/** Redraws whenever any window changes a choice, so a switch flipped elsewhere shows here. */
export function usePreferences(): void {
  const [, redraw] = useReducer((count: number) => count + 1, 0);
  useEffect(() => onPreferenceChange(redraw), []);
}

/**
 * Paints this window in the look: Light and Dark set the theme outright, System leaves it to the media
 * query in styles.css. Called whenever the look changes, here or in another window.
 */
export function paintLook(look: Look): void {
  const root = document.documentElement;
  if (look === 'system') root.removeAttribute('data-theme');
  else root.setAttribute('data-theme', look);
  root.style.colorScheme = look === 'system' ? '' : themeFor(look, false);
}

/** Keeps this window in the person's look, from their choice and from the computer's for System. */
export function useLook(preferences: Preferences): void {
  usePreferences();
  const look = preferences.look;
  useEffect(() => paintLook(look), [look]);
}
