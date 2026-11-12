import { X as McpToolDeclaration, a6 as DiscoveredAgentKind, a5 as ResourceKind, a9 as Sensitivity, ad as McpTool, a2 as SurfaceKind, a4 as Surface, I as ToolClass, v as MemnoxEvent, m as DecisionEffect, a as Policy, ak as DeclaredScope, _ as ScopeComparison, b as ActionRequest, aO as ScopeSubject } from './policy-CpDGjGKQ.js';

/**
 * Discovery reaches for the filesystem constantly, so the filesystem is an argument.
 * Every detector is then a pure function of what the machine says it holds.
 */
interface MachineReader {
    /** True when the path exists. Never throws: an unreadable path is simply absent. */
    exists(path: string): Promise<boolean>;
    /** The file's text, or null when it cannot be read. */
    read(path: string): Promise<string | null>;
    /** Immediate children of a directory, empty when it cannot be listed. */
    list(path: string): Promise<string[]>;
    homeDir(): string;
    /** The operating-system user, which is the owner hint until a person confirms it. */
    userName(): string;
}
/**
 * MCP servers are enumerated over the protocol rather than guessed from a config,
 * because a config says what a server is called and not what it can do.
 */
interface McpLister {
    listTools(server: string, command: string, args: readonly string[]): Promise<McpToolDeclaration[]>;
}
/** A step that changes the machine states its inverse before it runs. */
interface HardenWriter {
    write(path: string, contents: string): Promise<void>;
    remove(path: string): Promise<void>;
    read(path: string): Promise<string | null>;
}

/**
 * The binary an agent runs as, found the way the shell finds it: the first match on PATH.
 * Where it lives is read off the path; who signed it needs an inspector, because that
 * means running the platform's own tool, and discovery reads files and runs nothing.
 */
declare const HOST_SIGNATURE: {
    /** Signed by a named developer identity. */
    readonly SIGNED: "signed";
    /** Signed with no identity, which is how a locally built binary is signed. */
    readonly AD_HOC: "ad-hoc";
    readonly UNSIGNED: "unsigned";
    /** A script for an interpreter, which no platform signs. */
    readonly SCRIPT: "script";
    /** Not checked, or not checkable on this platform. */
    readonly UNKNOWN: "unknown";
};
type HostSignatureState = (typeof HOST_SIGNATURE)[keyof typeof HOST_SIGNATURE];
declare const HOST_LOCATION: {
    /** Somewhere a package manager or an installer puts binaries. */
    readonly INSTALLED: "installed";
    /** Temp, Downloads, or inside the work: places a binary lands without being installed. */
    readonly UNUSUAL: "unusual";
};
type HostLocation = (typeof HOST_LOCATION)[keyof typeof HOST_LOCATION];
interface HostSignature {
    state: HostSignatureState;
    /** The identity it was signed with, as the platform printed it. */
    signer?: string;
}
interface AgentHost {
    /** The path on PATH, which is what a shell would run. */
    path: string;
    location: HostLocation;
    signature: HostSignature;
}
/** Reads a binary's signature. Absent, every host reports its signature as unknown. */
interface HostInspector {
    inspect(path: string): Promise<HostSignature>;
}
interface HostSearch {
    /** The PATH the agent would be started with, split by the platform's delimiter. */
    path: string | undefined;
    projectDirs: readonly string[];
    inspector?: HostInspector;
}
/** The first match on PATH, or null when the product installs no command or none is found. */
declare function agentHostOf(kind: DiscoveredAgentKind, reader: MachineReader, search: HostSearch): Promise<AgentHost | null>;
/**
 * A directory on PATH inside the repository is the classic plant: the agent's own name,
 * resolved ahead of the installed one, from a place a clone can write.
 */
declare function locationOf(path: string, home: string, projectDirs: readonly string[]): HostLocation;

/**
 * Whether an agent stops to ask before it acts. Read off the setting the product itself
 * reads, because an agent that approves its own actions is bounded only by the account
 * and the machine it runs on, and that is the one fact a reach count does not carry.
 */
declare const APPROVAL_STATE: {
    /** It acts without a person confirming each step. */
    readonly AUTO: "auto";
    /** It asks, at least for what its own defaults consider risky. */
    readonly ASKS: "asks";
    /** A model approves its actions and a person sees only what the model leaves. */
    readonly MODEL_REVIEWED: "model-reviewed";
    /** Nothing on disk says, so neither answer is printed as a fact. */
    readonly UNKNOWN: "unknown";
};
type ApprovalState = (typeof APPROVAL_STATE)[keyof typeof APPROVAL_STATE];
interface ApprovalPosture {
    state: ApprovalState;
    /** The setting as it is spelled in the file, so the line can be checked by hand. */
    setting?: string;
    declaredIn?: string;
}
/** A product with no reader here is unknown, never assumed to ask. */
declare function approvalPostureOf(kind: DiscoveredAgentKind, reader: MachineReader, projectDirs: readonly string[]): Promise<ApprovalPosture>;

/** What every agent id starts with, and the only place it is spelled. */
declare const AGENT_ID_PREFIX = "agt_";
/** The id a detected agent is known by, everywhere, for ever. */
declare function agentIdFor(kind: string): string;
/** The id without its prefix, for a sentence a person reads. */
declare function agentNameIn(agentId: string): string;
/** A kind, not a session, or the roster is noise by week two. */
interface DiscoveredAgent {
    id: string;
    kind: DiscoveredAgentKind;
    version?: string;
    /** The files that proved it exists, so a detection can be argued with. */
    configPaths: string[];
    /** Which apps host it: one agent kind can run inside several clients. */
    clients: string[];
    /** Generated locally and never sent; the public half goes up only at enrolment. */
    keypairPath?: string;
    /** The operating-system user, until a person confirms it. */
    ownerHint: string;
    /** Whether it asks before acting, from the setting it reads. Set by discovery, not a detector. */
    approval?: ApprovalPosture;
    /** The binary it runs as, when the product installs one and it is on PATH. */
    host?: AgentHost;
    firstSeen: string;
    lastSeen: string;
}
interface AgentRef {
    id: string;
    kind: DiscoveredAgentKind;
}
declare function agentRefOf(agent: DiscoveredAgent): AgentRef;

/**
 * A thing on this machine an agent could reach, and how sensitive it is, read from a
 * path's shape because opening a file to be sure would make this scanner worth stealing.
 */
interface Resource {
    id: string;
    kind: ResourceKind;
    path?: string;
    /** Where a resource that is not a file was named, such as the env file holding a URL. */
    declaredIn?: string;
    /** A hash. NEVER the value: what is stored is a path, a kind and this. */
    fingerprint?: string;
    sensitivity: Sensitivity;
    reachableBy: AgentRef[];
}
/**
 * Truncated, so it tells two files apart and cannot attack one: a report carrying the
 * shape of somebody's SSH key would be the worst bug this product could ship.
 */
declare function fingerprint(value: string): string;
/** A `.env` file, with or without suffixes such as `.production.local`, or a direnv `.envrc`. */
declare const ENV_FILE_PATTERN: RegExp;
declare function classifySensitivity(path: string): Sensitivity;
declare function isCredentialPath(path: string): boolean;
/** The kind is read off the path, so nothing has to open a file to be counted. */
declare function classifyResourceKind(path: string): ResourceKind;

/**
 * The step a tool plays in a chain. A tool allow-list checks one call at a time, which
 * is the right thing to check and not the only thing: `read_customer`, `create_export`
 * and `send_file` are each unremarkable, and holding all three is an exfiltration path.
 */
declare const CHAIN_LINK: {
    /** Gets hold of something worth having. */
    readonly ACQUIRE: "acquire";
    /** Turns it into one movable artifact. */
    readonly PACKAGE: "package";
    /** Puts it somewhere the reader's organization does not control. */
    readonly EMIT: "emit";
};
type ChainLink = (typeof CHAIN_LINK)[keyof typeof CHAIN_LINK];
/** One completed path, with the tools that make it up so it can be argued with. */
interface CombinedCapability {
    id: string;
    /** What holding all of these amounts to, in the words somebody would repeat. */
    consequence: string;
    /** The tools that form the chain, in the order they would be used. */
    steps: {
        link: ChainLink;
        server: string;
        tool: string;
    }[];
    /** The subject the chain acquires, which is why it is worth printing. */
    subject: string;
    /**
     * True when no single step is destructive. This is the whole reason the chain needs
     * naming: an allow-list that reviews calls one at a time passes every one of them.
     */
    individuallyHarmless: boolean;
}
/**
 * Chains an agent can complete on its own, across every server it holds. The tools are
 * grouped by subject first, because `read_customer` plus `send_invoice` is two jobs and
 * `read_customer` plus `send_customer_report` is one path.
 */
declare function combinedCapabilities(tools: readonly McpTool[]): CombinedCapability[];
/** The step one tool name plays, for a seam ruling a single call rather than a surface. */
declare function chainLinkOfName(name: string): ChainLink | null;
/** One agent, and every path its own tools open together. */
interface AgentChains {
    agentId: string;
    capabilities: CombinedCapability[];
}
/**
 * Chains per agent, from whatever tools the surfaces carry. One function for `discover`,
 * `doctor` and `protect`, so a finding never appears in one command and not another.
 */
declare function chainsFor(agentIds: readonly string[], surfaces: readonly {
    agentId: string;
    tools?: McpTool[];
}[]): AgentChains[];
/** The line for the screen: what it is, and the tools that make it up. */
declare function describeCombined(capability: CombinedCapability): string;

/**
 * Which agents can reach which resources, joined from what the probes proved, and counted
 * once per agent per resource so one fact never carries two numbers.
 */
interface Reachability {
    agentId: string;
    /** Counts and names, never percentages: a percentage has no denominator here. */
    resources: Resource[];
    /** True when a shell surface made the closure everything the user can reach. */
    viaShell: boolean;
    surfaces: SurfaceKind[];
}
/**
 * Reachability is transitive. An agent that can run a shell reaches everything the shell
 * can, and a map that reported only the surface it was configured with would understate
 * every coding agent on the machine.
 */
declare function computeReachability(agents: readonly AgentRef[], surfaces: readonly Surface[], resources: readonly Resource[]): Reachability[];
/** Fills in `reachableBy`, so a resource reads from either direction without a second pass. */
declare function attributeResources(resources: readonly Resource[], reachability: readonly Reachability[], agents: readonly AgentRef[]): Resource[];
/**
 * Which agents reach a credential path, counted off the same table the reachable block
 * reads, so one file cannot carry two different counts on one screen.
 */
declare function agentsReachingPath(path: string, agents: readonly AgentRef[], surfaces: readonly Surface[]): AgentRef[];

/**
 * A browser driver with a persistent profile is the quietest credential on the machine:
 * an agent that can drive it is inside every site the person is still logged into.
 */
interface BrowserFinding {
    /** playwright, puppeteer, or whatever drove it. */
    driver: string;
    /** What proved it: a package directory, never an inference from a name. */
    detectedFrom: string;
    /** A profile that survives between runs, which is what carries the logins. */
    persistentProfile?: string;
    /** How many origins the profile still holds a login for. A count, never the sites. */
    savedLogins?: number;
}
/**
 * Estimated from the store's size rather than read, because the file holding logins is
 * encrypted and opening it is the one thing this product must not do.
 */
declare function countLogins(loginDataSize: number): number;
declare function findBrowserAutomation(reader: MachineReader, projectDirs: readonly string[]): Promise<BrowserFinding[]>;
declare function describeBrowser(finding: BrowserFinding): string;
/**
 * One ask per host per session. Asking on every navigation would train somebody to
 * hold the key down, which is worse than not asking.
 */
declare class BrowserHosts {
    private readonly answered;
    /** True when this session has already been asked about this host. */
    seen(sessionId: string, host: string): boolean;
    remember(sessionId: string, host: string): void;
    forget(sessionId: string): void;
}
/** Null for a local target: driving your own dev server is not the thing worth asking about. */
declare function navigationHost(url: string): string | null;
/**
 * The launchers worth standing in front of, because a driver arrives at a site with the
 * person's own session cookie. Each gets an interceptor wherever the machine has it.
 */
declare const BROWSER_LAUNCHERS: readonly string[];
declare function isBrowserLauncher(binary: string): boolean;
/** The first argument that is a URL. A launcher takes one; the rest are its own flags. */
declare function urlArgumentIn(args: readonly string[]): string | null;

/**
 * Credential files and what they let an agent do, read from structure: profile names,
 * host names and counts, and never a value. The one owner of every credential path list.
 */
interface CredentialFinding {
    /** What it is, in the reader's words: "AWS", "GitHub CLI". */
    kind: string;
    path: string;
    /** Structural detail only: profile names, hosts, contexts. Never a secret. */
    detail?: string;
    /** How many things it holds, where counting is the honest summary. */
    count?: number;
}
/** Home paths opened to be fingerprinted, never kept: what leaves is a path and a hash. */
declare const FINGERPRINTED_HOME_PATHS: readonly string[];
/** The `.env` names people actually use, in the directories they actually work in. */
declare const ENV_FILE_NAMES: readonly string[];
/** Credential files that live beside the work rather than in the home directory. */
declare const PROJECT_CREDENTIAL_FILES: readonly string[];
/**
 * Counted, never read out: a `.env` is the credential file most likely to hold something
 * live, so the summary is how many variables it holds and how many are named like a key.
 */
declare function findEnvFiles(reader: MachineReader, projectDirs: readonly string[]): Promise<EnvFinding[]>;
declare function findCredentials(reader: MachineReader): Promise<CredentialFinding[]>;
declare function looksLikeCredential(name: string): boolean;
interface EnvFinding {
    path: string;
    variables: number;
    /** How many are named like a credential. A count, never the names' values. */
    keyLike: number;
}
declare function readEnvFile(path: string, contents: string): EnvFinding;
interface AuthenticatedCli {
    name: string;
    /** The credential that makes it authenticated, by path or variable name. */
    via: string;
    /** The sentence the scan prints. */
    headline: string;
    /** Structural detail from the credential, e.g. profile or context names. */
    detail?: string;
    externalStateVerbs: number;
    destructiveVerbs: number;
    /** Set when a name looks like production. A guess, and printed as one. */
    productionLooking?: string;
}
/** Reported as "named like production", never as production. */
declare function productionLooking(detail: string | undefined): string | undefined;
/** Every file the scan reads as a credential, relative to home, for the tables to name. */
declare const SCANNED_CREDENTIAL_FILES: readonly string[];
/**
 * A binary on PATH plus a credential it can read is an authenticated CLI, and that
 * pair is the whole finding: either alone is unremarkable.
 */
declare function authenticatedClis(binaries: readonly string[], credentials: readonly CredentialFinding[], envNames?: readonly string[]): AuthenticatedCli[];

/**
 * What every agent detector answers. A detector proves an agent from files on disk and
 * names them, and never guesses from a name somebody would act on and cannot verify.
 */
interface DetectionResult {
    agent: DiscoveredAgent;
    surfaces: Surface[];
    /** Set by a harness: the agents it launches, and what it launches them with. */
    hosted?: HostedAgents;
}
/**
 * What a harness runs underneath itself. Separate from the agent, because a harness is
 * one row on the roster and several principals at the seam.
 */
interface HostedAgents {
    /** Kinds it drives, as its own config named them. Never inferred from the binary. */
    runtimes: string[];
    /** Roles it defines on disk, e.g. a swarm's planner, coder, deployer. */
    roles: string[];
    /** Hook or worker files it installed into another product's directory. */
    hooks: string[];
    /** True when its config turns on agent-to-agent work across machines. */
    federated: boolean;
    /** The file that proved each of the above, so a harness row is arguable. */
    evidence: string[];
}
/**
 * Discovery reads the home directory; a harness leaves most of its state beside the
 * work. Passed in rather than read, so a detector stays a function of what it was given.
 */
interface DetectionContext {
    projectDirs: readonly string[];
}
/**
 * One module per product's config layout, versioned because those layouts change without
 * notice. An upstream rename empties one detector and never the whole screen.
 */
interface AgentDetector {
    readonly kind: string;
    /** The layout revision this detector was written against, printed in the report. */
    readonly layoutVersion: string;
    detect(reader: MachineReader, now: string, context?: DetectionContext): Promise<DetectionResult | null>;
}
declare const EMPTY_CONTEXT: DetectionContext;

/**
 * A harness runs other agents, so the roster says so: one row reading like Claude Code
 * while launching nine roles is a wrong report.
 */
interface Harness {
    agentId: string;
    kind: DiscoveredAgentKind;
    /** Agent kinds it drives, as its own config named them. Never inferred from a binary. */
    runtimes: string[];
    /** Roles it defines on disk. Each is a separate principal at the seam. */
    roles: string[];
    /** Files it installed into another product's directory, with the path that proved it. */
    hooks: string[];
    /** Agent-to-agent work across machines, whose far side no local roster can see. */
    federated: boolean;
    evidence: string[];
}
declare function harnessOf(agent: DiscoveredAgent, hosted: HostedAgents | undefined): Harness | null;
/** How many principals a harness really is, and one when it defines no roles, since zero reads as absent. */
declare function principalCount(harness: Pick<Harness, 'roles'>): number;
/** One line a person repeats to a colleague, built from counts and nothing else. */
declare function describeHarness(harness: Harness): string;

/**
 * Hooks as capabilities. A hook runs a command as this user on an agent's event, outside
 * the agent's own permission prompt, so a plugin that installs forty of them has granted
 * forty programs a seat in every session without one question being asked.
 */
/** The products whose hook files are read here, as their events are recorded under. */
declare const HOOK_HOST: {
    readonly CLAUDE_CODE: "claude-code";
    readonly CODEX: "codex-cli";
    readonly GEMINI: "gemini-cli";
    readonly CURSOR: "cursor";
    readonly WINDSURF: "windsurf";
};
type HookHost = (typeof HOOK_HOST)[keyof typeof HOOK_HOST];
interface DiscoveredHook {
    /** Stable across scans while the file says the same thing, so drift is a comparison. */
    id: string;
    host: HookHost;
    event: string;
    matcher?: string;
    /** The program it runs, by name. Never the line, which can carry a token. */
    program: string;
    /** A hash of the whole command, so a changed line is seen without keeping it. */
    digest: string;
    declaredIn: string;
    /** The plugin that installed it, as `name@marketplace`, when one did. */
    plugin?: string;
    /** It runs before something happens and can refuse it. */
    gate: boolean;
    /** What it prints is handed to the model as context, which is a prompt nobody reviewed. */
    feedsModel: boolean;
    /** Memnox's own hook, which is the seam rather than something to govern. */
    own: boolean;
}
/** One hook as the published inventory schema states it, kept beside the type it checks. */
declare const INVENTORY_HOOK_SCHEMA: {
    readonly type: "object";
    readonly required: readonly ["id", "host", "event", "program", "digest", "declaredIn", "gate", "feedsModel", "own"];
    readonly additionalProperties: false;
    readonly properties: {
        readonly id: {
            readonly type: "string";
        };
        readonly host: {
            readonly enum: ("claude-code" | "codex-cli" | "cursor" | "gemini-cli" | "windsurf")[];
        };
        readonly event: {
            readonly type: "string";
        };
        readonly matcher: {
            readonly type: "string";
        };
        readonly program: {
            readonly type: "string";
        };
        readonly digest: {
            readonly type: "string";
        };
        readonly declaredIn: {
            readonly type: "string";
        };
        readonly plugin: {
            readonly type: "string";
        };
        readonly gate: {
            readonly type: "boolean";
        };
        readonly feedsModel: {
            readonly type: "boolean";
        };
        readonly own: {
            readonly type: "boolean";
        };
    };
};
/**
 * Every hook the agents here will run, including those a Claude Code plugin brought. A
 * plugin is counted only when a settings file enables it, because one sitting in a
 * marketplace checkout runs nothing.
 */
declare function discoverHooks(reader: MachineReader, projectDirs?: readonly string[]): Promise<DiscoveredHook[]>;
/**
 * The program a command line runs, and the script when the program is an interpreter.
 * Leading `NAME=value` assignments are skipped unread, because that is where a token sits.
 */
declare function programOf(command: string): string;
/** Hooks somebody other than Memnox put there, which are the ones a person has to read. */
declare function foreignHooks(hooks: readonly DiscoveredHook[]): DiscoveredHook[];
/** One line of counts under the total, the way the scan prints every other kind of reach. */
declare function describeHooks(hooks: readonly DiscoveredHook[]): string;

/**
 * What an agent can reach on the network, read from the environment rather than
 * measured, because nothing in this product leaves the machine.
 */
declare const OUTBOUND_STATE: {
    /** A proxy or a sandbox stands in the way, so egress is at least observable. */
    readonly RESTRICTED: "restricted";
    /** Nothing in the environment says either way. Reported as unknown, never as safe. */
    readonly UNKNOWN: "unknown";
};
type OutboundState = (typeof OUTBOUND_STATE)[keyof typeof OUTBOUND_STATE];
interface NetworkProbe {
    outbound: OutboundState;
    /** Proxy variables in force, names only, because a proxy URL can carry credentials. */
    proxyVars: string[];
    /** Hosts the environment already exempts from the proxy, which is the real hole. */
    noProxy: string[];
    /** Sandbox indicators found, e.g. a container marker or a seccomp profile. */
    sandbox: string[];
    /** What was read to reach this answer, so the probe is itself inspectable. */
    read: string[];
}
interface NetworkProbeInput {
    env: NodeJS.ProcessEnv;
    /** Paths that exist. Passed in, because the probe stays a pure function. */
    present: readonly string[];
}
/** Container markers on disk. Checked by the caller so this stays free of IO. */
declare const SANDBOX_PATHS: readonly ["/.dockerenv", "/run/.containerenv"];
declare function probeNetwork(input: NetworkProbeInput): NetworkProbe;
declare function proxyIsBypassedEntirely(probe: NetworkProbe): boolean;
declare function describeNetwork(probe: NetworkProbe): string;

/**
 * A command-line tool an agent with a shell can invoke. Everything an agent reaches
 * through one of these is reachable whether or not Memnox can see the call.
 */
interface DiscoveredTool {
    name: string;
    /** The path that proved it. A tool with no evidence is a guess. */
    detectedFrom: string;
}
/** Looked for where they install, never assumed from a list. */
declare function detectTools(reader: MachineReader): Promise<DiscoveredTool[]>;
/**
 * A connection string names a database an agent can reach. The scheme and whether the
 * host reads as production is all that is kept: the URL holds a credential, and the
 * value never leaves the process that read it.
 */
declare function databasesIn(contents: string, declaredIn: string): Resource[];
/**
 * An agent that can run a shell or reach HTTP already reaches everything on the network,
 * and saying so plainly is most of the value of the map. Derived from the surfaces
 * detected, never asserted.
 */
declare function networkReach(surfaces: readonly Surface[]): Resource | null;

/**
 * Skills and installed personas treated like deployments: read for their reach, and one
 * reaching further than the version somebody accepted is held until they look.
 */
/** A skill the agent wrote for itself, or a persona somebody installed; both change tomorrow. */
declare const DEFINITION_KIND: {
    readonly SKILL: "skill";
    readonly AGENT: "agent";
};
type DefinitionKind = (typeof DEFINITION_KIND)[keyof typeof DEFINITION_KIND];
/**
 * How much a definition may touch, as its own file states it. Three answers, because a
 * subagent with no `tools` key inherits every tool, the widest grant a file can carry.
 */
declare const GRANT: {
    /** The file names the tools it may use. */
    readonly DECLARED: "declared";
    /** The file names none, and on this harness that means every tool in the session. */
    readonly INHERITS: "inherits";
    /** This shape carries no grant anything here knows how to read. */
    readonly UNREAD: "unread";
};
type GrantKind = (typeof GRANT)[keyof typeof GRANT];
interface ToolGrant {
    kind: GrantKind;
    /** Named tools, and empty for every kind but `DECLARED`. */
    tools: string[];
}
declare const SKILL_STANDING: {
    /** Seen before, unchanged, and somebody accepted it. */
    readonly KNOWN: "known";
    /** Never seen here before. */
    readonly NEW: "new";
    /** Changed, and what it can reach is the same or smaller. */
    readonly CHANGED: "changed";
    /** Changed, and it reaches further than the version somebody accepted. */
    readonly WIDENED: "widened";
};
type SkillStanding = (typeof SKILL_STANDING)[keyof typeof SKILL_STANDING];
interface DiscoveredSkill {
    id: string;
    name: string;
    path: string;
    /** Which agent's directory it was found in. */
    agent: string;
    /** Written for itself, or installed by somebody. */
    kind: DefinitionKind;
    /** What its own frontmatter says it may use, which is not the same as what it names. */
    grant: ToolGrant;
    /** Command-line tools it names, which is evidence and not proof that it runs them. */
    reaches: string[];
    /** Content digest, so a change is detected without keeping the text. */
    digest: string;
}
interface SkillFinding extends DiscoveredSkill {
    standing: SkillStanding;
    /** What it reaches now and did not before. The whole reason to hold it. */
    gained: string[];
    /** Its own grant got wider, including a fence removed, which the text may not show. */
    widerGrant: boolean;
}
declare function discoverSkills(reader: MachineReader, roots?: readonly string[]): Promise<DiscoveredSkill[]>;
/**
 * Personas installed into an agent's directory, read for the grant their header carries,
 * because on a harness that inherits, one declaring no tools runs with everything.
 */
declare function discoverAgents(reader: MachineReader, roots?: readonly string[]): Promise<DiscoveredSkill[]>;
/** Both kinds through one screen: they are the same question about the same machine. */
declare function discoverDefinitions(reader: MachineReader, roots?: readonly string[]): Promise<DiscoveredSkill[]>;
/**
 * The tool grant a definition states in its own header. An absent key is `INHERITS` only
 * where the harness documents it, and `UNREAD`, which is no evidence, everywhere else.
 */
declare function grantOf(text: string, suffix: string, inherits: boolean): ToolGrant;
/**
 * Binaries the text names, matched whole, and only those with a verb table, because a
 * name with no table behind it says nothing enforceable.
 */
declare function reachOf(text: string, binaries: readonly string[]): string[];
interface AcceptedSkill {
    id: string;
    digest: string;
    reaches: string[];
    acceptedAt: string;
    acceptedBy: string;
    /** Optional: a record written before grants were read carries none, and is not a widening. */
    grant?: ToolGrant;
}
/**
 * What changed since somebody last looked. A new skill is reported and not held, since
 * an agent that cannot write its first one gets this switched off.
 */
declare function reviewSkills(found: readonly DiscoveredSkill[], accepted: readonly AcceptedSkill[]): SkillFinding[];
/**
 * Whether the file's grant got wider than the one somebody accepted. Losing the key is
 * the case worth catching: four named tools becoming none is the largest change.
 */
declare function grantWidened(before: ToolGrant | undefined, now: ToolGrant): boolean;
/**
 * How many definitions arriving together stop being somebody's own work: a dozen in one
 * directory between two scans is an install nobody read.
 */
declare const BULK_ARRIVAL = 12;
interface Arrival {
    agent: string;
    /** The directory they all landed in. */
    root: string;
    definitions: SkillFinding[];
    /** How many of them run with every tool in the session. */
    inheriting: number;
}
/** Rosters that arrived at once, as one row each: the finding is the install, not any one file. */
declare function bulkArrivals(findings: readonly SkillFinding[], threshold?: number): Arrival[];
/**
 * Held until a person looks: a definition reaching further than the accepted version,
 * or a roster that arrived all at once. `NEW` alone is never held.
 */
declare function quarantined(findings: readonly SkillFinding[], threshold?: number): SkillFinding[];
/** What its own header says it may use, in the words the distinction needs. */
declare function describeGrant(grant: ToolGrant): string;
declare function describeSkill(finding: SkillFinding): string;

interface DiscoveryReport {
    agents: DiscoveredAgent[];
    surfaces: readonly Surface[];
    resources: Resource[];
    reachability: Reachability[];
    /** What was opened and why, so the tool that inspects credentials is itself inspectable. */
    read: string[];
    /** Servers this run started to ask what they hold, named for the same reason. */
    probed: string[];
    /** Command-line tools an agent with a shell can invoke, each with what proved it. */
    tools: DiscoveredTool[];
    /** What the environment says about reaching the network. Never measured by dialling. */
    egress: NetworkProbe;
    /** Credential files an agent here can read. Names and structure, never values. */
    credentials: CredentialFinding[];
    /** A binary plus a credential it can use: the pair is the finding. */
    authenticated: AuthenticatedCli[];
    /** Browser drivers, and whether they carry a profile that holds your logins. */
    browsers: BrowserFinding[];
    /** `.env` files in the directories worked in: counts of variables and key-like names. */
    envFiles: EnvFinding[];
    /** Agents that run other agents: one row on the roster and several principals at the seam. */
    harnesses: Harness[];
    /** Paths a set of tools opens that no single one does, per agent that can walk all of it. */
    combined: AgentChains[];
    /**
     * Skills and installed personas, each with the tool grant its own header states. Kept
     * out of `read`, where three hundred paths would bury the credentials.
     */
    definitions: DiscoveredSkill[];
    /** Commands the agents here run on their own events, outside their own permission prompt. */
    hooks: DiscoveredHook[];
}
interface DiscoveryOptions {
    detectors?: readonly AgentDetector[];
    /** Supplied rather than read, so discovery stays a function of what it was given. */
    env?: NodeJS.ProcessEnv;
    /** Directories the reader works in, which hold the credentials a repository has. */
    projectDirs?: readonly string[];
    /** Injected so a report is reproducible; never read off a clock inside the run. */
    now: string;
    /**
     * Supplied, each server is started and asked what it holds, the only thing here that
     * runs somebody else's code. Omitted, every MCP surface reports no tools.
     */
    lister?: McpLister;
    /** Supplied, each agent's binary is asked who signed it. Omitted, the signer is unknown. */
    inspector?: HostInspector;
}
/**
 * The only aggregate true at minute zero. With a lister it starts the MCP servers this
 * machine already launches, and names each one it started.
 */
declare function discover(reader: MachineReader, options: DiscoveryOptions): Promise<DiscoveryReport>;
/** Counts and names, not percentages: a percentage here has no denominator. */
declare function summarize(report: DiscoveryReport): {
    agents: number;
    surfaces: number;
    tools: number;
    reachableSecrets: number;
};

declare const CAPABILITY_AREA: {
    readonly CODE: "code";
    readonly DATABASES: "databases";
    readonly PAYMENTS: "payments";
    readonly CHAT: "chat";
    readonly CLOUD: "cloud";
    readonly OTHER: "other";
};
type CapabilityArea = (typeof CAPABILITY_AREA)[keyof typeof CAPABILITY_AREA];
/** The words a sentence uses for each area. */
declare const AREA_WORDS: Readonly<Record<CapabilityArea, string>>;
declare function areaOf(name: string): CapabilityArea;
/** One thing that can change something outside the machine, and which agents can do it. */
interface ReachingCapability {
    /** The action a rule is written about: `mcp.<tool>` or `<cli>.<verb>`. */
    action: string;
    /** The server or CLI it is reached through, which is what names its area. */
    via: string;
    area: CapabilityArea;
    agentIds: string[];
}
interface AreaCount {
    area: CapabilityArea;
    count: number;
}
/**
 * A count and where it lands. `total` is absent while any server has never said what it
 * holds, because a zero there would be a guess drawn as a fact.
 */
interface CapabilityTally {
    total?: number;
    areas: AreaCount[];
}
/**
 * The one count of what an agent here can change outside the machine: MCP tools classed write
 * or destructive, and the write or destructive verbs of each signed in CLI. The scan's closing
 * line, `--json` and the voice's scan screen all read this.
 */
declare function capabilitiesOf(report: DiscoveryReport): ReachingCapability[];
declare function tallyOf(capabilities: readonly ReachingCapability[], counted?: boolean): CapabilityTally;
/**
 * Each capability credited to the first agent in `agentIds` order that holds it, so the
 * per agent tallies sum to the machine's distinct count and a screen can add them up.
 */
declare function creditedTallies(capabilities: readonly ReachingCapability[], agentIds: readonly string[], counted?: boolean): Map<string, CapabilityTally>;
/** "code, databases, payments and your team's chat", in the fixed order, or null for none. */
declare function areaPhrase(areas: readonly AreaCount[]): string | null;

/**
 * What is holding one agent, seam by seam. Per agent rather than per machine, because a
 * wrapped Claude Code and an unwrapped Cursor average out to nothing anybody can act on.
 */
declare const SEAM_STATE: {
    /** Something is in front of this surface now. */
    readonly HELD: "held";
    /** The seam exists and is not in place for this agent yet. */
    readonly OPEN: "open";
    /** This agent does not have that surface, so there is nothing to hold. */
    readonly NOT_APPLICABLE: "not-applicable";
    /** The agent has the surface and Memnox has nothing to put in front of it. Said, never counted as held. */
    readonly NO_SEAM: "no-seam";
};
type SeamState = (typeof SEAM_STATE)[keyof typeof SEAM_STATE];
/** What holds a surface: one of Memnox's own seams, or the agent's own hook calling the rules. */
declare const HELD_BY: {
    readonly SEAM: "seam";
    readonly OWN_HOOK: "own-hook";
};
type HeldBy = (typeof HELD_BY)[keyof typeof HELD_BY];
interface SeamCoverage {
    surface: SurfaceKind;
    state: SeamState;
    /** Set when held, so a proof of a seam is never counted for a surface the agent's own hook holds. */
    heldBy?: HeldBy;
    /** What is true, in one line. */
    detail: string;
    /** The command that closes it. Absent when there is nothing to do. */
    next?: string;
}
interface CoverageFacts {
    /** True when the interceptor directory comes first on the PATH this shell has. */
    interceptorsFirstOnPath: boolean;
    interceptorsInstalled: boolean;
    /** Hooks present in the repository the reader is standing in. */
    gitHooksInstalled: boolean;
    /** A kernel profile has been written for the rules in force. */
    osGuardWritten: boolean;
    /** Proxy variables are set in this environment, so egress is observed. */
    egressProxySet: boolean;
    /** The interceptor directory is on the login PATH, which a windowed app's terminal inherits. */
    loginPathConfigured: boolean;
    /**
     * At least one rule file is registered. A seam over an empty rule set forwards
     * everything, so reporting it held would be a reassuring lie.
     */
    rulesRegistered: boolean;
    /** This agent's own settings run the policy hook before its tool calls. */
    ownPolicyHook: boolean;
}
declare function coverageFor(kind: string, agentId: string, surfaces: readonly Surface[], facts: CoverageFacts): SeamCoverage[];
/** Held over what could be held. A count, so a partly wired agent reads as partly wired. */
declare function coverageSummary(coverage: readonly SeamCoverage[]): {
    held: number;
    total: number;
};

/**
 * Whether a seam actually refuses something, proved by planting a rule and attempting what
 * it forbids, because installed is not governed and nothing here is inferred.
 */
declare const PROOF: {
    /** It was asked to refuse and it refused. */
    readonly ENFORCED: "enforced";
    /** It was asked to refuse and the action went through. The finding that matters. */
    readonly NOT_ENFORCED: "not-enforced";
    /** Nothing is in place to ask. Not a failure, and not a pass either. */
    readonly ABSENT: "absent";
    /** In place, and this cannot prove it from here. Said rather than counted as a pass. */
    readonly UNPROVEN: "unproven";
};
type ProofState = (typeof PROOF)[keyof typeof PROOF];
interface SeamProof {
    seam: SurfaceKind;
    state: ProofState;
    /** What was attempted and what came back, in one line. */
    detail: string;
    /** The command that closes it, when there is one. */
    next?: string;
}
/** Seams a laptop can be asked to prove, in the order the report reads best. */
declare const PROVABLE_SEAMS: readonly SurfaceKind[];
/**
 * Proved against asked. `absent` is not counted either way: a machine with no egress
 * proxy has not failed a test, it has declined to take one, and rolling that into a
 * score would make an uninstalled seam look like a broken one.
 */
declare function summarizeProof(proofs: readonly SeamProof[]): {
    enforced: number;
    asked: number;
    failed: number;
};
/**
 * True when a seam that was asked to refuse did not. Absent and unproven never fail, so a
 * machine without the egress proxy does not turn CI red for it.
 */
declare function enforcementFailed(proofs: readonly SeamProof[]): boolean;
declare function describeProof(state: ProofState): string;

/**
 * What `memnox doctor --prove` found, which the computer reports about itself and nobody checks
 * independently. Installed, tested and demonstrated are kept apart, each claiming less than the next.
 */
declare const PROOF_RECORD_VERSION = 1;
/** The test each seam is given, in words, and whether it travels the route an agent's call takes. */
declare const SEAM_TEST: Readonly<Record<string, {
    test: string;
    agentPath: boolean;
}>>;
interface SeamTestResult extends SeamProof {
    /** What was attempted, so a reader knows what a pass does and does not show. */
    test: string;
}
interface AgentProof {
    agentId: string;
    kind: string;
    installed: SurfaceKind[];
    tested: SurfaceKind[];
    demonstrated: SurfaceKind[];
}
interface ProofRecord {
    version: typeof PROOF_RECORD_VERSION;
    /** Absent on a machine not enrolled with a workspace. */
    machineId?: string;
    runtimeVersion: string;
    bundleHashApplied?: string;
    modeApplied: string;
    /** ISO time the tests ran. */
    provedAt: string;
    /** The enforcement path the tests ran against; a different digest later means a different path. */
    seamConfigDigest: string;
    seams: SeamTestResult[];
    agents: AgentProof[];
}
/** Each seam's result with the test it was given. */
declare function seamTestsOf(proofs: readonly SeamProof[]): SeamTestResult[];
/** One agent's surfaces sorted by how much a proof shows about them, never more than it shows. */
declare function agentProofOf(agent: {
    id: string;
    kind: string;
}, coverage: readonly SeamCoverage[], seams: readonly SeamProof[]): AgentProof;
/**
 * A digest of what holds each agent's surfaces, read with facts no process's environment changes.
 * Wrapping a config, adding a hook, moving PATH or emptying the rules changes it, and ends the proof.
 */
declare function seamConfigDigestOf(agents: readonly {
    id: string;
    coverage: readonly SeamCoverage[];
}[]): string;

/**
 * How Memnox reaches an agent, kept apart from the job it does. The kind and the mediation are
 * read off what this machine can see in front of the agent, and never taken from the agent.
 */
declare const CONNECTION_KIND: {
    /** Its own hook, the interceptors, the shims or the proxy, all on this machine. */
    readonly RUNTIME_HOOK: "runtime_hook";
    /** Only the MCP servers it starts go through Memnox, as for Claude Desktop. */
    readonly RUNTIME_MCP_PROXY: "runtime_mcp_proxy";
    /** `@memnox/guard` wrapped round its tools in its own code. */
    readonly GUARD: "guard";
    /** The cloud gateway in front of its calls. */
    readonly GATEWAY: "gateway";
    /** It speaks to Memnox over MCP and reports what it does. */
    readonly MCP: "mcp";
    /** Found here with nothing in front of it, so it is only seen. */
    readonly OBSERVED: "observed";
};
type ConnectionKind = (typeof CONNECTION_KIND)[keyof typeof CONNECTION_KIND];
declare const MEDIATION: {
    /** Its calls pass through Memnox before they run. */
    readonly INTERPOSED: "interposed";
    /** It asks Memnox and could act without asking. */
    readonly ADVISORY: "advisory";
    /** Memnox sees what it did after it did it, or only that it is here. */
    readonly OBSERVED: "observed";
};
type Mediation = (typeof MEDIATION)[keyof typeof MEDIATION];
declare const CONNECTION_STATUS: {
    /** A session of it is working now. */
    readonly LIVE: "live";
    /** Found on the last scan with nothing running. */
    readonly IDLE: "idle";
    /** Bound once and not found any more. */
    readonly GONE: "gone";
};
type ConnectionStatus = (typeof CONNECTION_STATUS)[keyof typeof CONNECTION_STATUS];
interface AgentConnection {
    id: string;
    profileId: string;
    kind: ConnectionKind;
    agentKind?: string;
    /** The ledger key, `agt_<kind>`, which a binding never changes. */
    agentId?: string;
    mediation: Mediation;
    firstSeen: string;
    lastSeen: string;
    status: ConnectionStatus;
    /** How sure Memnox is of each capability through this connection, computed and never claimed. */
    levels?: CapabilityLevels;
}
/** A profile a person bound to an agent: the one thing about a connection that is stored. */
interface ProfileBinding {
    profileId: string;
    boundAt: string;
}
/** By agent id. An agent absent here answers to its default profile. */
type ProfileBindings = Readonly<Record<string, ProfileBinding>>;
/** What this machine knows of one detected agent, read off the scan, the hooks and its sessions. */
interface ConnectionEvidence {
    agentId: string;
    agentKind: string;
    /** What Memnox could hold it through: its own hook, or the servers it starts. */
    seam?: 'hook' | 'servers';
    /** Whether that seam is in place now. */
    held: boolean;
    /** Sessions of it working now. */
    running: number;
    firstSeen: string;
    lastSeen: string;
}
/** What a kind of connection can do, which is a fact about the kind and never a claim by the agent. */
declare function mediationOf(kind: ConnectionKind): Mediation;
/** A seam that is not in place yet holds nothing, so the agent is only seen until it is. */
declare function connectionKindOf(evidence: ConnectionEvidence): ConnectionKind;
/** The profile an agent works under: the one a person bound, or its default until they do. */
declare function profileIdFor(agentId: string, agentKind: string, bindings: ProfileBindings): string;
/** One connection per detected agent, and one gone connection per bound agent no longer found. */
declare function connectionsFor(found: readonly ConnectionEvidence[], bindings: ProfileBindings): AgentConnection[];

/**
 * How sure Memnox is of each thing an agent does, computed from what holds it and what was proved,
 * never claimed. Only a seam that refused a planted test is enforced; anything else says less.
 */
declare const CAPABILITY_LEVEL: {
    /** A seam in front of it refused a planted test: "Memnox stops this". */
    readonly ENFORCED: "enforced";
    /** Something is in front of it with no test passed: "Memnox checks this". */
    readonly MEDIATED: "mediated";
    /** The agent asks Memnox and could act without asking: "The agent asks Memnox". */
    readonly ADVISORY: "advisory";
    /** Seen in the record with nothing in front of it: "Memnox only sees this". */
    readonly OBSERVED: "observed";
    /** No evidence at all: "Outside Memnox". */
    readonly NONE: "none";
};
type CapabilityLevel = (typeof CAPABILITY_LEVEL)[keyof typeof CAPABILITY_LEVEL];
/** The seams enforcement is broken down by, each the surface a proof names. */
declare const ENFORCEMENT_SEAM: {
    readonly SHELL: "shell";
    readonly FILES: "filesystem";
    readonly GIT: "git";
    readonly NETWORK: "network";
    readonly BROWSER: "browser";
    readonly MCP: "mcp";
};
type EnforcementSeam = (typeof ENFORCEMENT_SEAM)[keyof typeof ENFORCEMENT_SEAM];
/** The strategy's seven capabilities, enforcement by seam. */
interface CapabilityLevels {
    context: CapabilityLevel;
    instructions: CapabilityLevel;
    tools: CapabilityLevel;
    activity: CapabilityLevel;
    coordination: CapabilityLevel;
    approval: CapabilityLevel;
    enforcement: Record<EnforcementSeam, CapabilityLevel>;
}
/** What one connection's levels are read from. */
interface LevelEvidence {
    connection: Pick<AgentConnection, 'kind' | 'mediation'>;
    /** This agent's line of the last `memnox doctor --prove`, where one ran. */
    proof?: AgentProof;
    /** That run's result per seam. */
    seams?: readonly SeamProof[];
    /** The enforcement path that proof ran against, as its record keeps it. */
    proofDigest?: string;
    /** The enforcement path installed now; a proof counts only while the two match. */
    currentDigest?: string;
    /** The ledger holds something this agent did. */
    seen: boolean;
}
declare function levelsOf(evidence: LevelEvidence): CapabilityLevels;
/** Every capability at none, which is what a profile with no agent behind it shows. */
declare function noLevels(): CapabilityLevels;
/**
 * A profile is only as sure as its weakest connection, so one unguarded agent under a job is never
 * hidden by a guarded one. Gone connections are left out; with none left, the profile is outside Memnox.
 */
declare function profileLevelsOf(connections: readonly Pick<AgentConnection, 'status' | 'levels'>[]): CapabilityLevels;

/**
 * The MCP Hub: servers declared once on this machine and handed to the agents a person
 * chose. The hub is the source of truth for the entries it wrote and for nothing else,
 * so a server a person configured by hand is shown as found and never rewritten.
 */
declare const HUB_VERSION = 1;
declare const HUB_TRANSPORT: {
    readonly STDIO: "stdio";
    readonly HTTP: "http";
};
type HubTransport = (typeof HUB_TRANSPORT)[keyof typeof HUB_TRANSPORT];
interface HubServer {
    name: string;
    description?: string;
    transport: HubTransport;
    /** On stdio: the server's own launch line, which the hub puts behind the proxy. */
    command?: string;
    args?: string[];
    /** On http: where the server answers. */
    url?: string;
    /** On http: sent with every request; a credential is written as `memnox-secret:<name>` and resolved by the proxy. */
    headers?: Record<string, string>;
    /** Plain values, written into the agent's config as they are. */
    env: Record<string, string>;
    /** Env name to secret name: only a reference reaches the config, the value stays in the OS store. */
    secrets: Record<string, string>;
}
interface HubAssignment {
    server: string;
    agent: DiscoveredAgentKind;
    /** The repository it is given in, as an absolute path, written to the agent's project config; absent is every project. */
    project?: string;
}
/** What the hub last wrote into one config, so a later hand edit reads as drift rather than ours. */
interface HubWritten {
    path: string;
    server: string;
    digest: string;
    /** The repository whose config this is, so the line is taken back once nothing is given there. */
    project?: string;
}
interface Hub {
    version: typeof HUB_VERSION;
    servers: HubServer[];
    assignments: HubAssignment[];
    written: HubWritten[];
}
declare function emptyHub(): Hub;
/** Every reason this server cannot be written, in the words a form shows; empty when it can. */
declare function hubServerProblems(server: HubServer): string[];
/** Why a remote server cannot be reached at this address, or undefined when it can. */
declare function remoteAddressProblem(url: string): string | undefined;
/** Every secret a server names, in its environment and inside its headers, each once. */
declare function secretsOfServer(server: HubServer): string[];
/** The agents a server is given to, in the order they were chosen. */
declare function agentsOf(hub: Hub, server: string): DiscoveredAgentKind[];
/**
 * The servers one agent is given in its own config, or with a repository, in that repository's
 * config only: a server given in one project is never written where every project reads it.
 */
declare function serversFor(hub: Hub, agent: DiscoveredAgentKind, project?: string): HubServer[];
/** Whether an agent has the server in this repository, given there or in every project. */
declare function hasServerIn(hub: Hub, assignment: Required<HubAssignment>): boolean;
/** Every repository the hub gives a server in or still has a line in, so each project config is kept in step. */
declare function projectsOf(hub: Hub): string[];
/** The hub with this server added or replaced by name, leaving its assignments as they were. */
declare function withServer(hub: Hub, server: HubServer): Hub;
/** The hub without this server or any of its assignments. Its written entries are removed by the next sync. */
declare function withoutServer(hub: Hub, name: string): Hub;
/** The hub with one assignment turned on or off; turning on twice is the same as once. */
declare function withAssignment(hub: Hub, assignment: HubAssignment, on: boolean): Hub;
/** A widening change the person signs before it holds: a server added or replaced, or given to one more agent. */
type HubChange = {
    put: HubServer;
} | {
    assign: HubAssignment;
};
declare function withChange(hub: Hub, change: HubChange): Hub;

/**
 * The MCP Hub as every screen reads and changes it: servers declared once and handed to agents.
 * No method here ever carries a secret's value back, only whether one is held.
 */
declare const MCP_HUB_METHOD: {
    /** Servers, agents, and what each agent's config holds that the hub did not write. */
    readonly HUB: "mcp-hub";
    /** Adds or replaces a server; widening, so it becomes a proposal the person signs. */
    readonly SERVER_PUT: "mcp-server-put";
    /** Takes a server away from the hub and from every agent it was given to. */
    readonly SERVER_REMOVE: "mcp-server-remove";
    /** Gives a server to an agent, signed, or takes it away, unsigned. */
    readonly ASSIGN: "mcp-assign";
    /** Takes a server the person configured themselves into the hub, for that same agent. */
    readonly IMPORT: "mcp-import";
    /** Writes what the hub says into every agent's config it can write. */
    readonly SYNC: "mcp-sync";
    /** Asks one server for its tools, on request and never on a timer. */
    readonly TEST: "mcp-test";
    /** Keeps a credential in the OS store, typed on this machine and never sent from afar. */
    readonly SECRET_SET: "mcp-secret-set";
    readonly SECRET_REMOVE: "mcp-secret-remove";
};
declare const MCP_HEALTH: {
    readonly UNKNOWN: "unknown";
    readonly HEALTHY: "healthy";
    readonly ERROR: "error";
};
type McpHealthState = (typeof MCP_HEALTH)[keyof typeof MCP_HEALTH];
/** Whose a server is: the person's own on this machine, or the organization's, which is read only here. */
declare const MCP_SCOPE: {
    readonly PERSONAL: "personal";
    readonly ORGANIZATION: "organization";
};
type McpScope = (typeof MCP_SCOPE)[keyof typeof MCP_SCOPE];
interface McpToolSummary {
    name: string;
    description?: string;
}
/** What the last test found, kept until the next one. */
interface McpServerHealth {
    state: McpHealthState;
    checkedAt?: string;
    error?: string;
    tools?: McpToolSummary[];
}
interface McpHubServerView {
    name: string;
    /** An organization server is never edited, removed or reassigned on this machine. */
    scope: McpScope;
    description?: string;
    transport: HubTransport;
    command?: string;
    args?: string[];
    url?: string;
    /** Plain variables by name only, so a value pasted where a secret belonged is never read back. */
    envNames: string[];
    /** On http: the headers sent, by name only, for the same reason. */
    headerNames?: string[];
    /** Behind the proxy, so every call is ruled on and recorded. */
    governed: boolean;
    toolCount: number;
    tools?: McpToolSummary[];
    health: McpServerHealth;
    agents: string[];
    /** The agents given it in one repository only, each with that repository, so a screen names the project. */
    projects?: McpProjectAssignment[];
    /** Each secret the server names, and whether the OS store holds it. Never the value. */
    secretsHeld: Record<string, boolean>;
    callsThisWeek: number;
}
/** One agent given a server in one repository, by its absolute path. */
interface McpProjectAssignment {
    agent: string;
    project: string;
}
/** An agent with an MCP config on this machine, and where it lives. */
interface McpHubAgentView {
    agent: string;
    path: string;
}
/** One server line in one agent's config that the hub did not write, or that it wrote and a person changed. */
interface McpHubEntryView {
    agent?: string;
    path: string;
    name: string;
    /** On drifted: edited or removed. On skipped: why it was not written. */
    kind?: string;
    reason?: string;
}
interface McpHubView {
    servers: McpHubServerView[];
    agents: McpHubAgentView[];
    found: McpHubEntryView[];
    drifted: McpHubEntryView[];
    skipped: McpHubEntryView[];
}
/** What a sync changed, counted per kind, so a screen says it in a line. */
interface McpSyncSummary {
    added: number;
    updated: number;
    removed: number;
    /** Configs the sync wrote, each backed up first. */
    files: string[];
}
interface McpHubRequestFields {
    /** On SERVER_PUT: the server as the form filled it, secrets as names only, a header's as `memnox-secret:<name>`. */
    mcpServer?: HubServer;
    /** On SERVER_REMOVE, ASSIGN, IMPORT and TEST: the server, by name. */
    mcpServerName?: string;
    /** On ASSIGN and IMPORT: the agent, by its kind. */
    mcpAgent?: string;
    /** On ASSIGN: given when true, taken away when false. */
    mcpOn?: boolean;
    /** On SECRET_SET and SECRET_REMOVE: the secret, by name. */
    mcpSecret?: string;
    /** On SECRET_SET: the value, which goes straight to the OS store and is never written anywhere else. */
    mcpSecretValue?: string;
}
interface McpHubResponseFields {
    /** On HUB, and after every change, so a screen redraws from one answer. */
    mcpHub?: McpHubView;
    /** On TEST: what the server answered. */
    mcpHealth?: McpServerHealth;
    /** On SYNC, and after a change that wrote configs. */
    mcpSynced?: McpSyncSummary;
}

/**
 * A skill as Memnox keeps it, once, before it is written into any agent's own format: its
 * instructions, the files beside them, and a manifest saying what it needs and what it is.
 */
/**
 * Whose a skill is: the person's, under the Memnox home, a repository's, committed with it, or the
 * organization's, pulled with the bundle and never changed on this machine.
 */
declare const SKILL_SCOPE: {
    readonly PERSONAL: "personal";
    readonly PROJECT: "project";
    readonly ORGANIZATION: "organization";
};
type SkillScope = (typeof SKILL_SCOPE)[keyof typeof SKILL_SCOPE];
/** The instructions every agent format starts from. */
declare const SKILL_INSTRUCTIONS = "SKILL.md";
/** The manifest, kept beside the instructions and left out of the folder digest it states. */
declare const SKILL_MANIFEST = "skill.toml";
/** What a skill says it needs to do its work, each a list of patterns. */
interface SkillPermissions {
    /** Paths it reads or writes outside its working folder. */
    filesystem: string[];
    /** Hosts it reaches. */
    network: string[];
    /** Command line tools it runs, by binary. */
    commands: string[];
}
interface SkillManifest {
    name: string;
    version: string;
    publisher?: string;
    description: string;
    category?: string;
    /** The folder digest the publisher stated; what holds a skill is the digest somebody accepted. */
    digest: string;
    /** Other skills it builds on, by name. */
    dependencies: string[];
    /** MCP servers it calls, by name. */
    mcpServers: string[];
    /** The agent tools it is granted, such as Bash or Read. */
    tools: string[];
    permissions: SkillPermissions;
    /** The agents it was written for, by kind; empty is any. */
    agents: string[];
}
/** One file beside the instructions, by its path inside the skill folder. */
interface SkillFile {
    path: string;
    bytes: Uint8Array;
}
interface CanonicalSkill {
    manifest: SkillManifest;
    instructions: string;
    /** Every other file, never the instructions or the manifest. */
    files: SkillFile[];
}
/** As many files as a skill reasonably carries, so a folder cannot fill the disk of every agent. */
declare const MOST_SKILL_FILES = 200;
declare const MOST_SKILL_BYTES: number;
declare function isSkillName(name: string): boolean;
/** A name somebody gave a skill elsewhere, made into one every agent folder takes. */
declare function skillNameOf(raw: string): string;
/** A path inside the folder that stays inside it, with no way up and no absolute start. */
declare function isInsideFolder(path: string): boolean;
/** Every reason this skill cannot be kept, in the words a form shows; empty when it can. */
declare function skillProblems(skill: CanonicalSkill): string[];
/** Ordered by their numbers, so 1.10.0 comes after 1.9.0. */
declare function compareVersions(a: string, b: string): number;

/**
 * What could safely be handed over next, from what a person has already approved. Every
 * number is a count of something that happened, because a percentage cannot be checked.
 */
/** Interruptions as a share of all actions: above the first steered, below the second self-running. */
declare const ASSIST_ASK_RATE = 0.2;
declare const SUPERVISED_ASK_RATE = 0.02;
declare const AUTONOMY: {
    /** Watched, nothing enforced. Where every install starts. */
    readonly OBSERVE: "observe";
    /** Asked about the things that change something. */
    readonly ASSIST: "assist";
    /** Routine work runs; anything outward or destructive is held. */
    readonly SUPERVISED: "supervised";
    /** Runs on its own, inside a boundary somebody wrote. */
    readonly AUTONOMOUS: "autonomous";
    /** Runs on its own, and the boundary has stopped catching anything. */
    readonly TRUSTED: "trusted";
};
type AutonomyLevel = (typeof AUTONOMY)[keyof typeof AUTONOMY];
declare const AUTONOMY_ORDER: readonly AutonomyLevel[];
/** Identical yeses before the same question stops being worth asking. */
declare const PROMOTION_THRESHOLD = 5;
/** Actions in the window before the top two rungs can be claimed, since quiet is not proof. */
declare const MINIMUM_EVIDENCE = 50;
/** Targets one handed-over rule lists before the approvals read as a pattern nobody named. */
declare const MOST_HANDED_TARGETS = 20;
interface Delegation {
    action: string;
    /** Times a person said yes to this exact thing. */
    approvals: number;
    /** Times a person said no. One is enough to stop a recommendation. */
    denials: number;
    lastAt: string;
    /** The widest class it was ever recorded under, since a rule allows the action at its worst. */
    class: ToolClass;
    /**
     * What the yeses were about, distinct. A handed-over rule names these and no others, so
     * it allows what was approved rather than the action everywhere. Empty when none carried one.
     */
    targets: string[];
    /** What this could become, and never more than the class allows. */
    recommendation: AutonomyLevel;
    /** Why, in the words the screen prints. */
    because: string;
}
/**
 * What a person has decided, per action: an authorized `ask` is a yes and a `deny` a no.
 * An `allow` is a rule deciding, so counting it would promote what was never asked.
 */
declare function delegations(events: readonly MemnoxEvent[], threshold?: number): Delegation[];
/** The ones worth putting on a screen: a habit, and nothing arguing against it. */
declare function promotable(found: readonly Delegation[], threshold?: number): Delegation[];
/** How often somebody is interrupted, as a count: hours saved would be a number nobody can check. */
declare function interruptions(events: readonly MemnoxEvent[], since: string): {
    total: number;
    byAction: {
        action: string;
        count: number;
    }[];
};
/** Where this machine sits on the ladder, read off what is configured and seen rather than declared. */
declare function standingOf(input: {
    enforcing: boolean;
    rules: number;
    asksInWindow: number;
    actionsInWindow: number;
}): AutonomyLevel;
declare function describeLevel(level: AutonomyLevel): string;
/**
 * Whether one action may stop being asked about, and the sentence for why not, so a
 * screen and the command under it cannot disagree.
 */
type HandOverVerdict = {
    action: string;
    ready: true;
    delegation: Delegation;
} | {
    action: string;
    ready: false;
    because: string;
};
declare function handOverVerdict(action: string, found: readonly Delegation[], threshold?: number): HandOverVerdict;
/** The rows on a screen that `--allow` would actually take, so neither names the other wrongly. */
declare function handable(each: Delegation, threshold?: number): boolean;
/** The rule's own words for how far a handed-over allow reaches, so the file says it too. */
declare function describeHandedReach(each: Delegation): string;

/**
 * What the Mac puts on a card for the person to read before they answer: a rule and where it
 * could hold, and a message drafted for their mail. Kept apart from the socket protocol, which
 * carries them, because each is a shape of its own that the Mac mirrors field for field.
 */

/** How a person asked: holding Control and Option says what follows is a rule they want in force. */
declare const ASK_INTENT: {
    readonly RULE: "rule";
    /** What they asked before a sign in, asked again by the Mac once it finished, never something said just now. */
    readonly RESUME: "resume";
};
type AskIntent = (typeof ASK_INTENT)[keyof typeof ASK_INTENT];
/** Where a rule can be put in force: every agent on this Mac, or only inside one repository. */
declare const RULE_SCOPE: {
    readonly MACHINE: "machine";
    readonly REPOSITORY: "repository";
    /** Offered to the workspace, where a second admin approves it and every agent that reads the bundle follows it. */
    readonly TEAM: "team";
};
type RuleScopeKind = (typeof RULE_SCOPE)[keyof typeof RULE_SCOPE];
/** One place a proposed rule can go; its id is the answer a CONFIRM signs, so the choice is covered by Touch ID. */
interface RuleScope {
    id: string;
    kind: RuleScopeKind;
    /** "This Mac", or the repository's folder name. */
    label: string;
    /** The repository's folder, on a repository scope. */
    folder?: string;
    /** The one the person most likely meant, picked on the card until they choose another. */
    suggested?: boolean;
}
/** A proposed rule as the Mac shows it before it is confirmed: what it does, and where it could go. */
interface RuleDraft {
    /** The rule in one plain sentence: "Deny git push to main". */
    summary: string;
    effect: DecisionEffect;
    action: string;
    branches?: string[];
    targets?: string[];
    /** The agent kinds it is narrowed to; absent, it reaches every agent. */
    agents?: string[];
    /** The folders it holds in, as wildcards; absent, it holds everywhere. */
    workingDirectories?: string[];
    /** What the action does, such as read, write, destructive or communication. */
    classes?: string[];
    reason: string;
    scopes: RuleScope[];
}
/** Whether a drafted message starts a thread or answers one. */
declare const DRAFT_MODE: {
    readonly COMPOSE: "compose";
    readonly REPLY: "reply";
};
type DraftMode = (typeof DRAFT_MODE)[keyof typeof DRAFT_MODE];
/** The mail services a draft can go out through, once Memnox Cloud has connected one. */
declare const MAIL_SERVICE: {
    readonly GMAIL: "gmail";
};
type MailService = (typeof MAIL_SERVICE)[keyof typeof MAIL_SERVICE];
/** A message the person's connected mail account would send, shown whole on the Mac before anything is sent. */
interface MailDraft {
    service: MailService;
    mode: DraftMode;
    to: string[];
    cc?: string[];
    subject?: string;
    body: string;
    /** On a reply, how many messages the thread already holds. */
    thread?: number;
}

/**
 * The Policy Studio as every screen reads and changes it: the rules in force and where each came
 * from, a rule proposed field by field, a dry run, packs, and how far the agents have been let go.
 */
declare const POLICY_METHOD: {
    /** Every rule in force on this machine, with where it came from and what would not load. */
    readonly POLICY_RULES: "rules";
    /** A rule filled in on a form; it holds only once the person signs the proposal it raises. */
    readonly RULE_PROPOSE: "rule-propose";
    /** Removing a person's rule: an allow goes at once, a deny or an ask waits on a signature. */
    readonly RULE_REMOVE: "rule-remove";
    /** One action ruled on against the rules in force, recording and changing nothing. */
    readonly RULE_TEST: "rule-test";
    /** The rules a person added here, as TOML text. */
    readonly RULES_EXPORT: "rules-export";
    /** A pack of rules as TOML, each turned into its own signed proposal. */
    readonly RULE_PACK_IMPORT: "rule-pack-import";
    /** The packs Memnox ships, each offered whole and imported through RULE_PACK_IMPORT. */
    readonly RULE_PACKS: "rule-packs";
    /** What could be handed over, what the autopilot holds, and where the machine stands. */
    readonly PROGRESS: "progress";
    /** Takes one autopilot grant back at once, since that only narrows. */
    readonly AUTOPILOT_REVOKE: "autopilot-revoke";
};
/** Where a rule in force came from. */
declare const RULE_SOURCE: {
    /** A person added it on this machine, by voice, a form or a hand over. */
    readonly PERSON: "person";
    /** A rule file in a repository, the person's to edit and commit. */
    readonly FILE: "file";
    /** Published by the workspace and pulled here; nothing on this machine loosens it. */
    readonly WORKSPACE: "workspace";
    /** The baseline setup wrote. */
    readonly DEFAULT: "default";
    /** Handed to one agent by the autopilot, for a while. */
    readonly AUTOPILOT: "autopilot";
    /** Allowed for a while with `memnox allow`. */
    readonly ALLOWANCE: "allowance";
    /** A pause or a freeze in force, which ends on its own. */
    readonly FREEZE: "freeze";
    /** Read out of the person's notes, confirmed in Learn and signed; it names where it was read. */
    readonly EXTRACTED: "extracted";
};
type RuleSource = (typeof RULE_SOURCE)[keyof typeof RULE_SOURCE];
/** What a rule matches; an absent list matches anything. */
interface PolicyRuleMatch {
    actions: string[];
    targets?: string[];
    agents?: string[];
    workingDirectories?: string[];
    classes?: string[];
    branches?: string[];
}
interface PolicyRuleView {
    name: string;
    effect: DecisionEffect;
    match: PolicyRuleMatch;
    reason?: string;
    /** The rule in one plain sentence, to read before the fields. */
    sentence: string;
    source: RuleSource;
    /** The file it was read from, where it lives in one. */
    file?: string;
    /** On a workspace rule: who decided it, and when. */
    decidedBy?: string;
    decidedAt?: string;
    /** On an extracted rule: where it was read, as `path#heading` or a link. */
    evidenceRefs?: string[];
    /** When it ends on its own, for a grant, an allowance or a freeze. */
    until?: string;
    /** Only a rule a person added on this machine, which is the only kind a screen removes. */
    editable: boolean;
}
/** A rule file that is there and will not load, so its rules are not in force. */
interface PolicyLoadProblem {
    file: string;
    issues: string[];
}
interface PolicyRulesView {
    rules: PolicyRuleView[];
    problems: PolicyLoadProblem[];
    /** Registered files that are gone. */
    missing: string[];
}
/** A rule as a form fills it in, before the daemon reads it back and offers where it holds. */
type RuleDraftInput = Omit<RuleDraft, 'summary' | 'scopes'>;
/** One action to rule on, the way `memnox policy test` takes it. */
interface RuleTestInput {
    /** A command line, or an action named outright such as `git.push`. */
    action: string;
    target?: string;
    agent?: string;
    workingDirectory?: string;
}
interface RuleVerdictView {
    effect: DecisionEffect;
    reason: string;
    /** The rule that decided, by name; absent when the default did. */
    rule?: string;
    /** What to do instead, where the rule names a way forward. */
    instead?: string;
}
/** An action a person approved often enough, with nothing arguing against handing it over. */
interface ProgressReady {
    action: string;
    approvals: number;
    targets: string[];
    because: string;
}
/** Approved, never refused, and not yet often enough. */
interface ProgressAlmost {
    action: string;
    approvals: number;
    /** Approvals still to go before it is ready. */
    needed: number;
}
/** A grant the autopilot made and that still stands. */
interface ProgressGrant {
    id: string;
    actions: string[];
    targets: string[];
    agents: string[];
    since: string;
    until: string;
    says: string;
}
/** Where the machine stands on the autonomy ladder, and what the next rung asks for. */
interface ProgressLadder {
    level: AutonomyLevel;
    says: string;
    rungs: AutonomyLevel[];
    next?: AutonomyLevel;
    /** What the record has to show before the next rung, in a sentence. */
    needs?: string;
    actionsThisWeek: number;
    asksThisWeek: number;
    /** Actions in a week before the top two rungs can be claimed. */
    minimumEvidence: number;
}
/** One week in counts, never hours saved. */
interface ProgressWeek {
    from: string;
    asked: number;
    /** Allowed by an autopilot grant rather than by a person. */
    answeredByAutopilot: number;
    /** Grants the autopilot made in the week. */
    handedOver: number;
}
interface ProgressView {
    ready: ProgressReady[];
    almost: ProgressAlmost[];
    grants: ProgressGrant[];
    autopilotOn: boolean;
    ladder: ProgressLadder;
    thisWeek: ProgressWeek;
    lastWeek: ProgressWeek;
}
/** A pack Memnox ships, with its TOML to hand straight to RULE_PACK_IMPORT. */
interface RulePackView {
    /** The file it ships as, without its extension, which stays the same between releases. */
    id: string;
    name: string;
    description: string;
    ruleCount: number;
    toml: string;
}
interface PolicyRequestFields {
    /** On RULE_PROPOSE. */
    ruleDraft?: RuleDraftInput;
    /** On RULE_REMOVE: the rule, by name. */
    ruleName?: string;
    /** On RULE_TEST. */
    ruleTest?: RuleTestInput;
    /** On RULE_PACK_IMPORT: the pack as TOML text. */
    rulePack?: string;
    /** On AUTOPILOT_REVOKE: the grant, by id. */
    grantId?: string;
}
interface PolicyResponseFields {
    /** On POLICY_RULES, and after every change, so a screen redraws from one answer. */
    policyRules?: PolicyRulesView;
    /** On RULE_PROPOSE: the rule read back, with where it could hold. */
    ruleProposed?: RuleDraft;
    /** On RULE_TEST. */
    ruleVerdict?: RuleVerdictView;
    /** On RULES_EXPORT. */
    rulesToml?: string;
    /** On RULE_PACK_IMPORT: one proposal per rule, each confirmed on its own. */
    packProposed?: string[];
    /** On PROGRESS and AUTOPILOT_REVOKE. */
    progress?: ProgressView;
    /** On RULE_PACKS. */
    rulePacks?: RulePackView[];
}

/**
 * The Skills Hub: skills kept once and handed to the agents a person chose. A skill whose folder
 * no longer matches what somebody accepted is held, and handed out only once it is accepted again.
 */
declare const SKILLS_HUB_VERSION = 1;
/** A version somebody accepted, kept so a later one is compared with it and an older one can come back. */
interface AcceptedSkillVersion {
    version: string;
    digest: string;
    tools: string[];
    /** Command line tools its text names, which is evidence of what it runs. */
    reaches: string[];
    acceptedAt: string;
}
/** Where a skill is handed to one agent: the home folder, or one repository. */
interface SkillAssignment {
    agent: DiscoveredAgentKind;
    project?: string;
}
interface HubSkill {
    name: string;
    scope: SkillScope;
    /** On a project skill: the repository it lives in. */
    project?: string;
    /** The version handed out. */
    current: string;
    enabled: boolean;
    /** Oldest first. */
    accepted: AcceptedSkillVersion[];
    assignments: SkillAssignment[];
    updatedAt: string;
}
/** What the hub last wrote for one skill in one agent, so only its own files are ever touched again. */
interface SkillWritten {
    skill: string;
    agent: DiscoveredAgentKind;
    /** The home folder or the repository it was written under. */
    root: string;
    /** Relative to the root: the folder, or the one file. */
    path: string;
    /** On a folder: every file in it that is ours, relative to it. */
    files?: string[];
    markerFile?: string;
}
interface SkillsHub {
    version: typeof SKILLS_HUB_VERSION;
    skills: HubSkill[];
    written: SkillWritten[];
}
/** A widening change the person signs before it holds. */
type SkillsChange = {
    accept: {
        name: string;
        version: string;
        digest: string;
    };
} | {
    assign: {
        name: string;
    } & SkillAssignment;
} | {
    rollback: {
        name: string;
        version: string;
        digest: string;
    };
};
declare function emptySkillsHub(): SkillsHub;
declare function skillNamed(hub: SkillsHub, name: string): HubSkill | undefined;
/** The hub with this skill added or replaced by name. */
declare function withSkill(hub: SkillsHub, skill: HubSkill): SkillsHub;
/** The hub without the skill of this name, which takes it out of every agent at its next sync. */
declare function withoutSkill(hub: SkillsHub, name: string): SkillsHub;
/** The skill with one assignment on or off; on twice is the same as once. */
declare function withSkillAssignment(skill: HubSkill, assignment: SkillAssignment, on: boolean): HubSkill;
/** The skill with this version recorded as accepted, replacing an earlier record of the same version. */
declare function withAccepted(skill: HubSkill, accepted: AcceptedSkillVersion): HubSkill;
/** What a skill's folder holds now, against the version last accepted. */
interface SkillStandingNow {
    standing: SkillStanding;
    /** Tools and commands it reaches now that the accepted version did not. */
    gained: string[];
    widened: boolean;
}
/**
 * Read through the same review a found skill gets: unchanged is known, a change is held, and a
 * change that reaches further is the one that needs a signature to accept.
 */
declare function skillStandingOf(skill: HubSkill, now: {
    digest: string;
    tools: string[];
    reaches: string[];
}): SkillStandingNow;
/** What a skill's text names, read the way a found skill is read. */
declare function reachesOf(skill: CanonicalSkill, binaries: readonly string[]): string[];
/**
 * What a skill declares it needs, as rules a person signs for the agents it is given to. A skill
 * is instructions rather than a boundary, so what it does beyond these is ruled on as usual.
 */
declare function needsOf(skill: CanonicalSkill, agents: readonly string[]): RuleDraftInput[];

/**
 * The Skills Hub as every screen reads and changes it: skills kept once, written into each agent's
 * own format, and held when their folder no longer matches what somebody accepted.
 */
declare const SKILLS_METHOD: {
    /** Skills, the agents that take them, and skills found on this machine to import. */
    readonly SKILLS_HUB: "skills-hub";
    /** Takes a skill found in an agent's folder into the hub, its files with it. */
    readonly SKILL_IMPORT: "skill-import";
    /** Adds a skill or a new version; one reaching further than the accepted version waits on a signature. */
    readonly SKILL_PUT: "skill-put";
    /** Gives a skill to an agent, signed, or takes it away, unsigned. */
    readonly SKILL_ASSIGN: "skill-assign";
    /** Takes a skill out of every agent at once, keeping its assignments for later. */
    readonly SKILL_DISABLE: "skill-disable";
    /** Hands a disabled skill back to the agents it was given to, as accepted. */
    readonly SKILL_ENABLE: "skill-enable";
    /** Writes what the hub says into every agent it can write. */
    readonly SKILL_SYNC: "skill-sync";
    /** Hands out an older accepted version again; signed where it reaches further than the current one. */
    readonly SKILL_ROLLBACK: "skill-rollback";
    /** Accepts a held skill's folder as it is now; signed where it reaches further. */
    readonly SKILL_ACCEPT: "skill-accept";
    /** Takes a skill out of the hub and every agent at once, its kept versions with it, since that only narrows. */
    readonly SKILL_REMOVE: "skill-remove";
    /** How often each skill was used lately, and how often what ran inside it failed or was refused. */
    readonly SKILL_STATS: "skill-stats";
    /** Adds one line to a skill's fix backlog, which nothing reads until the person calibrates it. */
    readonly SKILL_NOTE: "skill-note";
    /** A suggested SKILL.md built from the backlog and the failures, a preview that changes nothing. */
    readonly SKILL_CALIBRATE: "skill-calibrate";
};
/** What one agent keeps of a skill once it is written in that agent's format. */
interface SkillCompatibility {
    agent: string;
    label: string;
    supported: boolean;
    /** What the agent's format cannot carry, in a sentence each; empty when nothing is lost. */
    loses: string[];
}
interface SkillVersionView {
    version: string;
    current: boolean;
    /** When somebody accepted it; absent for a version never accepted. */
    acceptedAt?: string;
    digest?: string;
}
/** Why a skill is held: its folder changed since it was accepted, or reaches further than it did. */
interface SkillHold {
    /** changed, widened, or new for a folder nobody accepted yet. */
    standing: string;
    /** Tools and commands it reaches now that the accepted version did not. */
    gained: string[];
    /** Accepting it needs the person's signature. */
    signed: boolean;
}
interface SkillAssignmentView {
    agent: string;
    /** A repository it is written into; absent is the home folder. */
    project?: string;
}
interface SkillPermissionsView {
    filesystem: string[];
    network: string[];
    commands: string[];
}
interface SkillView {
    name: string;
    scope: SkillScope;
    project?: string;
    category?: string;
    version: string;
    description: string;
    publisher?: string;
    enabled: boolean;
    /** The folder digest as it is now. */
    digest: string;
    /** Present only while it is held, and then nothing new of it is handed out. */
    held?: SkillHold;
    /** Each agent it is given to, once. */
    agents: string[];
    assignments: SkillAssignmentView[];
    compatibility: SkillCompatibility[];
    /** Oldest first. */
    versions: SkillVersionView[];
    updatedAt: string;
    /** Every file beside the instructions, by path. */
    files: string[];
    instructions: string;
    tools: string[];
    mcpServers: string[];
    permissions: SkillPermissionsView;
    dependencies: string[];
    /** Why its folder would not read, when it would not. */
    problems?: string[];
}
/** A skill or persona found in an agent's own folder, offered for import. */
interface FoundSkillView {
    id: string;
    name: string;
    agent: string;
    /** skill or agent. */
    kind: string;
    path: string;
    tools: string[];
    /** Its grant in words, as `memnox skills` says it. */
    grant: string;
    /** Already in the hub under this name. */
    imported: boolean;
}
/** An agent a skill can be written into, and whether it is installed here. */
interface SkillAgentView {
    agent: string;
    label: string;
    installed: boolean;
}
interface SkillsHubView {
    skills: SkillView[];
    found: FoundSkillView[];
    agents: SkillAgentView[];
}
/** What a sync changed, so a screen says it in a line. */
interface SkillsSyncSummary {
    written: number;
    removed: number;
    files: string[];
    /** Wanted somewhere and not written, with why. */
    skipped: {
        skill: string;
        agent: string;
        path: string;
        reason: string;
    }[];
}
/** A skill as a form fills it in; every list left out is empty. */
interface SkillDraft {
    name: string;
    version: string;
    description: string;
    category?: string;
    publisher?: string;
    instructions: string;
    /** Text files beside the instructions, by path inside the skill. */
    files?: {
        path: string;
        text: string;
    }[];
    tools?: string[];
    mcpServers?: string[];
    dependencies?: string[];
    agents?: string[];
    permissions?: Partial<SkillPermissionsView>;
}
/** One skill's use over the chats lately, read from the transcripts the runtime already reads. */
interface SkillStatsView {
    name: string;
    uses: number;
    /** Tool calls inside the skill's turn that ended in an error. */
    failures: number;
    /** Tool calls inside the skill's turn that a permission or a rule refused. */
    refusals: number;
    lastUsedAt?: string;
    /** The fix backlog, oldest first. */
    notes: string[];
    /** The first line of a few recent failures, newest first. */
    recentFailures: string[];
}
/** A suggested change to one skill, built from its backlog and failures and accepted through SKILL_PUT. */
interface SkillCalibration {
    name: string;
    /** The section the suggestion adds or replaces in the instructions. */
    section: string;
    before: string[];
    after: string[];
    /** The skill as SKILL_PUT takes it with the change in, its version moved on by one. */
    draft: SkillDraft;
    notes: number;
    failures: number;
}
interface SkillsRequestFields {
    /** On every change but IMPORT and PUT: the skill, by name. */
    skillName?: string;
    /** On ASSIGN: the agent, by kind. */
    skillAgent?: string;
    /** On ASSIGN: the repository it is written into; on PUT and IMPORT, where a project skill lives. */
    skillProject?: string;
    /** On ASSIGN: given when true, taken away when false. */
    skillOn?: boolean;
    /** On ROLLBACK: the version to hand out again. */
    skillVersion?: string;
    /** On IMPORT: the found skill, by id. */
    skillFoundId?: string;
    /** On PUT and IMPORT: personal or project. */
    skillScope?: SkillScope;
    /** On PUT. */
    skillDraft?: SkillDraft;
    /** On SKILL_NOTE: the one line to add to the backlog. */
    skillNote?: string;
}
interface SkillsResponseFields {
    /** On SKILLS_HUB, and after every change, so a screen redraws from one answer. */
    skillsHub?: SkillsHubView;
    /** On SYNC, and after a change that wrote agents' folders. */
    skillsSynced?: SkillsSyncSummary;
    /** On SKILL_STATS and SKILL_NOTE: every hub skill, used or not. */
    skillStats?: SkillStatsView[];
    /** On SKILL_CALIBRATE: absent where there is nothing in the backlog and nothing failed. */
    skillCalibration?: SkillCalibration;
}

/**
 * A project: one repository and what every agent opened in it is given. `.memnox/project.toml` is
 * committed so a team shares it; what is this machine's own stays under the Memnox home.
 */
/** Inside the repository, beside the code fingerprint and the hooks. */
declare const PROJECT_FILE: string;
/** Under the Memnox home: one folder per project, for what never leaves this machine. */
declare const PROJECTS_DIR = "projects";
/** Where what an agent learns in this project is kept and read from. */
declare const MEMORY_SCOPE: {
    /** Kept with the project, so every agent opened in it reads the same. */
    readonly PROJECT: "project";
    /** The person's own memory, shared across every project. */
    readonly PERSONAL: "personal";
    /** Nothing kept. */
    readonly NONE: "none";
};
type MemoryScope = (typeof MEMORY_SCOPE)[keyof typeof MEMORY_SCOPE];
interface ProjectManifest {
    name: string;
    /** Files whose text is the project's instructions, relative to the repository. */
    instructions: string[];
    /** MCP Hub servers, by name, given to every agent opened here. */
    servers: string[];
    /** Skills Hub skills, by name, written into every agent opened here. */
    skills: string[];
    /** The agents the project is opened with, by kind or profile id; empty is every agent seen working in it. */
    agents: string[];
    /** The rule file, relative to the repository. */
    policy?: string;
    memory: MemoryScope;
}
/** What opening a project hands its agents that they did not have, which the person signs. */
interface ProjectChange {
    projectId: string;
    root: string;
    servers: HubAssignment[];
    skills: ({
        name: string;
    } & SkillAssignment)[];
    /** The rule file put in force, absolute. */
    policy?: string;
}
/** The machine's own id for a repository, from its path, so two clones are two projects. */
declare function projectIdOf(root: string): string;
/** Checked before an id becomes a folder name, since a screen sends it. */
declare function isProjectId(id: string): boolean;
/** Every list empty, memory kept with the project. */
declare function emptyManifest(name: string): ProjectManifest;
declare function projectToml(manifest: ProjectManifest): string;
/** The manifest, or every reason it will not read; a list left out is a list with nothing in it. */
declare function parseProjectToml(text: string): ProjectManifest | {
    problems: string[];
};
/** Every path stays inside the repository, so a shared file cannot point an agent at the home folder. */
declare function manifestProblems(manifest: ProjectManifest): string[];

/**
 * Long and short term memory as layers any agent reads: MEMORY.md for every chat, the router file
 * that points each department at its own file, and the skills that say where live data is. A plan
 * is only a preview; it is written inside Memnox's fenced blocks once the person confirms that plan.
 */
declare const MEMORY_LAYERS_METHOD: {
    /** Each project's three layers as they stand: MEMORY.md, the router files, and the SKILL.md skills. */
    readonly MEMORY_LAYERS: "memory-layers";
    /** The proposed MEMORY.md index and router lines for one project, a preview that writes nothing. */
    readonly MEMORY_LAYERS_PLAN: "memory-layers-plan";
    /** Writes the plan the person confirmed, refused when the files changed since it was shown. */
    readonly MEMORY_LAYERS_APPLY: "memory-layers-apply";
    /** The last thirty days of chats: how often a cold cache was loaded again, and what keeping it warm saves. */
    readonly SESSION_COST: "session-cost";
};
/** Which of the three layers a file is. */
declare const MEMORY_LAYER: {
    /** MEMORY.md, read in every chat: one line per memory, each linked to its file. */
    readonly INDEX: "index";
    /** CLAUDE.md, AGENTS.md, GEMINI.md or Cursor's rules: one line per department. */
    readonly ROUTER: "router";
    /** One memory written as its own file, which the index links to. */
    readonly MEMORY: "memory";
};
type MemoryLayer = (typeof MEMORY_LAYER)[keyof typeof MEMORY_LAYER];
/** MEMORY.md as it stands: whether it is there, how long, and how many of its lines link nowhere. */
interface MemoryIndexLayerView {
    /** Relative to the repository. */
    path: string;
    present: boolean;
    lines: number;
    /** Lines that say something and link to no file, which is what the index is meant to avoid. */
    unlinked: number;
}
/** One agent's router file as it stands. */
interface MemoryRouterLayerView {
    agent: string;
    /** Relative to the repository. */
    path: string;
    present: boolean;
    lines: number;
    chars: number;
    /** Folders of the repository that keep their own instruction file, each a department. */
    departments: string[];
    /** Of those, how many the router names. */
    routed: number;
}
/** A SKILL.md the project's agents read, and whether it says where live data is. */
interface MemorySkillLayerView {
    name: string;
    /** Relative to the repository. */
    path: string;
    /** It names a database, a table, a query or an address to read live data from. */
    liveData: boolean;
}
interface ProjectLayersView {
    name: string;
    /** The repository, absolute. */
    path: string;
    agents: string[];
    index: MemoryIndexLayerView;
    routers: MemoryRouterLayerView[];
    skills: MemorySkillLayerView[];
    /** What the router's block keeps when a chat compacts, as last written. */
    keep: string[];
}
/** What memory measured about itself; every field is absent where nothing was measured. */
interface MemoryValueView {
    /** The median of the recent searches on this machine, in milliseconds. */
    searchMedianMs?: number;
    /** How many searches that median is over. */
    searches?: number;
    /** Tokens agents did not read because a memory read answered in budgeted lines rather than whole, where measured. */
    contextTokensSaved?: number;
}
interface MemoryLayersView {
    projects: ProjectLayersView[];
    value: MemoryValueView;
}
/** One file a plan writes: its block before and after, by line, so a screen draws the change. */
interface MemoryLayerFilePlan {
    /** Relative to the repository. */
    path: string;
    layer: MemoryLayer;
    /** The agent that reads it, on a router file. */
    agent?: string;
    /** A whole file of ours rather than a block inside a person's. */
    whole: boolean;
    before: string[];
    after: string[];
    changed: boolean;
}
interface MemoryLayersPlan {
    /** The repository, absolute. */
    project: string;
    /** What the person confirms; apply refuses a plan whose digest no longer matches. */
    digest: string;
    files: MemoryLayerFilePlan[];
}
interface MemoryLayersApplied {
    written: string[];
    unchanged: string[];
}
/** One model's API prices in US dollars per million tokens. */
interface ModelPriceView {
    model: string;
    input: number;
    cacheWrite: number;
    cacheRead: number;
}
/** The last days of chats, read from the transcripts the runtime already reads; never a ping. */
interface SessionCostView {
    days: number;
    sessions: number;
    turns: number;
    /** Turns that loaded their whole context into the cache again after it went cold. */
    coldReloads: number;
    reloadedTokens: number;
    /** What those reloads cost at API prices; absent where a model's price is unknown. */
    reloadCostUsd?: number;
    /** What keeping each chat warm for the window would have saved, net of keeping it warm; absent likewise. */
    warmSavingUsd?: number;
    /** How long a chat would be kept warm, in hours. */
    warmHours: number;
    /** Models seen whose price is not in the table, so the totals say what they leave out. */
    unpricedModels: string[];
    prices: ModelPriceView[];
}
interface MemoryLayersRequestFields {
    /** On PLAN and APPLY, and to narrow MEMORY_LAYERS: the repository, absolute. */
    memoryLayersProject?: string;
    /** On PLAN and APPLY: one agent's router; absent is every agent of the project. */
    memoryLayersAgent?: string;
    /** On PLAN and APPLY: what the router keeps when a chat compacts, one line each. */
    memoryKeep?: string[];
    /** On APPLY: the digest of the plan the person confirmed. */
    memoryLayersDigest?: string;
}
interface MemoryLayersResponseFields {
    /** On MEMORY_LAYERS, and after APPLY. */
    memoryLayers?: MemoryLayersView;
    /** On PLAN. */
    memoryLayersPlan?: MemoryLayersPlan;
    /** On APPLY. */
    memoryLayersApplied?: MemoryLayersApplied;
    /** On SESSION_COST. */
    sessionCost?: SessionCostView;
}

/**
 * The community index as screens browse it: skills and rule packs from Memnox Cloud's marketplace
 * or a git repository's `index.json`. A download is checked against its digest before it is
 * written, and an install is only a skill held for acceptance or a pack's rules proposed.
 */
declare const INDEX_METHOD: {
    /** The index, filtered by words and kind, read fresh or from what was last read. */
    readonly INDEX_LIST: "index-list";
    /** Fetches one version, checks its digest, and holds the skill or proposes the pack's rules. */
    readonly INDEX_INSTALL: "index-install";
    /** Where the index is read from: a new one is a proposal the Mac signs, the marketplace again is at once. */
    readonly INDEX_SOURCE_SET: "index-source-set";
};
/** The source named by a word rather than a URL. */
declare const INDEX_SOURCE: {
    /** Memnox Cloud's marketplace, of the workspace this machine is on: the default. */
    readonly MARKETPLACE: "marketplace";
};
/** What a listing is, in the marketplace's own words. */
declare const INDEX_KIND: {
    readonly SKILL: "skill";
    readonly RULE_PACK: "rule_pack";
};
type IndexKind = (typeof INDEX_KIND)[keyof typeof INDEX_KIND];
interface IndexPublisherView {
    /** An organization or a member, as the marketplace says. */
    kind: string;
    name: string;
}
/** What a listing declares it needs, as its manifest in the index says; read before anything is installed. */
interface IndexNeedsView {
    /** Paths it reads or writes. */
    filesystem: string[];
    /** Hosts it reaches. */
    network: string[];
    /** Commands it runs. */
    commands: string[];
    /** MCP servers it uses, by name. */
    mcpServers: string[];
    /** Tools it asks its agent for, by name. */
    tools: string[];
}
/** One listing as a screen browses it. */
interface IndexEntryView {
    id: string;
    name: string;
    kind: IndexKind;
    description: string;
    category?: string;
    publisher: IndexPublisherView;
    license?: string;
    /** Agent kinds it supports; empty is every agent. */
    agents: string[];
    /** The newest version not marked unsafe, and the digest its content must match. */
    latest?: {
        version: string;
        digest: string;
    };
    /** Versions marked unsafe since they were published, which nothing installs. */
    yanked: string[];
    /** Every published version is marked unsafe, so the listing offers nothing to install. */
    unsafe: boolean;
    /** The version of this skill the Skills Hub holds here, where it holds one. */
    installed?: string;
    /** What it declares it needs; absent where the index carries no manifest for it. */
    needs?: IndexNeedsView;
    /** What a person should know before installing it, each in a sentence; empty where nothing stands out. */
    warnings: string[];
}
interface CommunityIndexView {
    /** Where the index was read from. */
    source: string;
    /** Whether that is a Memnox Cloud marketplace, the default, rather than an index somebody named. */
    marketplace: boolean;
    /** When it was read; absent before it was ever read. */
    fetchedAt?: string;
    /** False where the index held more than it carries. */
    complete: boolean;
    entries: IndexEntryView[];
    /** Why what is shown is not fresh, or why there is nothing, in a sentence. */
    said?: string;
}
/** What an install did, so a screen says it in a line and opens what waits on the person. */
interface IndexInstalled {
    id: string;
    name: string;
    kind: IndexKind;
    version: string;
    digest: string;
    /** For a pack: one proposal per rule, each signed on its own. */
    proposed: string[];
    /** For a skill: it is in the Skills Hub, held until the person accepts it. */
    held: boolean;
    said: string;
}
interface IndexRequestFields {
    /** On INDEX_LIST: words, each found in the name or the description. */
    indexQuery?: string;
    /** On INDEX_LIST: only skills, or only rule packs. */
    indexKind?: IndexKind;
    /** On INDEX_LIST: read again now rather than from what was last read. */
    indexRefresh?: boolean;
    /** On INDEX_SOURCE_SET, from this machine only: an https URL to an `index.json`, or `marketplace`; absent is `marketplace`. */
    indexSource?: string;
    /** On INDEX_INSTALL: the listing, by id or by name. */
    indexName?: string;
    /** On INDEX_INSTALL: the version; absent is the newest not marked unsafe. */
    indexVersion?: string;
}
interface IndexResponseFields {
    /** On INDEX_LIST, and after an install. */
    communityIndex?: CommunityIndexView;
    /** On INDEX_INSTALL. */
    indexInstalled?: IndexInstalled;
}

/**
 * What this machine learned from the sources a person pointed it at: candidates a model read out
 * of them, facts a person confirmed, and the evidence each one carries. Nothing here promotes
 * itself: a model proposes and only a person's confirm makes a fact verified.
 */
declare const MEMORY_STATUS: {
    /** Read out of a source, or suggested by an agent, and confirmed by nobody yet. */
    readonly CANDIDATE: "candidate";
    /** A person confirmed it. */
    readonly VERIFIED: "verified";
    /** A newer confirmed fact restates it. */
    readonly SUPERSEDED: "superseded";
    /** A person said no, which is remembered so it is never proposed again. */
    readonly REJECTED: "rejected";
    /** Every passage it was read from changed or went away. */
    readonly OUTDATED: "outdated";
    /** Confirmed, and another confirmed fact says the opposite, so a person decides between them. */
    readonly CONFLICTING: "conflicting";
};
type MemoryStatus = (typeof MEMORY_STATUS)[keyof typeof MEMORY_STATUS];
declare const MEMORY_STATUSES: readonly string[];
/** What a candidate is: something true or decided, a way of working, or a rule to enforce. */
declare const MEMORY_KIND: {
    /** A fact or a decision. */
    readonly FACT: "fact";
    readonly CONVENTION: "convention";
    /** Becomes a signed rule proposal once a person confirms it. */
    readonly RULE: "rule";
};
type MemoryKind = (typeof MEMORY_KIND)[keyof typeof MEMORY_KIND];
declare const MEMORY_KINDS: readonly string[];
/** Where an item came from: a model reading a source, an agent's suggestion, or a person. */
declare const MEMORY_ORIGIN: {
    readonly EXTRACTED: "extracted";
    readonly AGENT: "agent";
    readonly PERSON: "person";
};
type MemoryOrigin = (typeof MEMORY_ORIGIN)[keyof typeof MEMORY_ORIGIN];
/** The rule half of a rule candidate, in the engine's own effects and patterns. */
interface MemoryRule {
    effect: DecisionEffect;
    actions: string[];
    targets?: string[];
    agents?: string[];
    reason: string;
}
/** One place an item was read from: a file and the heading it sat under, or a link. */
interface MemoryEvidence {
    sourceId: string;
    /** The file, relative to the source, or the document's own id at an API. */
    document: string;
    heading?: string;
    url?: string;
    /** The passage's digest when it was read, so a change to it is seen. */
    digest: string;
    /** The passage changed or went away since. */
    stale: boolean;
}
interface MemoryItem {
    id: string;
    kind: MemoryKind;
    /** Verbatim as the model or the agent wrote it, never reworded here. */
    statement: string;
    subject: string;
    status: MemoryStatus;
    scope: MemoryScope;
    /** The repository a project item belongs to. */
    project?: string;
    origin: MemoryOrigin;
    /** The source it was read from, absent for an agent's suggestion. */
    sourceId?: string;
    /** Read from a source outside the person's own trust. */
    tainted: boolean;
    /** The extractor's own confidence, never the person's. */
    confidence?: number;
    /** Who suggested it, for an agent's suggestion. */
    suggestedBy?: string;
    rule?: MemoryRule;
    /** An earlier item it restates in other words. */
    duplicateOf?: string;
    /** The signed rule proposal a confirm raised and that is not settled yet. */
    proposalId?: string;
    createdAt: string;
    decidedAt?: string;
    decidedBy?: string;
    evidence: MemoryEvidence[];
}
/** Statuses an agent is handed as settled. */
declare const SETTLED_STATUSES: readonly MemoryStatus[];
/** Statuses still waiting on a person, which the Learn queue shows. */
declare const OPEN_STATUSES: readonly MemoryStatus[];
/** Statuses a changed passage can still move to outdated; the rest already said their last word. */
declare const LIVE_STATUSES: readonly MemoryStatus[];
/** One key per wording, so a rejection holds against the same words read again anywhere. */
declare function statementKey(kind: string, statement: string): string;
/** The share of words two statements have in common, from 0 to 1. */
declare function wordOverlap(a: string, b: string): number;
/** The same thing in nearly the same words, which the queue shows as a duplicate rather than as news. */
declare function restates(a: string, b: string): boolean;
/**
 * Two confirmed facts about the same subject that say opposite things: close in their words and
 * one negated where the other is not. A heuristic, so it only ever flags for a person to decide.
 */
declare function disagrees(a: MemoryItem, b: MemoryItem): boolean;
/** An item whose every piece of evidence went stale says nothing current any more. */
declare function isOutdated(item: Pick<MemoryItem, 'evidence'>): boolean;
/** Where the evidence sits, as a person reads it: `notes/ops.md, "Releases"`, or the link. */
declare function evidenceRef(evidence: Pick<MemoryEvidence, 'document' | 'heading' | 'url'>): string;

/**
 * One port over every place a person keeps what they know: a vault, a folder, agents' instruction
 * files, an export, an API or an MCP memory server. Each is read when the person asks or a file
 * changes, never on a timer, and every read is bounded.
 */
declare const MEMORY_SOURCE_KIND: {
    readonly OBSIDIAN: "obsidian";
    readonly MARKDOWN: "markdown";
    /** CLAUDE.md, AGENTS.md, GEMINI.md and .cursor/rules in one repository. */
    readonly INSTRUCTIONS: "instructions";
    readonly NOTION_EXPORT: "notion-export";
    readonly SUPERMEMORY: "supermemory";
    /** An MCP memory server in the hub, read through one of its tools. */
    readonly MCP: "mcp";
    /** What the person's agents read and wrote in one connected app through Memnox, kept on this machine only. */
    readonly APP_CALLS: "app-calls";
    /** What the person's agents read and wrote through one MCP server, kept on this machine only. */
    readonly MCP_CALLS: "mcp-calls";
};
type MemorySourceKind = (typeof MEMORY_SOURCE_KIND)[keyof typeof MEMORY_SOURCE_KIND];
declare const MEMORY_SOURCE_KINDS: readonly string[];
/** Files the person points at are their own; anything a third party wrote or exported is not. */
declare const SOURCE_TRUST: {
    readonly TRUSTED: "trusted";
    readonly TAINTED: "tainted";
};
type SourceTrust = (typeof SOURCE_TRUST)[keyof typeof SOURCE_TRUST];
/** Kept by Memnox itself from the calls agents make, so no form adds one and only Memnox writes them. */
declare const CALL_SOURCE_KINDS: readonly MemorySourceKind[];
declare function isCallSource(kind: string): boolean;
declare function trustOf(kind: MemorySourceKind): SourceTrust;
/** Whether the source lives on this machine's disk, which is what a file watcher can watch. */
declare function isFileSource(kind: MemorySourceKind): boolean;
/** A source as the person added it. A key is held in the OS store, and only its name is here. */
interface MemorySourceRecord {
    id: string;
    kind: MemorySourceKind;
    name: string;
    /** A folder, absolute, or the base URL of an API. */
    location: string;
    trust: SourceTrust;
    scope: MemoryScope;
    /** The repository a project source belongs to. */
    project?: string;
    /** The OS store entry holding the API key. */
    secret?: string;
    /** For an MCP source: the hub server and the tool that reads it. */
    server?: string;
    tool?: string;
    addedAt: string;
    lastReadAt?: string;
    /** Why the last read failed, when it did. */
    lastError?: string;
}
/** One document a source holds, and a stamp that moves when it changes. */
interface SourceDocumentRef {
    /** A path relative to the source, or the document's id at an API. */
    document: string;
    /** Modified time or version; compared, never parsed. */
    stamp: string;
}
/** Why a document a source holds was not read, so a read says what it passed over. */
declare const SKIP_REASON: {
    /** Past the bytes a note may have, so an attachment or a dump. */
    readonly TOO_LARGE: "too-large";
    /** Past the documents one source reads. */
    readonly PAST_LIMIT: "past-limit";
    /** Listed, then gone or not text when it was opened. */
    readonly UNREADABLE: "unreadable";
};
type SkipReason = (typeof SKIP_REASON)[keyof typeof SKIP_REASON];
interface SkippedDocument {
    document: string;
    reason: SkipReason;
}
/** A piece of a document under one heading, which is what a citation names. */
interface SourcePassage {
    document: string;
    heading?: string;
    /** A link to it, where the source has one. */
    url?: string;
    text: string;
    /** The agent whose call brought it in, for a source of agents' calls, so what it teaches is theirs to suggest. */
    by?: string;
}
interface SourceDocument {
    document: string;
    passages: SourcePassage[];
}
/** The port every source is read through. */
interface MemorySource {
    readonly kind: MemorySourceKind;
    readonly trust: SourceTrust;
    /** Every document there now, bounded. */
    list(): Promise<SourceDocumentRef[]>;
    /** One document split into passages; null when it is gone or unreadable. */
    read(ref: SourceDocumentRef): Promise<SourceDocument | null>;
    /** Those listed whose stamp moved past the one given, by document. */
    changedSince(seen: ReadonlyMap<string, string>): Promise<SourceDocumentRef[]>;
    /** What the last list left out and why; absent for a source that leaves nothing out. */
    skipped?(): SkippedDocument[];
}
/** The changed half of `list`, shared by every source since a stamp is only ever compared. */
declare function changedOf(source: Pick<MemorySource, 'list'>, seen: ReadonlyMap<string, string>): Promise<SourceDocumentRef[]>;

/**
 * What the workspace has settled, as this machine last pulled it, and the lookup that finds
 * the part a prompt or a path is about. The control plane hands over the whole set and never
 * ranks it, so the choosing happens here, by shared words, with every match naming its words.
 */
/** One settled thing, as the control plane's `GET :ws/memory` sends it. */
interface WorkspaceFact {
    id: string;
    /** decision, policy, authority, responsibility or relationship. */
    kind: string;
    statement: string;
    subject: string;
    scope?: string;
    /** The person it names: the owner, the approver, the party. */
    principal?: string;
    capability?: string;
    object?: string;
    sourceRef?: string;
    /** declared, authoritative or observed. */
    provenance?: string;
    /** Who confirmed it. */
    verifiedBy?: string;
    settledAt?: string;
}
/**
 * Something a connected tool said that nobody has approved, as the control plane sends it in
 * `unconfirmed`. Context an agent weighs and never a decision: no verdict reads it, and it is
 * its own type so a candidate cannot be handed to anything that takes a settled fact.
 */
interface WorkspaceCandidate {
    id: string;
    kind: string;
    statement: string;
    subject: string;
    scope?: string;
    principal?: string;
    /** Always `candidate`, kept so the file says what it is without its reader inferring it. */
    standing: 'candidate';
    approved: false;
    /** The connected tools it was read out of: slack, notion, linear. */
    sources: string[];
    /** Who said what it was read out of, as the tool names them. */
    saidBy?: string[];
    sourceRef?: string;
    /** True when anything it was read from came from outside the workspace's trust. */
    untrusted?: true;
    detectedAt?: string;
}
interface WorkspaceMemory {
    hash: string;
    facts: WorkspaceFact[];
    /** Read out of connected tools and approved by nobody; absent where there are none. */
    unconfirmed?: WorkspaceCandidate[];
    /** How many facts this machine is not cleared for, so a partial set is never read as whole. */
    withheld: number;
    /** When this machine last heard from the control plane about it. */
    syncedAt: string;
}
/** What is being looked up: words a person typed, and paths an agent is about to touch. */
interface FactQuery {
    words?: readonly string[];
    paths?: readonly string[];
}
/** A match, with the words it matched on, so why it was said is never a mystery. */
interface FactFound {
    fact: WorkspaceFact;
    matched: string[];
    /** True when it matched on what the fact is about rather than only on its wording. */
    onSubject: boolean;
}
/** A candidate a query reached, and the words that reached it. */
interface CandidateFound {
    candidate: WorkspaceCandidate;
    matched: string[];
}
/** The facts a query is about, those matched on their subject first. */
declare function factsAbout(memory: WorkspaceMemory, query: FactQuery): FactFound[];
/** The unapproved candidates a query is about, found exactly the way a settled fact is. */
declare function candidatesAbout(memory: WorkspaceMemory, query: FactQuery): CandidateFound[];
/**
 * The decisions a write to this path bears on, as ids, found the way a brief finds them.
 * Recorded on the write so the control plane can ask whoever answers for one to look, since
 * matching them again there would be the relevance layer it deliberately does not have.
 */
declare function decisionsBearingOn(memory: WorkspaceMemory, path: string): string[];
/** The newest facts, for a lookup that named nothing in particular. */
declare function newestFacts(memory: WorkspaceMemory, most: number): WorkspaceFact[];
/** One sentence an agent can cite: what was settled, who settled it, when, and where. */
declare function describeFact(found: FactFound): string;
/** The newest candidates, for a lookup that named nothing in particular. */
declare function newestCandidates(memory: WorkspaceMemory, most: number): WorkspaceCandidate[];
/**
 * One sentence that cannot be read as settled: it opens by saying nobody approved it and
 * names where it was read, so an agent quoting it quotes the warning too.
 */
declare function describeCandidate(candidate: WorkspaceCandidate): string;
/** Where a candidate was read and who said it, plus the untrusted warning where it applies. */
declare function candidateOrigin(candidate: WorkspaceCandidate): string;
/** Who confirmed it, when, and where it came from, in the words a person reads. */
declare function factOrigin(fact: WorkspaceFact): string;
/**
 * The shape the control plane sends, checked field by field, or null where it is not one.
 * A fact missing its id, statement or subject is dropped rather than guessed at.
 */
declare function parseWorkspaceMemory(value: unknown, syncedAt: string): WorkspaceMemory | null;
/** Lowercased words, camel case split, stop words and short words dropped, plurals folded. */
declare function termsOf(text: string): Set<string>;

/**
 * The workspace's memory graph as a screen draws it: what arrived from the connected tools, who said
 * it, and what the team settled out of it. Held only in memory, never written anywhere.
 */
/** What a node is, as a screen draws it. The cloud's other kinds (an agent, a path) are not memory. */
declare const WORKSPACE_NODE_KIND: {
    /** A connected tool things arrive through: slack, github, notion. */
    readonly SOURCE: "source";
    /** One thing that arrived: a message, an issue, an uploaded file, or an address several things link to. */
    readonly DOCUMENT: "document";
    /** A section of something long enough to have been cut. */
    readonly PASSAGE: "passage";
    /** A thread or a channel, holding the messages in it. */
    readonly CONVERSATION: "conversation";
    readonly PERSON: "person";
    /** An account its tool lists as an app, which posts like somebody and is never one. */
    readonly BOT: "bot";
    /** A team, a department or the company, as the directory names it. */
    readonly GROUP: "group";
    /** A rule set in force. */
    readonly POLICY: "policy";
    /** Something the team settled, in force. */
    readonly DECISION: "decision";
    /** Something a connected tool said that nobody approved. */
    readonly CANDIDATE: "candidate";
};
type WorkspaceNodeKind = (typeof WORKSPACE_NODE_KIND)[keyof typeof WORKSPACE_NODE_KIND];
/**
 * Where a decision stands. A machine is handed only what is in force and what waits, so a superseded
 * or a rejected fact never reaches one and has no word here.
 */
declare const WORKSPACE_NODE_STATUS: {
    readonly VERIFIED: "verified";
    readonly CANDIDATE: "candidate";
};
type WorkspaceNodeStatus = (typeof WORKSPACE_NODE_STATUS)[keyof typeof WORKSPACE_NODE_STATUS];
/** What one line says, each a field on the record. */
declare const WORKSPACE_LINK_KIND: {
    /** A tool, and the thing it delivered. */
    readonly CARRIES: "carries";
    /** A thing, and a passage or a message inside it. */
    readonly CONTAINS: "contains";
    /** Who wrote a thing, and the thing; who said what a candidate was read out of. */
    readonly SAID: "said";
    /** A thing, and somebody it names. */
    readonly MENTIONS: "mentions";
    readonly MEMBER_OF: "member_of";
    readonly REPORTS_TO: "reports_to";
    /** Whoever let something in, and what they approved; who confirmed a decision. */
    readonly APPROVED: "approved";
    /** A thing, and what its words link to. */
    readonly LINKS_TO: "links_to";
    /** Two things that say something alike, proposed by comparison and stated by nobody. */
    readonly RELATES: "relates";
    /** A decision, and the thing it was read out of. */
    readonly READ_FROM: "read_from";
    /** A decision, and what it is about. */
    readonly ABOUT: "about";
    /** A person a fact in force says answers for something. */
    readonly ANSWERS_FOR: "answers_for";
    /** A decision, and the person it names as owner, approver or party. */
    readonly NAMES: "names";
};
type WorkspaceLinkKind = (typeof WORKSPACE_LINK_KIND)[keyof typeof WORKSPACE_LINK_KIND];
/** Whether the picture was read live just now or stands on the facts this machine saved. */
declare const WORKSPACE_GRAPH_SOURCE: {
    readonly LIVE: "live";
    readonly SAVED: "saved";
};
type WorkspaceGraphSource = (typeof WORKSPACE_GRAPH_SOURCE)[keyof typeof WORKSPACE_GRAPH_SOURCE];
/** Why the saved facts stand in for the live graph. */
declare const WORKSPACE_GRAPH_FALLBACK: {
    /** This machine is not connected to a workspace, or was let go. */
    readonly NOT_JOINED: "not-joined";
    /** The control plane did not answer in time. */
    readonly UNREACHABLE: "unreachable";
    /** It answered and refused, or answered with something unreadable. */
    readonly REFUSED: "refused";
};
type WorkspaceGraphFallback = (typeof WORKSPACE_GRAPH_FALLBACK)[keyof typeof WORKSPACE_GRAPH_FALLBACK];
/** One message an author posted that the cloud counted rather than drew. */
interface WorkspaceSaid {
    label: string;
    href?: string;
    excerpt?: string;
    /** ISO time it was said. */
    at?: string;
}
interface WorkspaceGraphNode {
    /** The cloud's ref, or `fact:` and `candidate:` with the record's id. */
    id: string;
    kind: WorkspaceNodeKind;
    label: string;
    /** The system that delivered it, in its own word: slack, github. */
    tool?: string;
    /** Where to open it. */
    href?: string;
    /** The opening of what arrived, already clipped and cleared for this machine by the cloud. */
    excerpt?: string;
    /** The words a decision or a candidate states, verbatim. */
    statement?: string;
    /** Who said it, by name, where a line on the record says so. */
    saidBy?: string;
    /** ISO time it was said, settled or seen. */
    at?: string;
    /** How many times the same person said it, or how many messages an author's mark counts. */
    count?: number;
    status?: WorkspaceNodeStatus;
    /** declared, authoritative or observed, on a decision. */
    provenance?: string;
    /** Read from somebody the workspace does not know. */
    untrusted?: true;
    /** How many lines touch it, so a screen sizes it and names only the heavy ones. */
    weight: number;
    /** The newest messages an author's count holds, only those this machine may read. */
    said?: WorkspaceSaid[];
}
interface WorkspaceGraphLink {
    from: string;
    to: string;
    kind: WorkspaceLinkKind;
    /** candidate, observed or declared, where the record ranks the line. */
    basis?: string;
}
interface WorkspaceGraphView {
    nodes: WorkspaceGraphNode[];
    links: WorkspaceGraphLink[];
    /** How many this machine's clearance kept back, always said, or a partial picture reads as whole. */
    withheld: number;
    /** True where the cloud cut the picture at its ceiling. */
    truncated: boolean;
    source: WorkspaceGraphSource;
    /** Why the saved facts stand in, on a saved picture only. */
    fallback?: WorkspaceGraphFallback;
    /** When the live graph was read. */
    readAt?: string;
    /** When this machine last pulled the saved facts. */
    syncedAt?: string;
}
declare function workspaceFactId(id: string): string;
declare function workspaceCandidateId(id: string): string;
declare function workspaceSourceId(tool: string): string;

/**
 * Memory as every screen reads and changes it: the sources a person pointed Memnox at, the Learn
 * queue of what was read out of them, and the facts a person confirmed. A model only proposes;
 * a fact is verified by a person's confirm, and a rule holds only once its proposal is signed.
 */
declare const MEMORY_METHOD: {
    readonly MEMORY_LAYERS: "memory-layers";
    readonly MEMORY_LAYERS_PLAN: "memory-layers-plan";
    readonly MEMORY_LAYERS_APPLY: "memory-layers-apply";
    readonly SESSION_COST: "session-cost";
    /** Every source with where it is, its trust, when it was last read and what it taught. */
    readonly MEMORY_SOURCES: "memory-sources";
    /** Adds a folder, a repository's instruction files, an export, Supermemory or a hub server. */
    readonly MEMORY_SOURCE_ADD: "memory-source-add";
    /** Takes a source away; what it taught goes outdated rather than vanishing. */
    readonly MEMORY_SOURCE_REMOVE: "memory-source-remove";
    /** Reads a source again now and extracts what changed, with the person's own agent CLI. */
    readonly MEMORY_SOURCE_READ: "memory-source-read";
    /** The Learn queue: candidates and conflicts waiting on a person. */
    readonly MEMORY_LEARN: "memory-learn";
    /** A fact becomes verified; a rule candidate raises a signed rule proposal. */
    readonly MEMORY_CONFIRM: "memory-confirm";
    /** Rejected, and remembered so the same words are never proposed again. */
    readonly MEMORY_REJECT: "memory-reject";
    /** A candidate's words or its rule changed before it is confirmed. */
    readonly MEMORY_EDIT: "memory-edit";
    /** Search over what was learned: keyword, and by meaning too where a local embedding model is turned on. */
    readonly MEMORY_SEARCH: "memory-search";
    /** What was learned, by status and scope; verified by default. */
    readonly MEMORY_FACTS: "memory-facts";
    /** Deletes one item and its evidence. */
    readonly MEMORY_FORGET: "memory-forget";
    /**
     * What the workspace settled and what its connected tools said, as this machine last pulled
     * it, read off disk with no network near it. Only a read down: nothing local goes up with it.
     */
    readonly WORKSPACE_MEMORY: "workspace-memory";
    /**
     * The workspace's memory graph as the console draws it, read live off the control plane on this
     * machine's own credential and held only in memory, folded with the saved facts. Where the cloud
     * cannot be reached or refuses, the saved facts alone, saying why.
     */
    readonly WORKSPACE_GRAPH: "workspace-graph";
};
/** A source as a form adds it; a key is named, never sent, and kept with the hub's secrets. */
interface MemorySourceInput {
    kind: MemorySourceKind;
    /**
     * A folder, absolute, or a repository for instruction files, or an API's base URL. A Markdown,
     * a Notion export or an instructions source may also name one file, which is all it reads.
     */
    location?: string;
    name?: string;
    scope?: MemoryScope;
    /** The OS store entry holding an API key. */
    secret?: string;
    /** For an MCP source: the hub server, and the tool that reads it. */
    server?: string;
    tool?: string;
}
/** How many items a source taught, by where each stands now. */
interface MemorySourceCounts {
    candidate: number;
    verified: number;
    conflicting: number;
    outdated: number;
    rejected: number;
}
interface MemorySourceView {
    id: string;
    kind: MemorySourceKind;
    name: string;
    /** The folder, or the API's base URL. */
    location: string;
    trust: SourceTrust;
    scope: MemoryScope;
    project?: string;
    /** Re-read when a file in it changes; false for an API, which is read on request only. */
    watched: boolean;
    /** For a source that needs a key: whether the OS store holds it. Never the value. */
    keyHeld?: boolean;
    lastReadAt?: string;
    /** Why the last read failed, when it did. */
    lastError?: string;
    counts: MemorySourceCounts;
}
interface MemoryEvidenceView {
    /** As a person reads it: `notes/ops.md#Releases`, or the link. */
    ref: string;
    document: string;
    heading?: string;
    url?: string;
    /** The source's name, or the source id when it was removed. */
    source: string;
    /** The passage changed or went away since it was read. */
    stale: boolean;
    /** For evidence read from an agent's call: who made it, through what, and when, never what it carried. */
    call?: MemoryCallView;
}
/** One call an agent made through an app or an MCP server, named so the map joins the fact to the agent, its conversation and the app. */
interface MemoryCallView {
    /** `app` for a connected app reached through Memnox, `mcp` for an MCP server. */
    via: string;
    agent: string;
    sessionId?: string;
    /** The app's toolkit slug, on a call through Memnox. */
    app?: string;
    /** The MCP server's name, on a call to one. */
    server?: string;
    tool: string;
    at: string;
}
interface MemoryRuleView {
    effect: DecisionEffect;
    actions: string[];
    targets?: string[];
    agents?: string[];
    reason: string;
    /** The rule read back in one plain sentence, before any field. */
    sentence: string;
}
interface MemoryItemView {
    id: string;
    kind: MemoryKind;
    /** Verbatim as it was read or suggested. */
    statement: string;
    subject: string;
    status: MemoryStatus;
    scope: MemoryScope;
    project?: string;
    origin: MemoryOrigin;
    /** Read from a source outside the person's trust. */
    tainted: boolean;
    /** The extractor's own confidence, from 0 to 1, never a person's. */
    extractorConfidence?: number;
    /** The agent that suggested it. */
    suggestedBy?: string;
    rule?: MemoryRuleView;
    /** The earlier item it restates, so the queue says so rather than offering it as news. */
    duplicateOf?: {
        id: string;
        statement: string;
    };
    /** The rule proposal waiting on the person's signature. */
    proposalId?: string;
    evidence: MemoryEvidenceView[];
    createdAt: string;
    decidedAt?: string;
    decidedBy?: string;
}
interface MemoryItemsView {
    items: MemoryItemView[];
    /** Matching items past the ones listed, so a cut list never reads as whole. */
    more: number;
}
/** Whether the person's agent CLI read the passages a read found. */
declare const EXTRACTOR_STATE: {
    readonly ANSWERED: "answered";
    /** No agent CLI could be asked, so the new passages wait for the next read. */
    readonly UNAVAILABLE: "unavailable";
    /** It answered in no shape that could be read. */
    readonly UNREADABLE: "unreadable";
    /** Nothing new to read. */
    readonly IDLE: "idle";
};
type ExtractorState = (typeof EXTRACTOR_STATE)[keyof typeof EXTRACTOR_STATE];
/** What one read came to, so an empty read and a failed one are told apart. */
interface MemoryReadSummary {
    sourceId: string;
    documents: number;
    passages: number;
    added: number;
    /** Said again by another passage, which only added evidence. */
    merged: number;
    /** Words a person rejected before, not proposed again. */
    rejectedBefore: number;
    /** Citations naming no passage shown, dropped and never repaired. */
    droppedCitations: number;
    /** Candidates that did not survive validation. */
    discarded: number;
    outdated: number;
    /** Whether the person's agent CLI answered, so passages left unread are said as such. */
    extractor: ExtractorState;
    error?: string;
    /** Documents the source holds that this read passed over, and why; absent when none were. */
    skipped?: SkippedDocument[];
}
/** An edit before confirming; a rule goes through the same draft as any other rule. */
interface MemoryEditInput {
    statement?: string;
    subject?: string;
    rule?: RuleDraftInput;
}
/** How a search was answered, so a screen says keyword only rather than letting it pass as both. */
declare const MEMORY_SEARCH_MODE: {
    readonly KEYWORD: "keyword";
    readonly SEMANTIC: "semantic";
};
type MemorySearchMode = (typeof MEMORY_SEARCH_MODE)[keyof typeof MEMORY_SEARCH_MODE];
/** A passage a search found in what a source read, so a file's words are found and not only what was learned from it. */
interface MemoryPassageView {
    sourceId: string;
    document: string;
    heading?: string;
    /** The words around the match, cut short. */
    snippet: string;
}
interface MemoryRequestFields extends MemoryLayersRequestFields {
    /** On MEMORY_SOURCE_ADD. */
    memorySource?: MemorySourceInput;
    /** On MEMORY_SOURCE_REMOVE and MEMORY_SOURCE_READ. */
    memorySourceId?: string;
    /** On CONFIRM, REJECT, EDIT and FORGET. */
    memoryItemId?: string;
    /** On MEMORY_EDIT. */
    memoryEdit?: MemoryEditInput;
    /** On MEMORY_SEARCH. */
    memoryQuery?: string;
    /** On SEARCH, FACTS and LEARN: personal or project. */
    memoryScope?: MemoryScope;
    /** On MEMORY_FACTS. */
    memoryStatus?: MemoryStatus;
    /** On WORKSPACE_GRAPH: read the cloud again now rather than answer from the last few seconds' read. */
    workspaceGraphFresh?: boolean;
}
interface MemoryResponseFields extends MemoryLayersResponseFields {
    /** On every source method, so a screen redraws from one answer. */
    memorySources?: MemorySourceView[];
    /** On MEMORY_SOURCE_READ, which waits for a read already running, such as the one an add starts. */
    memoryRead?: MemoryReadSummary;
    /** On LEARN, and after CONFIRM, REJECT and EDIT. */
    memoryLearn?: MemoryItemsView;
    /** On MEMORY_FACTS and MEMORY_SEARCH. */
    memoryFacts?: MemoryItemsView;
    /** On MEMORY_SEARCH: keyword alone, or keyword fused with a local embedding model the person turned on. */
    memorySearchMode?: MemorySearchMode;
    /** On MEMORY_SEARCH: why it was keyword only although semantic search is on, such as the model not answering. */
    memorySearchNote?: string;
    /** On MEMORY_SEARCH: passages of the read documents that matched, best first. */
    memoryPassages?: MemoryPassageView[];
    /** On CONFIRM and EDIT: the item as it now stands. */
    memoryItem?: MemoryItemView;
    /** On WORKSPACE_MEMORY: absent where this machine never pulled one, which is every machine never connected. */
    workspaceMemory?: WorkspaceMemory;
    /** On WORKSPACE_GRAPH: always present, live where the cloud answered and the saved facts where it did not. */
    workspaceGraph?: WorkspaceGraphView;
}

/**
 * A rule a person said, in the runtime's own match fields: what the sentence grammar reads and
 * what a model's draft must come back as, checked by the same validator every policy file passes.
 */
/** One rule as a person meant it, before it is named and written. */
interface SpokenRuleDraft {
    effect: DecisionEffect;
    /** One action pattern; `*` with `classes` where the sentence named a kind of action. */
    operation: string;
    /** The agent kind it was narrowed to, where the person named one. */
    agent?: string;
    /** Wildcards over what the action touches; a leading `!` leaves one out. */
    targets?: string[];
    dataClassifications?: string[];
    classes?: string[];
    branches?: string[];
    alternative?: {
        action: string;
        note: string;
    };
}
/** What a sentence was read as, and what it left for the person to say. */
interface SpokenRuleReading {
    draft: SpokenRuleDraft;
    openQuestions: string[];
}
declare const ANY_ACTION = "*";
declare const EXCLUDE = "!";
/** Asked whenever a sentence says "approved" and names none, since a guessed list is a hole. */
declare const APPROVED_DESTINATIONS_QUESTION = "Which destinations are approved? Name each one and the rule leaves it out.";
/** Every name one product is seen under: the hook's kind, a shell's launcher and the console's id. */
declare function agentPatterns(kind: string): string[];
/** The rule as the engine reads it; the name is unique to what it matches, so a second rule never replaces the first. */
declare function policyOfSpokenRule(draft: SpokenRuleDraft): Policy;
/** What the runtime's own validator refuses in the rule, empty when it would load. */
declare function spokenRuleProblems(draft: SpokenRuleDraft): string[];
/**
 * A draft from a model's answer, or undefined where any field falls outside the runtime's own
 * words: a fourth effect, a class or a kind of data nobody classifies, an agent nobody runs.
 */
declare function spokenRuleFromModel(raw: unknown): SpokenRuleReading | undefined;
/** The rule in the words a person checks before they confirm it, and the reason an agent is given. */
declare function readBackOfSpokenRule(draft: SpokenRuleDraft): string;

/**
 * Two agents in one file inside this window are working at the same time: long enough to
 * outlast a test run, short enough that yesterday's edit is not a collision.
 */
declare const DEFAULT_COLLISION_WINDOW_MINUTES = 30;
/** One shared file is a coincidence; two is a reason to ask somebody. */
declare const MINIMUM_SHARED_TARGETS = 2;
/** How many rows a screen that summarises the ledger reads: bounded, because a person is waiting. */
declare const LEDGER_SCAN_LIMIT = 20000;
/** A whole window's operations, which is the widest read any command makes. */
declare const LEDGER_WINDOW_LIMIT = 50000;
/** Searching back for one row by id, where the answer is usually near the end. */
declare const LEDGER_LOOKUP_LIMIT = 5000;
/** One session's worth, for a check that reads a transcript against the record. */
declare const LEDGER_SESSION_LIMIT = 2000;
/** A short look back, for a question about something that just happened. */
declare const LEDGER_RECENT_LIMIT = 500;
/** The last matching row and nothing else. */
declare const LEDGER_LATEST_ONLY = 1;
/** The parts of an action's context a verdict is read against, in the order a person reads them. */
declare const CONTEXT_DOMAIN: {
    /** Who the agent works for, and what that person may do. */
    readonly PERSON: "person";
    /** Which agent, in which job, and whether it touched what governs it. */
    readonly AGENT: "agent";
    /** What the session said it was for. */
    readonly INTENT: "intent";
    /** What the call does and whether anybody could read it first. */
    readonly TOOLS: "tools";
    /** Where it lands, and the rules and conditions in force there. */
    readonly SYSTEMS: "systems";
    /** What this agent has done before, and what this session did on the way here. */
    readonly HISTORY: "history";
};
type ContextDomain = (typeof CONTEXT_DOMAIN)[keyof typeof CONTEXT_DOMAIN];
/**
 * How a rule that agreed with a verdict names the part of the context it was written
 * about, among the verdict's signals, so the ledger can say which part decided.
 */
declare const CONTEXT_SIGNAL_PREFIX: {
    readonly PERSON: "person:";
    readonly AGENT: "agent:";
    readonly INTENT: "intent:";
    readonly SYSTEMS: "systems:";
    /** How the call sat against the declared task: `scope:in_scope` or `scope:out_of_scope`. */
    readonly SCOPE: "scope:";
};

/** One part of the context, and what the row says about it. */
interface ContextPart {
    domain: ContextDomain;
    /** In words, each a fact the row carries or a rule that agreed with the verdict. */
    facts: string[];
    /** Something here is why the verdict came out the way it did. */
    decided: boolean;
}
/** Every part, in reading order, so a part with nothing recorded says so rather than vanishing. */
declare function actionContextOf(event: MemnoxEvent): ContextPart[];
/** A row with no signals was written before they were kept, which is not the same as clear. */
declare function hasRecordedContext(event: MemnoxEvent): boolean;

/**
 * What a checkout claims: an issue number at the head of its branch and keys its head commit names.
 * The workspace checks each against what its trackers delivered; only the claim leaves the machine.
 */
declare const WORK_CLAIM_FORM: {
    readonly KEY: "key";
    readonly NUMBER: "number";
    readonly URL: "url";
};
declare const WORK_CLAIM_SOURCE: {
    readonly BRANCH: "branch";
    readonly COMMIT: "commit";
    readonly PROMPT: "prompt";
};
interface WorkClaim {
    value: string;
    form: (typeof WORK_CLAIM_FORM)[keyof typeof WORK_CLAIM_FORM];
    source: (typeof WORK_CLAIM_SOURCE)[keyof typeof WORK_CLAIM_SOURCE];
    /** The commit a commit claim was read from, so the evidence stays the commit. */
    evidence?: string;
}
interface WorkClaims {
    /** The branch the checkout is on, so a change of branch can replace what the old one claimed. */
    branch?: string;
    claims: WorkClaim[];
}
/** How long reading the head commit may take before the lease goes without it. */
declare const COMMIT_READ_TIMEOUT_MS = 400;
/** The issue number a branch was made for, read from its last segment, or undefined. */
declare function numberClaimOfBranch(branch: string | null): WorkClaim | undefined;
/**
 * The keys a commit message names, written in capitals as a tracker writes
 * them. More than a handful reads as a list rather than the work, so none.
 */
declare function keysInText(text: string): string[];
/** Keys in the head commit's message, each carrying the commit it came from. */
declare function commitClaimsAt(root: string, timeoutMs?: number): Promise<WorkClaim[]>;
/** What this checkout claims now, and what its session's prompts named. Branch keys travel as its refs. */
declare function workClaimsAt(root: string, prompted?: () => Promise<readonly WorkClaim[]>): Promise<WorkClaims>;

/**
 * What somebody asked for, written down before the agent starts, because scope drift
 * compared against anything but a declaration is a classifier with an opinion. An absent
 * task is `undeclared` throughout, never a guess and never a violation.
 */
declare const TASK_DIR = "tasks";
interface SessionTask {
    id: string;
    sessionId: string;
    /** In the words the person used, so a refusal can quote the ask. */
    statement: string;
    scope: DeclaredScope;
    declaredAt: string;
    /** Roughly what this should take: evidence of surprise, never a ceiling on its own. */
    expectedActions?: number;
    /** `investigate` holds the session to reading: a change outside this machine is refused. */
    intent?: TaskIntent;
    /** `prompt` when read from what the person typed, which a declared task always replaces. */
    declaredBy?: string;
    /** The person's latest follow up in the session, kept beside the mission rather than over it. */
    latestAsk?: string;
    /** Issues the person's own words named as the task: kept here, and only the claim is ever sent. */
    promptClaims?: WorkClaim[];
}
declare const TASK_INTENT: {
    readonly INVESTIGATE: "investigate";
};
type TaskIntent = (typeof TASK_INTENT)[keyof typeof TASK_INTENT];
declare function taskDirFor(home: string): string;
/** What a person declares for a session, before it is stamped with an id and a time. */
interface TaskDeclaration {
    sessionId: string;
    statement: string;
    scope: DeclaredScope;
    expectedActions?: number;
    intent?: TaskIntent;
}
declare function taskFor(declaration: TaskDeclaration, now: string): SessionTask;
/** Nothing declared at all. Written so a caller can say so rather than test for empty. */
declare function isEmptyScope(scope: DeclaredScope): boolean;
declare class SessionTasks {
    private readonly records;
    constructor(home: string);
    declare(task: SessionTask): Promise<void>;
    /** Null when nothing was declared for this session, which is the ordinary case. */
    read(sessionId: string): Promise<SessionTask | null>;
    all(): Promise<SessionTask[]>;
    clear(sessionId: string): Promise<void>;
}
/**
 * The five dimensions of a request, read off what the caller reported and taken
 * verbatim, because deriving a service from a path would be a guess.
 */
declare function subjectOf(request: ActionRequest): ScopeSubject;
/**
 * How this request sat against what was asked for. `undeclared` when no task was, which
 * is not a finding: most sessions declare none and calling that drift would drown it.
 */
declare function scopeOf(task: SessionTask | null, request: ActionRequest, matches: (patterns: readonly string[], value: string) => boolean): ScopeComparison;
/** The line a refusal or a report uses. Names the dimension, never merely "out of scope". */
declare function describeDrift(task: SessionTask, drift: ScopeComparison): string;
/** How long a task declared for a repository stands, since a forgotten one would narrow for ever. */
declare const REPOSITORY_TASK_HOURS = 12;
interface RepositoryTask extends SessionTask {
    root: string;
    until: string;
}
/**
 * A task somebody declared for a repository rather than for one session, which is how a
 * session only the hooks see gets one: nobody knows its id, everybody knows the repository.
 */
declare class RepositoryTasks {
    private readonly records;
    constructor(home: string);
    declare(root: string, declaration: Omit<TaskDeclaration, 'sessionId'>, moment: {
        now: string;
        hours?: number;
    }): Promise<RepositoryTask>;
    /** The task standing for this repository, or null where none is or it ran out. */
    inForce(root: string | null, now: string): Promise<RepositoryTask | null>;
    clear(root: string): Promise<void>;
}

/**
 * The ledger as a screen pages through it: what agents did and what was decided, names only and
 * never arguments or file contents, one decision opened whole, and a period exported signed.
 */
declare const ACTIVITY_METHOD: {
    /** One page of the ledger, newest first, filtered and bounded. */
    readonly ACTIVITY: "activity";
    /** One decision whole: its rule, who handed the work down, what led up to it, and the trace. */
    readonly DECISION: "decision";
    /** The rows a filter selects, as a signed bundle an auditor can check. */
    readonly ACTIVITY_EXPORT: "activity-export";
};
/** What kind of thing an agent did, as a filter names it. */
declare const ACTIVITY_KIND: {
    readonly TOOL: "tool";
    readonly COMMAND: "command";
    readonly FILE: "file";
    readonly MCP: "mcp";
};
type ActivityKind = (typeof ACTIVITY_KIND)[keyof typeof ACTIVITY_KIND];
/** How a held call was let through. */
declare const ANSWERED_HOW: {
    /** With Touch ID or Face ID. */
    readonly SIGNED: "signed";
    /** On the Mac, for a call that stayed inside its session's repository. */
    readonly WITHIN_SESSION: "within-session";
    /** By voice, in a terminal, or any route that names itself otherwise. */
    readonly OTHER: "other";
};
type AnsweredHow = (typeof ANSWERED_HOW)[keyof typeof ANSWERED_HOW];
interface ActivityFilter {
    effect?: DecisionEffect;
    /** The agent's kind, such as claude-code. */
    agent?: string;
    kind?: ActivityKind;
    /** Matched against the operation, the target and the rule's name, never arguments. */
    text?: string;
    /** ISO 8601; only rows at or after it. */
    since?: string;
    /** ISO 8601; only rows at or before it. */
    until?: string;
}
interface ActivityRow {
    id: string;
    at: string;
    agent: string;
    agentName: string;
    session: string;
    kind: ActivityKind;
    operation: string;
    target?: string;
    effect: DecisionEffect;
    /** What enforce would have said, where the mode kept it from being applied. */
    shadowEffect?: DecisionEffect;
    rule?: string;
    reason: string;
    answeredBy?: string;
    answeredHow?: AnsweredHow;
    /** The exit code, where it ran and failed. */
    failed?: number;
}
interface ActivityPage {
    rows: ActivityRow[];
    /** Hand back as `activityCursor` for the next page; absent on the last. */
    nextCursor?: string;
}
/** The rule that decided, as it stands now beside what the row recorded. */
interface DecisionRule {
    name: string;
    file?: string;
    line?: number;
    source?: RuleSource;
    decidedBy?: string;
    decidedAt?: string;
    /** The workspace has published newer rules since this was decided. */
    newerSince?: boolean;
}
/** One step the session took just before, names only. */
interface DecisionStep {
    at: string;
    operation: string;
    target?: string;
    effect: DecisionEffect;
}
/** The ledger's own account of the action, as `memnox trace` prints it. */
interface DecisionTrace {
    mode: string;
    exitCode?: number;
    durationMs?: number;
    approvedBy?: string;
    argsDigest?: string;
    outputDigest?: string;
}
interface DecisionView {
    row: ActivityRow;
    rule?: DecisionRule;
    /** Who handed the work down, as one line: person, agent, helper. */
    chain: string;
    context: ContextPart[];
    /** The task somebody declared for the session, where one was. */
    task?: string;
    before: DecisionStep[];
    alternative?: string;
    trace: DecisionTrace;
}
/** One row as it is written, for a live timeline: names only, never arguments, output or contents. */
interface LiveActivityRow {
    id: string;
    at: string;
    /** The agent's kind, such as claude-code. */
    agent: string;
    operation: string;
    effect: DecisionEffect;
    /** The target by name: a path, a host, a server; never what was sent to it. */
    target?: string;
}
/** The most rows one ACTIVITY event carries; the rest of a burst is counted, and a screen pages for it. */
declare const MOST_LIVE_ACTIVITY_ROWS = 20;
interface ActivityEventFields {
    /** On ACTIVITY: the rows written since the last one, oldest first. */
    activityRows?: LiveActivityRow[];
    /** On ACTIVITY: rows of the same burst this event does not carry, at least this many. */
    activityMissed?: number;
}
interface ActivityRequestFields {
    /** On ACTIVITY and ACTIVITY_EXPORT. */
    activityFilter?: ActivityFilter;
    /** On ACTIVITY: where the last page ended. */
    activityCursor?: string;
    /** On ACTIVITY: rows wanted, capped by the daemon. */
    activityLimit?: number;
    /** On DECISION: the row, by id. */
    decisionId?: string;
}
interface ActivityResponseFields {
    /** On ACTIVITY. */
    activity?: ActivityPage;
    /** On DECISION. */
    decision?: DecisionView;
    /** On ACTIVITY_EXPORT: the signed header as one JSON line, then one event per line. */
    activityBundle?: string;
}

/** A sign in the daemon has under way: the code to approve and where, as the Mac app shows them. */
interface PersonSignInCode {
    userCode: string;
    page?: string;
    /** Epoch milliseconds. */
    expiresAt: number;
}
/**
 * Whether a person is signed in on the daemon's side. The Mac app keeps its own credential for
 * answering from the notch; the voice's tools and `memnox inbox` go through this one.
 */
interface PersonStanding {
    signedIn: boolean;
    name?: string;
    workspaceId?: string;
    /** A sign in under way, until it is approved or runs out. */
    code?: PersonSignInCode;
    /** Why the last sign in stopped, kept until the next one starts. */
    failed?: string;
}
/**
 * Whether this machine is connected to a workspace, the credential `memnox login` writes, which is what
 * carries rules, workspace memory and phone pairing to it. The same shape as a person's standing, with the
 * workspace's name where a person's would be, so the Mac app shows both with one piece of code.
 */
interface MachineStanding {
    signedIn: boolean;
    /** The workspace's name, once the workspace has said it. */
    name?: string;
    workspaceId?: string;
    machineId?: string;
    /** A connection under way, until it is approved or runs out. */
    code?: PersonSignInCode;
    /** Why the last connection stopped, or that the workspace let this machine go. */
    failed?: string;
}

/**
 * When a person last asked an agent something and when it last finished answering, written by
 * the agent's own hook. The ledger cannot say this: an agent writing a long reply records
 * nothing, so silence there reads as finished when it is still working.
 */
declare const TURNS_DIR = "turns";
/** One turn: from the person's prompt until the agent handed back, open while it works. */
interface TurnWindow {
    promptAt: string;
    endedAt?: string;
}
interface SessionTurn {
    sessionId: string;
    agent: string;
    /** The person's last prompt. */
    promptAt?: string;
    /** The agent's last turn ending, when it stopped and handed back to the person. */
    endedAt?: string;
    /** Every recent turn, oldest first, so what changed while it worked can be told apart from the rest. */
    windows?: TurnWindow[];
}
declare class SessionTurns {
    private readonly records;
    private readonly dir;
    constructor(home: string);
    prompted(sessionId: string, agent: string, at: string): Promise<void>;
    private recordPrompt;
    ended(sessionId: string, agent: string, at: string): Promise<void>;
    private recordEnding;
    read(sessionId: string): Promise<SessionTurn | null>;
    all(): Promise<SessionTurn[]>;
}

declare const NOTICE_KIND: {
    /** A long turn ended and the agent handed back to the person. */
    readonly FINISHED: "finished";
    readonly COMMITTED: "committed";
    readonly PUSHED: "pushed";
    /** Something the person asked to be told about happened. */
    readonly WATCHED: "watched";
    /** Only watching, a rule would have asked about or refused something that went through. */
    readonly WOULD_HAVE: "would-have";
    /** An agent asked its person something in its own picker, held so the voice can read it out. */
    readonly QUESTION: "question";
    /** A command the voice started ran on its own and worked, which needs nobody, so it is shown and not said. */
    readonly ENDED: "ended";
    /** Two agents on one piece of work, here or across machines, which the person sorts out. */
    readonly COLLISION: "collision";
    /** A teammate speaking to the person through the workspace, said at once and listened after. */
    readonly MESSAGE: "message";
    /** The person's agent and a teammate's were found on one feature and introduced, which is shown. */
    readonly TOGETHER: "together";
    /** A session has failures it has not got past, so its changes outside this machine ask first. */
    readonly STRUGGLING: "struggling";
    /** A session began, by its own start hook or its first action, which is shown and kept for the voice. */
    readonly STARTED: "started";
    /** A session ended: closed by the person, or its process gone with nothing in progress. */
    readonly CLOSED: "closed";
    /** A session's process went away in the middle of a turn, so whatever it was doing stopped unfinished. */
    readonly GONE: "gone";
    /** The person finished signing in to one of their tools, so what they asked for can carry on. */
    readonly SIGNED_IN: "signed-in";
    /** A sign in the person opened never finished, which a company's approval screen is the usual cause of. */
    readonly SIGN_IN_STALLED: "sign-in-stalled";
    /** An agent stopped in its own terminal to ask its person something, which the voice reads and answers there. */
    readonly ASKING: "asking";
    /** A budget passed the line its person asked to be told at, or ran out. */
    readonly BUDGET: "budget";
};
type NoticeKind = (typeof NOTICE_KIND)[keyof typeof NOTICE_KIND];
/**
 * The one id a piece of news has on every route that carries it, the live broadcast, the
 * waiting feed and a phone's wake, so a surface told twice shows it once.
 */
declare function noticeSubject(kind: NoticeKind, sessionId: string, at: string): string;
interface SessionNotice {
    kind: NoticeKind;
    sessionId: string;
    agent: string;
    at: string;
    /** For a commit or a push, what it named: the branch or the remote. */
    target?: string;
    /** For a finished turn, how long it ran, which is why it is worth saying. */
    minutes?: number;
    /** For what a rule would have done: the action, the rule, and ask or deny. */
    action?: string;
    rule?: string;
    wouldHave?: string;
}
/** What has been told so far, carried from one look to the next so nothing is told twice. */
interface NoticeWatch {
    /** The newest ledger event already counted. */
    seen: string;
    /** The newest turn ending already counted. */
    turnsSeen: string;
}
/** What a turn came to, counted from the ledger, so "it asked you nothing" is a count and never a guess. */
interface RunTally {
    actions: number;
    /** Put to a person, whatever they answered. */
    asked: number;
    /** Refused, by a rule or a person. */
    stopped: number;
}
/** Agent work between two moments; a config change or a summary row is Memnox's own and never counted. */
declare function runTally(events: readonly MemnoxEvent[], from: string, to: string): RunTally;
/** The tally as a sentence a person hears at the end of a run they were not watching. */
declare function describeRun(tally: RunTally): string;
/** A turn this long is one the person likely stepped away from, so its end is news; a short one they watched. */
declare const LONG_TURN_MS: number;
declare function startWatch(moment: string): NoticeWatch;
/** The new notices since the last look, and the watch to carry into the next one. */
declare function noticesFrom(watch: NoticeWatch, events: readonly MemnoxEvent[], turns: readonly SessionTurn[]): {
    watch: NoticeWatch;
    notices: SessionNotice[];
};

/**
 * Something the person asked to be told about a session, like "tell me when the tests pass".
 * Each watch speaks once and is gone, and the decision is made from facts the caller gathered,
 * so it is the same answer every time it is asked with the same facts.
 */
declare const WATCHES_DIR = "watches";
/** A working afternoon, never a watch that speaks up tomorrow about something long forgotten. */
declare const WATCH_TTL_MS: number;
declare const WATCH_FOR: {
    /** Its turn ended and it handed back to the person. */
    readonly FINISHED: "finished";
    /** A test run passed after the watch was set. */
    readonly TESTS_PASS: "tests_pass";
    /** A test run failed after the watch was set. */
    readonly TESTS_FAIL: "tests_fail";
    /** It is paused, or a call of its is held waiting on the person. */
    readonly STUCK: "stuck";
};
type WatchFor = (typeof WATCH_FOR)[keyof typeof WATCH_FOR];
interface SessionWatch {
    id: string;
    sessionId: string;
    agent: string;
    for: WatchFor;
    /** What the person said, so the voice can answer in their terms. */
    said?: string;
    /**
     * A session just started has no id until its agent first acts, so the watch waits for the
     * first one in this repository started after `since`, and `sessionId` stays empty until then.
     */
    awaiting?: AwaitedSession;
    setAt: string;
    expiresAt: string;
}
interface AwaitedSession {
    repository: string;
    since: string;
}
/** One test run the agent made, as its own transcript records it. */
interface TestRun {
    at: string;
    command: string;
    passed: boolean;
}
/** What is known about the session right now, gathered by whoever holds the files. */
interface WatchFacts {
    promptAt?: string;
    endedAt?: string;
    testRuns: readonly TestRun[];
    paused: boolean;
    held: number;
}
/** Why it fired, in a plain sentence the voice can say when it cannot word it itself. */
interface WatchFired {
    watch: SessionWatch;
    what: string;
}
/** Whether the thing the person asked about has happened since they asked, and what it was. */
declare function watchFired(watch: SessionWatch, facts: WatchFacts): WatchFired | null;
/** Whether a shell command runs a test suite, from how test runners are invoked. */
declare function isTestCommand(command: string): boolean;
interface WatchInput {
    sessionId: string;
    agent: string;
    for: WatchFor;
    said?: string;
    awaiting?: AwaitedSession;
    at: string;
}
declare class SessionWatches {
    private readonly records;
    constructor(home: string);
    set(input: WatchInput): Promise<SessionWatch>;
    /** The watches still waiting, removing the expired so the folder never grows. */
    open(moment: string): Promise<SessionWatch[]>;
    /** The session it was waiting for has appeared, so from now on it watches that one. */
    bind(watch: SessionWatch, sessionId: string): Promise<SessionWatch>;
    /** Said once, so it is gone. */
    done(id: string): Promise<void>;
}

/** How a finished turn's tests stood when it handed back, so nothing celebrates work nobody checked. */
declare const TURN_TESTS: {
    /** The last run inside the turn passed and nothing was written after it. */
    readonly PASSED: "passed";
    /** The last run inside the turn failed. */
    readonly FAILED: "failed";
    /** The last run passed, but a file was written after it, so the pass no longer covers the work. */
    readonly STALE: "stale";
    /** The agent ran no tests in the turn. */
    readonly NONE: "none";
};
type TurnTests = (typeof TURN_TESTS)[keyof typeof TURN_TESTS];
/** The stretch a turn ran in: from the person's prompt to the agent handing back. */
interface TurnSpan {
    promptAt: string;
    endedAt: string;
}
/** The last test run inside the turn, weighed against the writes that came after it. */
declare function turnTests(span: TurnSpan, runs: readonly TestRun[], writesAt: readonly string[]): TurnTests;

/** How an instruction the Mac was asked to type ended, as DELIVERED reports it in `answer`. */
declare const DELIVERY: {
    /** Typed into the agent's prompt and sent, though nothing read it back, so it is not known to have landed. */
    readonly TYPED: "typed";
    /** Typed and sent, and the Mac read the target back and saw it land, which `proof` says how. */
    readonly VERIFIED: "verified";
    /** Left for the session's next prompt, since reaching it now would have taken the person's window. */
    readonly WAITING: "waiting";
    /** It could not be typed safely, so the words were left on the clipboard. */
    readonly CLIPBOARD: "clipboard";
    /** The Mac is not allowed to press keys until the person turns Memnox on under Accessibility, so the words were left on the clipboard. */
    readonly NOT_ALLOWED: "not-allowed";
    /** Nothing was typed anywhere. */
    readonly FAILED: "failed";
};
type Delivery = (typeof DELIVERY)[keyof typeof DELIVERY];
/** What the Mac read back after acting, so a claim that something landed carries what it saw. */
interface DeliveryProof {
    /** What was checked, in a few words, such as "the words in its terminal tab". */
    checked: string;
    /** The excerpt that was seen, when the check read text. */
    seen?: string;
    /** A screenshot of the target taken after acting, by its path on this Mac. */
    image?: string;
}
/** One window as the Mac saw it: whose it is, a capture of it, and the labels its controls carry. */
interface Sight {
    app: string;
    window?: string;
    /** The capture, by its path on this Mac; absent when Memnox may not record the screen. */
    image?: string;
    /** Roles, titles and values from the window's accessibility tree, one control per line. */
    outline?: string;
    /** The words in the capture, read on the Mac, so the screen is read without the picture leaving it. */
    text?: string;
}
/**
 * What the screen showed around an action: the target's window just before and just after, by their
 * paths on the Mac, and the words read off the after one there, so what is said about it has a witness.
 */
interface Witness {
    app: string;
    before?: string;
    after?: string;
    text?: string;
}
/** Typed in either way: sent, whether or not it was read back. */
declare function wentIn(outcome: Delivery): boolean;

/** How a show event wants to be shown, as the Mac app's Display mirrors it. */
declare const DISPLAY: {
    /** Bring the session's own window forward. */
    readonly OPEN: "open";
    /** Put a summary card on screen while the voice reads it. */
    readonly CARD: "card";
    /** Type the person's confirmed instruction into the terminal tab the agent waits in. */
    readonly TYPE: "type";
    /** Open the session in its editor with the instruction in its input, for the person to send. */
    readonly PREFILL: "prefill";
    /** Turn through the sessions to this one and bring its own terminal tab or editor forward. */
    readonly FOCUS: "focus";
    /** Open a new terminal tab in a repository and type the line that starts an agent there. */
    readonly LAUNCH: "launch";
    /** Open an agent's own desktop app on a repository, with the task handed to it through its links. */
    readonly APP: "app";
    /** A card that pages through a session's changed files while the voice walks through them. */
    readonly WALK: "walk";
    /** The whole screen: every agent on this Mac, found by a live scan, with what each reaches. */
    readonly AGENTS: "agents";
    /** A trace as a waterfall card: what ran, inside what, for how long, and what failed. */
    readonly TRACE: "trace";
    /** Every session lately as one card each, together, so they can be read at a glance. */
    readonly SESSIONS: "sessions";
    /** Close the live window on a session and its own terminal tab, which ends the agent there. */
    readonly CLOSE: "close";
    /** Press Escape in the terminal a session runs in, which stops its turn where it is and keeps the tab. */
    readonly INTERRUPT: "interrupt";
    /** Take every Memnox card and window off the screen, leaving every agent and its tab alone. */
    readonly DISMISS: "dismiss";
    /** A message from the person's connected mail, drafted for them to read; Send is a signed CONFIRM of `subject`. */
    readonly DRAFT: "draft";
    /** Open a folder the person named; its title says where: finder, editor or terminal. */
    readonly FOLDER: "folder";
    /** Look at the screen: the Mac captures the window in front, or the app named in the title, and answers with SEEN. */
    readonly LOOK: "look";
    /** Press keys in the terminal a session runs in, the text naming them, to answer what its agent asks there. */
    readonly PRESS: "press";
    /** The icons of tools the person asked for and has not signed in to; each opens that tool's own sign in. */
    readonly SIGN_IN: "signin";
    /** A web page the person asked to open, its one http or https address in `links`, opened in their browser. */
    readonly LINK: "link";
};
type DisplayKind = (typeof DISPLAY)[keyof typeof DISPLAY];
/** How a LAUNCH reaches where it runs, when that is not a terminal tab or an editor's own terminal. */
declare const DISPLAY_VIA: {
    /** Another terminal app, such as Ghostty, opened on the folder with the line typed into its new window. */
    readonly TERMINAL_APP: "terminal-app";
    /** An editor's agent panel, opened on the folder with the task sent as a new conversation. */
    readonly PANEL: "panel";
    /** On APP, a new chat started in the app before the words are typed, rather than the one open. */
    readonly NEW_CHAT: "new-chat";
    /**
     * On APP, the words the app's own prompt link left in its chat sent with Return, only once the Mac
     * reads them in the focused chat input; the Mac answers verified when it sent them.
     */
    readonly SEND_PREFILLED: "send-prefilled";
};
type DisplayVia = (typeof DISPLAY_VIA)[keyof typeof DISPLAY_VIA];
/** The named keys a PRESS may carry, as the Mac maps each to the key itself. */
declare const TERMINAL_KEY: {
    readonly UP: "up";
    readonly DOWN: "down";
    readonly LEFT: "left";
    readonly RIGHT: "right";
    readonly ENTER: "enter";
    readonly ESCAPE: "escape";
    readonly TAB: "tab";
    readonly SPACE: "space";
};
type TerminalKey = (typeof TERMINAL_KEY)[keyof typeof TERMINAL_KEY];
/** Enough to move down a list of choices and pick one, never a sentence typed a key at a time. */
declare const MOST_PRESSED_KEYS = 8;
/** The keys named, in order, or null when any word is not a key, so only keys are ever pressed. */
declare function terminalKeys(said: string): string[] | null;

/**
 * A question an agent put to its person in its own picker, such as Claude Code's
 * AskUserQuestion, held for a moment so the voice can read it out and the spoken answer can
 * go back in the picker's place. Unanswered in time, the picker opens as it always did.
 */
declare const AGENT_QUESTIONS_DIR = "questions";
/** Every agent question id starts with this, so a brief can tell one from any other subject. */
declare const AGENT_QUESTION_PREFIX = "aqn_";
/** Long enough to hear one question read and answer it; each answer earns the next one as long again. */
declare const AGENT_QUESTION_WAIT_MS = 45000;
/**
 * The longest a set of questions is held however many steps it has, inside the five minutes
 * the hook is given, so the agent's own picker still opens if the person walks away mid-way.
 */
declare const AGENT_QUESTION_MOST_MS = 270000;
interface AgentQuestionOption {
    label: string;
    description?: string;
}
interface AgentQuestionItem {
    question: string;
    header?: string;
    options: AgentQuestionOption[];
    multiSelect: boolean;
}
interface AgentQuestion {
    id: string;
    sessionId: string;
    agent: string;
    questions: AgentQuestionItem[];
    askedAt: string;
    expiresAt: string;
    /** By question text, the way the host's picker records a pick. */
    answers?: Record<string, string>;
    answeredAt?: string;
}
interface AgentQuestionInput {
    sessionId: string;
    agent: string;
    toolUseId: string;
    questions: AgentQuestionItem[];
    at: string;
    waitMs?: number;
}
declare function isAgentQuestionId(subject: string): boolean;
/** Every question has an answer, so the picker has nothing left to ask. */
declare function fullyAnswered(question: AgentQuestion): boolean;
/**
 * What was said as the answer to one question: an option's label when it names one, ignoring
 * case and a trailing full stop, and otherwise the words themselves, which the picker takes
 * as its "other" answer.
 */
declare function answerFor(item: AgentQuestionItem, said: string): string;
declare class AgentQuestions {
    private readonly records;
    constructor(home: string);
    ask(input: AgentQuestionInput): Promise<AgentQuestion>;
    read(id: string): Promise<AgentQuestion | null>;
    /** Still waiting on the person: unanswered and inside its wait, removing the rest. */
    open(moment: string): Promise<AgentQuestion[]>;
    /**
     * One question's answer, by its number from one; the record when it took, null when the
     * question is gone, already over, or has no such number.
     */
    answer(id: string, number: number, said: string, moment: string): Promise<AgentQuestion | null>;
    close(id: string): Promise<void>;
}

/**
 * Connecting the person's own tools from any screen: every person signed in to Memnox Cloud, on
 * every plan, may connect any toolkit the cloud's catalogue holds, as themselves, with nobody else
 * asked first. Signed out, the catalogue can still be browsed but nothing is connected.
 */
/** A search answers no more than this many, which is what a picker shows before the person types more. */
declare const MOST_TOOLKITS_FOUND = 30;
/** The sign in page for one tool, and whether the daemon already opened it in the Mac's browser. */
interface ConnectionSignIn {
    /** The cloud's lowercase toolkit slug. */
    toolkit: string;
    url: string;
    /** False from a paired phone, which opens the page itself. */
    opened: boolean;
}
/** Memnox Cloud's own reading of a toolkit: whether it supplies records, conversation, or neither. */
declare const TOOLKIT_KIND: {
    readonly RECORD: "record";
    readonly CONVERSATION: "conversation";
    readonly OTHER: "other";
};
type ToolkitKind = (typeof TOOLKIT_KIND)[keyof typeof TOOLKIT_KIND];
/** How fully Memnox Cloud reads a toolkit once connected: its history and its authors, or less. */
declare const TOOLKIT_SUPPORT: {
    readonly FULL: "full";
    readonly PARTIAL: "partial";
};
type ToolkitSupport = (typeof TOOLKIT_SUPPORT)[keyof typeof TOOLKIT_SUPPORT];
/** Where a connector comes from, in the order a search offers them: the vendor's own first, a community server last. */
declare const CONNECTOR_SOURCE: {
    /** The vendor's own server, or one the catalogue verified. */
    readonly OFFICIAL: "official";
    /** A command line tool on this machine. */
    readonly CLI: "cli";
    /** The vendor's API, reached through the catalogue. */
    readonly API: "api";
    /** A community MCP server. */
    readonly MCP: "mcp";
};
type ConnectorSource = (typeof CONNECTOR_SOURCE)[keyof typeof CONNECTOR_SOURCE];
/** The weight each source sorts by, highest first, which a screen shows as a chip. */
declare const CONNECTOR_WEIGHT: Readonly<Record<ConnectorSource, number>>;
/** One tool the catalogue offers, by the slug a sign in takes; an older cloud sends only the first three. */
interface ToolkitSummary {
    slug: string;
    name: string;
    logo?: string;
    /** The provider's own words for it, as the cloud's catalogue carries them. */
    description?: string;
    /** The provider's category tags, as written, which a screen counts into a rail. */
    categories?: string[];
    kind?: ToolkitKind;
    support?: ToolkitSupport;
    /** Where it comes from; a search answers official first, then cli, api and mcp. */
    source?: ConnectorSource;
    /** CONNECTOR_WEIGHT of its source. */
    weight?: number;
}
/** The source a catalogue entry names, or official where it says the catalogue verified it, else its API. */
declare function connectorSourceOf(named: unknown, verified: unknown): ConnectorSource;
/** Highest weight first, the catalogue's own order kept within a weight. */
declare function rankedBySource(toolkits: readonly ToolkitSummary[]): ToolkitSummary[];
/** Why a connection cannot be made yet, as a state a screen draws rather than words it reads. */
declare const CONNECT_STATE: {
    /** Nobody is signed in to Memnox Cloud on this machine, which connecting any app now needs. */
    readonly SIGN_IN_NEEDED: "sign-in-needed";
};
type ConnectState = (typeof CONNECT_STATE)[keyof typeof CONNECT_STATE];
interface ConnectionsRequestFields {
    /** On CONNECTIONS_SIGN_IN and CONNECTIONS_SIGN_OUT: the tool, by its lowercase slug. */
    toolkit?: string;
    /** On CONNECTIONS_SIGN_IN: open a new sign in even where one already works, to use another account. */
    again?: boolean;
    /** On TOOLKITS_SEARCH: the words to match; left out lists the catalogue's first page. */
    query?: string;
}
interface ConnectionsResponseFields {
    /** On CONNECTIONS_SIGN_IN: the page that connects the tool. */
    signIn?: ConnectionSignIn;
    /** On TOOLKITS_SEARCH: at most MOST_TOOLKITS_FOUND tools the catalogue matched. */
    toolkits?: ToolkitSummary[];
    /** On TOOLKITS_SEARCH and a refused CONNECTIONS_SIGN_IN: what connecting waits on, absent when nothing does. */
    connectState?: ConnectState;
}

/**
 * The part of the daemon protocol that lists a folder under the person's home, so a phone browses
 * the Mac by names and sizes without the brain or the screen. Nothing in a file ever travels.
 */
declare const ENTRY_KIND: {
    readonly FOLDER: "folder";
    readonly FILE: "file";
};
type EntryKind = (typeof ENTRY_KIND)[keyof typeof ENTRY_KIND];
/** One entry of a folder as FILES_LIST answers it: its name and what it is, never what is in it. */
interface FileEntry {
    name: string;
    kind: EntryKind;
    /** A file's size; absent on a folder. */
    bytes?: number;
    /** When it last changed, ISO 8601. */
    modified?: string;
}
interface FilesRequestFields {
    /** On FILES_LIST: the folder relative to the person's home; absent lists the home itself. */
    path?: string;
}
interface FilesResponseFields {
    /** On FILES_LIST: the folder listed, relative to the person's home and empty for the home itself. */
    path?: string;
    /** On FILES_LIST: folders first and then files, each by name, hidden entries left out. */
    files?: FileEntry[];
}

/**
 * The home every surface opens on, the same five blocks on the Mac, the iPhone and the terminal:
 * what waits on the person, what is working, what happened today, the one thing that could be
 * handed over next, and what nothing covers. Counts, never scores.
 */
declare const HOME_METHOD: {
    /** The five blocks, read once, so a screen draws them without asking five questions. */
    readonly HOME: "home";
    /** Turns the ready suggestion into a rule proposal the person confirms with Touch ID or Face ID. */
    readonly HAND_OVER: "hand-over";
    /**
     * Puts this machine from observe into enforce, unsigned because it only narrows what agents may do. Going back
     * to observe widens, so no surface offers it here and it stays `memnox protect --observe` at the terminal.
     */
    readonly MODE_ENFORCE: "mode-enforce";
};
/** What a mode change moved, so a screen says where it was and where it is now. */
interface HomeModeSet {
    was: string;
    now: string;
}
/** An agent at work right now, as one line on the home. */
interface HomeWorking {
    sessionId: string;
    agent: string;
    agentName: string;
    task?: string;
    repository?: string;
}
/** What the ledger says since midnight, in counts a person can check. */
interface HomeToday {
    actions: number;
    asked: number;
    allowed: number;
    refused: number;
}
/** The one action the record says could run without asking, and why. */
interface HomeReady {
    action: string;
    approvals: number;
    /** Who was asked, where every yes came from one agent. */
    agentName?: string;
    /** What the yeses were about; the rule it becomes names these and no others. */
    targets: string[];
    because: string;
}
/** What no rule or seam covers here, said as counts. */
interface HomeNotCovered {
    /** Agents found on this machine that run outside Memnox. */
    unprotected: number;
    /** Agents silent for a month that still hold reach. */
    dormant: number;
}
interface HomeView {
    machine: string;
    mode: string;
    waiting: number;
    working: HomeWorking[];
    today: HomeToday;
    ready?: HomeReady;
    notCovered: HomeNotCovered;
    /**
     * What only the person can do for what is here to be in force, such as approving hooks in
     * Codex or restarting an agent that loads a plugin. Absent when nothing is owed.
     */
    needsYou?: string[];
}
interface HomeResponseFields {
    /** On HOME. */
    home?: HomeView;
    /** On HAND_OVER: the proposal the person now confirms, by its id. */
    proposed?: string;
    /** On MODE_ENFORCE: the mode this machine was in and the one it is in now. */
    modeSet?: HomeModeSet;
}

/**
 * The native wrapper's half of the protocol: one command line ruled on by the daemon, so a
 * wrapped command pays a connect rather than a Node start. Anything the daemon cannot rule
 * on exactly as the Node interceptor would is answered `node`, and the Node one runs.
 */
declare const INTERCEPT_METHOD: {
    /** Rule on a whole command line, as `memnox-intercept` would before running it. */
    readonly INTERCEPT: "intercept";
    /** The client acted on the plan it was given, so the daemon may write the row for it. */
    readonly INTERCEPT_ACTED: "intercept-acted";
    /** The command the plan allowed has ended, with its exit code. */
    readonly INTERCEPT_RAN: "intercept-ran";
};
/** Bumped whenever either side changes shape; a mismatch is answered `node`. */
declare const FAST_INTERCEPT_VERSION = 1;
declare const INTERCEPT_PLAN: {
    /** Run the real binary and report how it ended, which writes the row. */
    readonly RUN: "run";
    /** Run the real binary with nothing recorded: a person typed it, or protection is stopped. */
    readonly PASS: "pass";
    /** Print the message and exit with the code given, without running anything. */
    readonly REFUSE: "refuse";
    /** Hand the same argv to the Node interceptor, which is always right. */
    readonly NODE: "node";
};
type InterceptPlanKind = (typeof INTERCEPT_PLAN)[keyof typeof INTERCEPT_PLAN];
interface InterceptRequestFields {
    /** On INTERCEPT: the protocol version the client speaks. */
    fast?: number;
    /**
     * On INTERCEPT: the binary the wrapper stands for, then its arguments. Ruled on in memory
     * and never stored or logged; the ledger keeps their digest, as on every other path.
     */
    argv?: string[];
    /** On INTERCEPT: the environment the command would run with, read the way Node would read it. */
    env?: Record<string, string>;
    /** On INTERCEPT: the directory the command runs in. */
    cwd?: string;
    /** On INTERCEPT: the client's parent, which is whatever ran the command. */
    ppid?: number;
}
interface InterceptResponseFields {
    /** On INTERCEPT: the protocol version the daemon answered in. */
    fast?: number;
    /** On INTERCEPT: what the client does next. */
    plan?: InterceptPlanKind;
    /** On RUN and PASS: the binary to run, found the way the Node interceptor finds it. */
    real?: string;
    /** On RUN and PASS: PATH for the command, with the interceptor directory taken off. */
    path?: string;
    /** On REFUSE: the exit code. */
    exitCode?: number;
    /** Lines for stderr, in order: warnings before a run, the refusal, a pause after one. */
    notes?: string[];
}
/** One INTERCEPT line, exactly as the native client writes it; the golden fixture pins it. */
interface InterceptLine {
    argv: readonly string[];
    env: readonly (readonly [string, string])[];
    cwd: string;
    ppid: number;
}
/** The bytes the native client sends, key for key, so a test can hold both sides to them. */
declare function encodeInterceptLine(line: InterceptLine): string;
declare function isInterceptMethod(method: string): boolean;

/**
 * The agents on this machine as a screen manages them: whether each runs under Memnox, its
 * sessions, its servers from the hub, and what it did today. Names only, never arguments.
 */
declare const AGENTS_METHOD: {
    /** Every agent found here, one card each. */
    readonly AGENTS: "agents";
    /** Holds one agent at once, since that only narrows. */
    readonly AGENT_PAUSE: "agent-pause";
    /** Lets a paused agent carry on, which waits on the person's signature. */
    readonly AGENT_RESUME: "agent-resume";
    /** Holds one session before its next action, at once. */
    readonly SESSION_STOP: "session-stop";
    /** Opens the agent in a new terminal in a folder, for an agent with a known launch command. */
    readonly AGENT_LAUNCH: "agent-launch";
    /**
     * Every agent the scan finds now, with the counted facts the full screen scan draws, read and never shown, so a
     * screen draws it without asking the voice. A server never asked starts one full count behind the answer.
     */
    readonly AGENTS_SCAN: "agents-scan";
};
declare const AGENT_STATUS: {
    /** Its hook is in, or every server it starts runs through Memnox, so whatever Memnox can see of it is ruled on. */
    readonly PROTECTED: "protected";
    /** Found here and running outside Memnox. */
    readonly UNPROTECTED: "unprotected";
    /** Silent for a month and still holding reach. */
    readonly DORMANT: "dormant";
    /** A person paused it; nothing it asks for runs. */
    readonly PAUSED: "paused";
};
type AgentStatus = (typeof AGENT_STATUS)[keyof typeof AGENT_STATUS];
/** What Memnox holds an agent through, which says what Protect changes for it and when that takes hold. */
declare const AGENT_SEAM: {
    /** Its own hook, which every action passes. */
    readonly HOOK: "hook";
    /**
     * Only the MCP servers it starts, as for Claude Desktop, which has no hook. It reads its config when it
     * opens, so servers put behind Memnox reach it once it is quit and opened again.
     */
    readonly SERVERS: "servers";
};
type AgentSeam = (typeof AGENT_SEAM)[keyof typeof AGENT_SEAM];
interface AgentSessions {
    running: number;
    idle: number;
    finished: number;
}
interface AgentToday {
    actions: number;
    asked: number;
    refused: number;
}
/** One thing it did lately, by name. */
interface AgentAction {
    id: string;
    at: string;
    operation: string;
    target?: string;
    effect: DecisionEffect;
}
interface AgentView {
    kind: string;
    name: string;
    status: AgentStatus;
    /** What Memnox holds it through; absent for an agent it has no way into, which stays unprotected. */
    seam?: AgentSeam;
    /** Where its binary sits: installed, or somewhere unusual. Never the path, which names the user. */
    installed?: string;
    /** Its MCP config file, where the hub found one. */
    configPath?: string;
    /** When a pause lifts on its own. */
    pausedUntil?: string;
    sessions: AgentSessions;
    /** The hub's servers given to it, by name. */
    mcpServers: string[];
    /** The Skills Hub's skills given to it, by name, whether or not they are enabled. */
    skills: string[];
    today: AgentToday;
    /** The last five, newest first. */
    recent: AgentAction[];
    /** Whether AGENT_LAUNCH can open it, which only an agent with a known launch command can. */
    launchable: boolean;
    /** The profile it works under: the one a person bound, or its own default. */
    profileId?: string;
    /** How sure Memnox is of each capability for it, from what holds it and what was proved. */
    levels?: CapabilityLevels;
}
/** What AGENT_LAUNCH asked the Mac to type, in the folder it opens on. */
interface AgentLaunched {
    agent: string;
    workingDirectory: string;
    /** The line typed into the new terminal. */
    line: string;
}
interface AgentsRequestFields {
    /** On AGENT_PAUSE, AGENT_RESUME and AGENT_LAUNCH: the agent, by kind or by the name it goes by. */
    agentKind?: string;
    /** On AGENT_LAUNCH: the folder it opens in. On EVALUATE: the folder the action runs in, whose project the daemon finds. */
    workingDirectory?: string;
}
/** What AGENTS_SCAN found: each agent with its counted facts, and the machine's real capabilities. */
interface AgentsScanView {
    agents: AgentNode[];
    /** `total` is absent while the servers are still being counted, never zero for that. */
    capabilities: CapabilityTally;
}
interface AgentsResponseFields {
    /** On AGENTS, and after a pause or a stop. */
    agentsView?: AgentView[];
    /** On AGENT_LAUNCH. */
    agentLaunched?: AgentLaunched;
    /** On AGENTS_SCAN. */
    agentsScan?: AgentsScanView;
}

/** A held call's yes bound to the exact call: the digest a screen signs, and the one it says it signed. */
interface HeldActionEventFields {
    /** On HELD, and on every held call WAITING lists: the digest a v4 confirmation signs. */
    actionDigest?: string;
}
interface HeldActionRequestFields {
    /** On CONFIRM of a held call: the digest the screen signed, so a call changed since is refused by name. */
    actionDigest?: string;
}

/**
 * Projects as every screen reads and changes them: one repository, the agents seen in it, and
 * the servers, skills, rules and instructions each agent opened there is given.
 */
declare const PROJECTS_METHOD: {
    /** Every project on this machine, opened or found, most recently active first. */
    readonly PROJECTS: "projects";
    /** Takes a folder in as a project and applies it; what widens an agent waits on a signature. */
    readonly PROJECT_OPEN: "project-open";
    /** Writes a project's `.memnox/project.toml` from a form, applying nothing until asked. */
    readonly PROJECT_PUT: "project-put";
    /** Hands the project's instructions to its agents at once, and proposes its servers, skills and rules. */
    readonly PROJECT_APPLY: "project-apply";
};
/** A server or skill the project names, and the agents here that already have it. */
interface ProjectGrantView {
    name: string;
    /** In the hub on this machine; a name the hub lacks is given to nobody. */
    inHub: boolean;
    /** Of the project's agents, those that have it now. */
    agents: string[];
}
interface ProjectRulesView {
    /** Relative to the repository, as the manifest names it. */
    file?: string;
    count: number;
    /** In the registry every seam loads. */
    inForce: boolean;
    /** Why the file would not load, when it would not. */
    problem?: string;
}
/** One file an agent reads instructions from: a source the project imports, a file Memnox writes into, or both. */
interface ProjectInstructionView {
    path: string;
    /** The project reads it as its instructions. */
    source: boolean;
    present: boolean;
    /** The agents that read this file. */
    agents: string[];
    /** Holds a block or file of Memnox's own just now. */
    written: boolean;
}
interface ProjectMissionView {
    id: string;
    statement: string;
    startedAt: string;
}
/** Where a project's setup comes from; absent is this machine's own. */
declare const PROJECT_SCOPE: {
    /** Shared by the organization in Memnox Cloud and laid over the clone, read only here. */
    readonly ORGANIZATION: "organization";
};
type ProjectScope = (typeof PROJECT_SCOPE)[keyof typeof PROJECT_SCOPE];
/** What the organization hands a shared project, its names looked up in the same bundle. */
interface ProjectOrganizationView {
    /** The cloud's id, which the project's memory is kept under. */
    id: string;
    name: string;
    /** The project's first repository, `host/owner/name`, which a screen names it by. */
    repository: string;
    /** Every repository the project spans, this clone's `origin` among them. */
    repositories: string[];
    description?: string;
    servers: string[];
    skills: string[];
    rulePack?: string;
    /** Rules the organization publishes under the rule pack. */
    rules: number;
    memory: string;
    /** Each name the bundle did not carry, said in a sentence, and left out. */
    skipped: string[];
    /** The line a local edit is refused with, for a screen to show before anybody tries. */
    editedIn: string;
}
interface ProjectView {
    id: string;
    /** `organization` where Memnox Cloud shares this repository with the person; absent is their own. */
    scope?: ProjectScope;
    /** On an organization project: what it hands, read only. */
    organization?: ProjectOrganizationView;
    name: string;
    path: string;
    /** Has a committed `.memnox/project.toml`; otherwise what is shown is found rather than declared. */
    declared: boolean;
    /** Why the committed manifest would not read, when it would not. */
    problems?: string[];
    /** Opened on this machine, which is when its instructions and grants are applied. */
    opened: boolean;
    /** The agents the manifest names, or every agent seen in it when it names none. */
    agents: string[];
    /** Agents that ran a session here, by kind. */
    agentsSeen: string[];
    sessions: {
        total: number;
        ended: number;
    };
    servers: ProjectGrantView[];
    skills: ProjectGrantView[];
    rules: ProjectRulesView;
    instructions: ProjectInstructionView[];
    memoryScope: string;
    openMissions: ProjectMissionView[];
    openQuestions: number;
    lastActive?: string;
    appliedAt?: string;
}
interface ProjectsView {
    projects: ProjectView[];
}
/** What applying did at once, and what it proposed for the person to sign. */
interface ProjectApplySummary {
    /** Instruction files written or rewritten, relative to the repository. */
    written: string[];
    /** Instruction files of ours taken out, since nothing was left to put in them. */
    removed: string[];
    /** Files a person wrote in the way of one of ours, which were left alone. */
    kept: string[];
    /** The repository's own servers put behind the proxy for Claude Code, which governs and never widens. */
    governed: string[];
    /** Names the manifest gives that the hub on this machine does not have. */
    missing: string[];
}
/** A project as a form fills it in; every list left out is empty. */
interface ProjectDraft {
    name: string;
    instructions?: string[];
    servers?: string[];
    skills?: string[];
    agents?: string[];
    policy?: string;
    memory?: string;
}
interface ProjectsRequestFields {
    /** On OPEN: the folder, absolute; on PUT, the repository the manifest is written into. */
    projectPath?: string;
    /** On APPLY. */
    projectId?: string;
    /** On PUT. */
    projectDraft?: ProjectDraft;
}
interface ProjectsResponseFields {
    /** On PROJECTS, and after every change, so a screen redraws from one answer. */
    projects?: ProjectsView;
    /** On OPEN and APPLY: what was done at once. */
    projectApplied?: ProjectApplySummary;
}

/**
 * Backing up what a person set up on this machine and restoring it: rules, hubs, skills, projects
 * and memory, sealed under a passphrase, and never a secret. Both are the local socket's alone.
 */
declare const BACKUP_METHOD: {
    /** Seals the setup under a passphrase and hands the archive back as text. */
    readonly BACKUP_CREATE: "backup-create";
    /** Opens an archive and proposes putting it back, which holds once the person signs it. */
    readonly BACKUP_RESTORE: "backup-restore";
};
/** What an archive holds, so a screen says it before anything is restored. */
interface BackupSummary {
    createdAt: string;
    /** Under the Memnox home, by path. */
    files: string[];
    /** The ledger rides along; it is only ever restored where there is none. */
    ledger: boolean;
}
interface BackupRequestFields {
    /** On CREATE and RESTORE. Never stored, never logged. */
    backupPassphrase?: string;
    /** On RESTORE: the archive as CREATE handed it back. */
    backupArchive?: string;
    /** On CREATE: carry the ledger too. */
    backupLedger?: boolean;
}
interface BackupResponseFields {
    /** On CREATE. */
    backupArchive?: string;
    /** On CREATE and RESTORE: what the archive holds. */
    backupSummary?: BackupSummary;
}

/**
 * Reaching this machine over the local network rather than the relay: off until the person turns
 * it on, the same Noise sessions either way, and only ever a private address.
 */
declare const LAN_METHOD: {
    /** Whether the local network is on, where it listens, whether it is advertised, and which phones reach it. */
    readonly LAN_STATUS: "lan-status";
    /** Turns it off at once, or proposes turning it on, which holds once the person signs it on the Mac. */
    readonly LAN_SET: "lan-set";
};
/** A paired phone with a live session over the local network now. */
interface LanPhone {
    deviceId: string;
    name: string;
}
interface LanStatus {
    /** The person's setting: off until they turn it on. */
    on: boolean;
    /** A listener is up, which also needs a private address on this machine. */
    listening: boolean;
    /** The private addresses it listens on; empty while off or with no private network. */
    addresses: string[];
    /** The port each address listens on, while listening. */
    port?: number;
    /** Announced over Bonjour as `_memnox._tcp` under a random name that says nothing of the machine. */
    advertised: boolean;
    /** That random name, which the QR carries so a phone knows which announcement is this machine. */
    instance?: string;
    reachable: LanPhone[];
}
interface LanRequestFields {
    /** On LAN_SET: true proposes turning it on, false turns it off now. */
    lanOn?: boolean;
}
interface LanResponseFields {
    /** On LAN_STATUS and LAN_SET. */
    lan?: LanStatus;
}

/**
 * Personal sync as every screen reads and drives it: one person's servers, skills, projects, rules
 * and verified memory carried blind across their own machines. It runs when asked and after a
 * local change, never on a timer, and the key moves only behind a fingerprint the Mac signs.
 */
declare const PERSONAL_SYNC_METHOD: {
    /** Where sync stands here: the key, the last run, what was left out, and any machine waiting. */
    readonly PERSONAL_SYNC_STATUS: "personal-sync-status";
    /** Pulls what the person's other machines sent, then sends what changed here. */
    readonly PERSONAL_SYNC_NOW: "personal-sync-now";
    /** The copies a sync replaced without having seen them, opened for the person to choose from. */
    readonly PERSONAL_SYNC_CONFLICTS: "personal-sync-conflicts";
    /** Keeps one side of a conflict: the copy taken back here, or this machine's own. */
    readonly PERSONAL_SYNC_RESOLVE: "personal-sync-resolve";
    /** On a machine holding the key: proposes sealing it to a waiting machine whose fingerprint the person compared. */
    readonly PERSONAL_SYNC_KEY_OFFER: "personal-sync-key-offer";
    /** On a new machine: proposes taking the key sealed to it, once the person compared the same fingerprint. */
    readonly PERSONAL_SYNC_KEY_ACCEPT: "personal-sync-key-accept";
};
/** Where personal sync stands on this machine. */
declare const PERSONAL_SYNC_STATE: {
    /** Not on Memnox Cloud, so there is nowhere to carry anything. */
    readonly OFF: "off";
    /** No sync key here yet: another of the person's machines has to seal it to this one. */
    readonly WAITING_FOR_KEY: "waiting-for-key";
    /** A key sealed to this machine arrived and waits for the person to compare and accept it. */
    readonly KEY_ARRIVED: "key-arrived";
    readonly READY: "ready";
    /** The plan does not carry personal sync; what is here stays here. */
    readonly NOT_ON_PLAN: "not-on-plan";
    /** The credential speaks for no person, so it has nothing of its own to sync. */
    readonly NO_PERSON: "no-person";
};
type PersonalSyncState = (typeof PERSONAL_SYNC_STATE)[keyof typeof PERSONAL_SYNC_STATE];
/** Which side of a conflict to keep. */
declare const SYNC_KEEP: {
    /** The copy the cloud kept, put back here and sent as the newest. */
    readonly THEIRS: "theirs";
    /** What this machine holds now; the kept copy is let go. */
    readonly MINE: "mine";
};
type SyncKeep = (typeof SYNC_KEEP)[keyof typeof SYNC_KEEP];
/** One of the person's machines, as far as the sync key goes. */
interface PersonalSyncMachine {
    machineId: string;
    /** Compared with what the other machine shows before the key moves either way. */
    fingerprint: string;
    /** Another of the person's machines already sealed the key to it. */
    sealed: boolean;
}
/** How many items of one kind this machine carries. */
interface PersonalSyncKindCount {
    kind: string;
    items: number;
}
interface PersonalSyncStatus {
    state: PersonalSyncState;
    /** Where it stands, in one sentence a screen shows as it is. */
    said: string;
    /** Which sync key this machine holds, never the key. */
    keyId?: string;
    lastSyncedAt?: string;
    kinds: PersonalSyncKindCount[];
    conflicts: number;
    /** Items left out of the last run, each said: too large, sealed under another key, or waiting on a signature. */
    skipped: string[];
    /** Repositories opened on the person's other machines and not here. */
    openedElsewhere: string[];
    /** On a machine holding the key: the person's machines still waiting for it. */
    waiting: PersonalSyncMachine[];
    /** On a machine waiting: the fingerprint of the key that arrived, to compare before accepting it. */
    arrivedFingerprint?: string;
}
/** A conflict copy opened here, beside what this machine holds of the same item now. */
interface PersonalSyncConflict {
    id: string;
    kind: string;
    name: string;
    /** Which machine wrote the copy that lost. */
    writtenBy: string;
    keptAt: string;
    /** The copy, as text a screen shows. */
    theirs: string;
    /** What this machine holds now, absent where it holds nothing by that name. */
    mine?: string;
}
interface PersonalSyncRequestFields {
    /** On RESOLVE. */
    syncConflictId?: string;
    /** On RESOLVE. */
    syncKeep?: SyncKeep;
    /** On KEY_OFFER: the waiting machine to seal the key to. */
    syncMachineId?: string;
    /** On KEY_OFFER and KEY_ACCEPT: the fingerprint the person compared, which must be the one shown. */
    syncFingerprint?: string;
}
interface PersonalSyncResponseFields {
    /** On every personal sync method, so a screen redraws from one answer. */
    personalSync?: PersonalSyncStatus;
    /** On CONFLICTS. */
    syncConflicts?: PersonalSyncConflict[];
}

/**
 * Job descriptions with no agent behind them. A template carries no activity, no session and no
 * standing; using one copies its job into a new profile, and every suggestion stays off until taken.
 */
interface ProfileTemplate {
    id: string;
    name: string;
    purpose: string;
    /** Matched by `roles:` once a profile copied from it is bound; a role grants nothing by itself. */
    role: string;
    responsibilities: string[];
    /** Skills a person may add, by name only, never installed by the template. */
    suggestedSkills: string[];
    /** Rules in plain words, shown for a person to write as rules; none is ever applied by a template. */
    suggestedRules: string[];
    /** Only agents `memnox scan` can find, so a template never names a connection nobody can make. */
    suggestedConnections: DiscoveredAgentKind[];
}
declare const PROFILE_TEMPLATES: readonly ProfileTemplate[];
declare function templateNamed(named: string): ProfileTemplate | undefined;
/** What a template copies into a new profile: its job, and only the skills a person took. */
declare function draftFromTemplate(template: ProfileTemplate, chosen: {
    name?: string;
    skills?: readonly string[];
}): ProfileDraft;

/**
 * Profiles as every screen reads and applies them: one named bundle of Skills Hub skills, MCP Hub
 * servers and a rule pack, such as Backend Engineering, kept under the Memnox home. Applying one
 * to an agent and a project raises the signed proposals each piece raises on its own.
 */
declare const PROFILES_METHOD: {
    /** Every profile kept here, with what of each the hubs no longer hold. */
    readonly PROFILES: "profiles";
    /** Adds a profile or replaces one of the same name; it grants nothing until it is applied. */
    readonly PROFILE_PUT: "profile-put";
    /** Forgets a profile; what it already handed out stays where it was given. */
    readonly PROFILE_REMOVE: "profile-remove";
    /** Proposes giving an agent the profile's servers and skills, in a project, and its rule pack's rules. */
    readonly PROFILE_APPLY: "profile-apply";
    /** Binds a kept profile to one agent found here; its ledger key stays `agt_<kind>`. */
    readonly PROFILE_BIND: "profile-bind";
    /** Takes a binding off, which puts the agent back on its default profile. */
    readonly PROFILE_UNBIND: "profile-unbind";
    /** The catalog of job descriptions, none with an agent behind it. */
    readonly TEMPLATES: "templates";
    /** Copies a template's job into a new profile, with only the suggested skills a person took. */
    readonly PROFILE_FROM_TEMPLATE: "profile-from-template";
};
/** A rule pack as a profile carries it: its name and its TOML, imported as any pack is. */
interface ProfileRulePack {
    name: string;
    toml: string;
}
/** A profile as a form fills it in. */
interface ProfileDraft {
    name: string;
    description?: string;
    /** Skills Hub skills, by name. */
    skills?: string[];
    /** MCP Hub servers, by name. */
    mcpServers?: string[];
    rulePack?: ProfileRulePack;
    /** The job, each field optional so a version 1 form still fills a profile in. */
    purpose?: string;
    role?: string;
    responsibilities?: string[];
    instructions?: string;
    responsiblePerson?: string;
    projects?: string[];
    templateOf?: string;
}
/** The job fields a profile shows beside what it bundles. */
interface ProfileJob {
    purpose?: string;
    role?: string;
    responsibilities: string[];
    instructions?: string;
    /** Who answers for it; on a view, the person at this machine when none was named. */
    responsiblePerson?: string;
    projects: string[];
    templateOf?: string;
}
interface ProfileView extends ProfileJob {
    /** The name made safe for a file, which every method names the profile by too. */
    id: string;
    name: string;
    description?: string;
    skills: string[];
    mcpServers: string[];
    /** The pack's name and how many rules it holds, never its text. */
    rulePack?: {
        name: string;
        rules: number;
    };
    updatedAt: string;
    /** Names the hubs no longer hold, or a pack that no longer loads, each in a sentence. */
    missing: string[];
    /** The agent's own default, computed for an agent nobody bound and never stored. */
    isDefault?: true;
    /** How it reaches the agents it works through; empty is a profile with no agent behind it. */
    connections: AgentConnection[];
    /** The weakest level of its connections that are not gone, so one unguarded agent is never hidden. */
    levels: CapabilityLevels;
}
/** What applying a profile raised, so a screen says it in a line and opens the cards. */
interface ProfileApplied {
    profile: string;
    agent: string;
    project?: string;
    /** Proposal ids, one per server, skill and rule, each signed on its own. */
    proposed: string[];
    /** Already given to that agent, so nothing was raised for them. */
    already: string[];
    /** Not raised, each with why. */
    skipped: string[];
}
interface ProfilesRequestFields {
    /** On PROFILE_PUT. */
    profileDraft?: ProfileDraft;
    /** On PROFILE_REMOVE, PROFILE_APPLY, PROFILE_BIND and AGENT_LAUNCH: the profile, by id or by name. */
    profileName?: string;
    /** On PROFILE_APPLY: the agent, by kind. */
    profileAgent?: string;
    /** On PROFILE_FROM_TEMPLATE: the template, by id or name; `profileName` names the copy. */
    templateId?: string;
    /** On PROFILE_FROM_TEMPLATE: the suggested skills the person took; the rest stay off. */
    templateSkills?: string[];
    /** On PROFILE_BIND and PROFILE_UNBIND: the agent, by id, kind or the name it goes by. */
    agentId?: string;
    /** On PROFILE_APPLY: the repository its skills are written into and its rules hold in, as an absolute path; absent is the home folder and the whole machine. */
    profileProject?: string;
}
interface ProfilesResponseFields {
    /** On every profile method, so a screen redraws from one answer. */
    profiles?: ProfileView[];
    /** On TEMPLATES. */
    templates?: ProfileTemplate[];
    /** On PROFILE_APPLY, and on AGENT_LAUNCH with a profile. */
    profileApplied?: ProfileApplied;
}

/** A progress note is a line for a person, not a report, so it stays this short. */
declare const MOST_PROGRESS_CHARS = 500;
/** Past this the oldest notes go, so a long piece of work cannot grow its file without end. */
declare const MOST_PROGRESS_NOTES = 50;
declare const TRACKER: {
    readonly LINEAR: "linear";
    readonly JIRA: "jira";
    readonly GITHUB: "github";
    readonly ASANA: "asana";
};
type Tracker = (typeof TRACKER)[keyof typeof TRACKER];
/** The tracker's own issue, named and never duplicated: its title is a label, not a copy. */
interface ExternalTaskRef {
    source: Tracker;
    /** `LIN-123`, `PAY-42`, `acme/api#17` or an Asana task id. */
    externalId: string;
    url?: string;
    title?: string;
}
declare const WORK_STATUS: {
    readonly ACTIVE: "active";
    readonly BLOCKED: "blocked";
    readonly HANDOFF_REQUESTED: "handoff_requested";
    /** The agent says it is done; only a person closes it. */
    readonly DONE_CLAIMED: "done_claimed";
    readonly DONE: "done";
    readonly STOPPED: "stopped";
};
type WorkStatus = (typeof WORK_STATUS)[keyof typeof WORK_STATUS];
/** Context moves by reference: the reader opens each one through its own clearance. */
declare const REF_KIND: {
    readonly FACT: "fact";
    readonly EVENT: "event";
    readonly COMMIT: "commit";
    readonly PR: "pr";
    readonly FILE: "file";
    readonly LEASE: "lease";
    readonly SESSION: "session";
};
type RefKind = (typeof REF_KIND)[keyof typeof REF_KIND];
interface WorkRef {
    kind: RefKind;
    id: string;
}
interface WorkProgress {
    at: string;
    /** The session or agent that said it, never a person, who closes or stops instead. */
    by: string;
    note: string;
    state?: WorkStatus;
    refs: WorkRef[];
}
/** One side of a handoff: an agent by its profile, or a person. */
interface HandoffParty {
    profileId?: string;
    person?: string;
}
declare const HANDOFF_STATE: {
    readonly REQUESTED: "requested";
    readonly ACCEPTED: "accepted";
    readonly DECLINED: "declined";
};
type HandoffState = (typeof HANDOFF_STATE)[keyof typeof HANDOFF_STATE];
interface WorkHandoff {
    id: string;
    from: HandoffParty;
    to: HandoffParty;
    reason: string;
    refs: WorkRef[];
    state: HandoffState;
    requestedAt: string;
    /** The person who answered, and only a person ever does. */
    decidedBy?: string;
    decidedAt?: string;
}
interface AgentWork {
    id: string;
    profileId: string;
    /** Who answers for this work: asks go to them, and the agent never holds their authority. */
    responsiblePerson: string;
    /** The person who pointed the agent at it, where that is someone else. */
    assignedBy?: string;
    target: ExternalTaskRef;
    /** The repository it is scoped to, absolute, which keeps the record in that project. */
    projectRoot?: string;
    sessions: string[];
    /** How many agents have carried it: one at the start, one more per accepted handoff. */
    attempts: number;
    status: WorkStatus;
    progress: WorkProgress[];
    handoffs: WorkHandoff[];
    createdAt: string;
    updatedAt: string;
}
/** What a person names when they start work. */
interface WorkStart {
    profileId: string;
    responsiblePerson: string;
    assignedBy?: string;
    target: ExternalTaskRef;
    projectRoot?: string;
}
declare function startedWork(start: WorkStart, now: string): AgentWork;
declare function isFinished(work: Pick<AgentWork, 'status'>): boolean;
type WorkOutcome = {
    work: AgentWork;
} | {
    refused: string;
};
/** What an agent may say about its work: a note, and blocked, carrying on, or claiming it done. */
declare function withProgress(work: AgentWork, progress: Omit<WorkProgress, 'refs'> & {
    refs?: readonly WorkRef[];
}): WorkOutcome;
/** An agent asking to hand on; nothing moves until a person answers. */
declare function withHandoffRequest(work: AgentWork, ask: {
    to: HandoffParty;
    reason: string;
    refs?: readonly WorkRef[];
    at: string;
}): WorkOutcome;
/** A person's answer: accepted moves the work to the agent or person named; declined leaves it. */
declare function withHandoffAnswer(work: AgentWork, answer: {
    handoffId: string;
    accepted: boolean;
    by: string;
    at: string;
}): WorkOutcome;
/** A person ending it: done once the agent's claim is checked, or stopped at any point. */
declare function finishedWork(work: AgentWork, how: {
    status: typeof WORK_STATUS.DONE | typeof WORK_STATUS.STOPPED;
    at: string;
}): WorkOutcome;
/** A session started under the work's profile joins it once, so the record names every session. */
declare function joinedBy(work: AgentWork, sessionId: string, at: string): AgentWork;
/** The task a session under this work is held to, so drift is measured against what was asked. */
declare function sessionTaskOfWork(work: AgentWork, sessionId: string, now: string): SessionTask;

/**
 * Agent work as a person's screen starts, stops and closes it, and answers its handoffs. The issue
 * stays in its tracker; only a reference to it is kept, and no method here can be an agent's.
 */
declare const WORK_METHOD: {
    /** Every piece of agent work kept here, newest change first. */
    readonly WORK: "agent-work";
    /** A person pointing a profile's agent at an issue: `LIN-123`, a Jira key, or an issue link. */
    readonly WORK_START: "work-start";
    /** A person stopping it, whatever the agent said. */
    readonly WORK_STOP: "work-stop";
    /** A person closing it as done, usually once the agent claimed it. */
    readonly WORK_CLOSE: "work-close";
    /** A person accepting or declining an agent's request to hand the work on. */
    readonly HANDOFF_ANSWER: "handoff-answer";
};
declare const HANDOFF_ANSWER_WORD: {
    readonly ACCEPT: "accept";
    readonly DECLINE: "decline";
};
type HandoffAnswerWord = (typeof HANDOFF_ANSWER_WORD)[keyof typeof HANDOFF_ANSWER_WORD];
interface AgentWorkRequestFields {
    /** On WORK_START: the profile whose agent carries it, by id or name. */
    workProfile?: string;
    /** On WORK_START: the issue, as a key or its link. */
    workTarget?: string;
    /** On WORK_START: which tracker a bare key is in; Linear when left out. */
    workTracker?: Tracker;
    /** On WORK_START: a title to show beside the key, never fetched. */
    workTitle?: string;
    /** On WORK_START: the repository it is scoped to, absolute, which keeps its record there. */
    workProject?: string;
    /** On WORK_STOP and WORK_CLOSE. */
    workId?: string;
    /** On HANDOFF_ANSWER. */
    handoffId?: string;
    handoffAnswer?: HandoffAnswerWord;
}
interface AgentWorkResponseFields {
    /** On every work method, so a screen redraws from one answer. */
    agentWork?: AgentWork[];
}
interface AgentWorkEventFields {
    /** On WORK: the piece of work that changed, as it now stands. */
    workChanged?: AgentWork;
}

/**
 * The part of the daemon protocol a paired phone brings: pairing, the device registry, the voice
 * a phone speaks with, and driving the Mac. `docs/remote-contract.md` is the description it follows.
 */
declare const REMOTE_METHOD: {
    /** Opens a pairing and answers the QR the Mac shows; refused while the machine is not on Memnox Cloud. */
    readonly PAIR_BEGIN: "pair-begin";
    /** Streams where a pairing stands until it is paired, declined or expired. */
    readonly PAIR_PENDING: "pair-pending";
    /** The person's yes to a device: signed by the Mac over `pairMessage`, or the device's digits where no Mac key is kept. */
    readonly PAIR_ACCEPT: "pair-accept";
    /** The person's no to a phone, unsigned since saying no can do no harm. */
    readonly PAIR_DECLINE: "pair-decline";
    readonly DEVICES_LIST: "devices-list";
    /** Takes a device's access away, unsigned since it only narrows what is allowed. */
    readonly DEVICE_REVOKE: "device-revoke";
    /** One more capability for a device, signed by the Mac over `grantMessage` wherever a Mac key is kept. */
    readonly DEVICE_GRANT: "device-grant";
    /** One capability taken back from a device, unsigned since it only narrows what is allowed. */
    readonly DEVICE_UNGRANT: "device-ungrant";
    /** The Kokoro voice the person picked on the Mac, handed to a paired phone inside the tunnel. */
    readonly VOICE_CHOICE: "voice-choice";
    /** A phone driving the Mac until a time it signed for, or stopping when it names none. */
    readonly DRIVE: "drive";
    /** A phone whose app left the screen handing the voice back to the Mac, unsigned since it only gives power up. */
    readonly VOICE_RELEASE: "voice-release";
};
/** What a remote or pairing answer settled, in the words the contract names. */
declare const REMOTE_OUTCOME: {
    readonly PAIRING: "pairing";
    readonly PAIRED: "paired";
    readonly DECLINED: "declined";
    readonly REVOKED: "revoked";
    readonly GRANTED: "granted";
    readonly UNGRANTED: "ungranted";
    readonly REFUSED: "refused";
    readonly DRIVING: "driving";
    readonly STOPPED: "stopped";
};
declare const PAIRING_STATE: {
    /** The QR is up and no phone has reached it yet. */
    readonly WAITING: "waiting";
    /** A phone finished the handshake and proved its key, and waits on the person. */
    readonly ANSWERED: "answered";
    readonly PAIRED: "paired";
    readonly DECLINED: "declined";
    readonly EXPIRED: "expired";
};
type PairingState = (typeof PAIRING_STATE)[keyof typeof PAIRING_STATE];
/** The phone that reached a pairing, with the six digits both screens show. */
interface PairingPhone {
    name: string;
    fingerprint: string;
    code: string;
}
/** A pairing as the daemon answers it: pair-begin carries the QR, pair-pending the state. */
interface PairingWire {
    id: string;
    qr?: string;
    expiresAt?: string;
    state?: PairingState;
    /** Who accepts it: the Mac's Touch ID, or the person typing the digits the device shows. */
    approver?: string;
    /** The code is left out when the person accepts by typing it, so only the device's screen has it. */
    phone?: Omit<PairingPhone, 'code'> & {
        code?: string;
    };
}
/** A device as devices-list shows it; its keys stay in the registry and never travel. */
interface DeviceWire {
    id: string;
    name: string;
    kind: string;
    fingerprint: string;
    capabilities: string[];
    pairedAt: string;
    revokedAt?: string;
    approvedBy?: string;
}
/** Who drives the Mac and until when, which the Mac island shows the whole time; no until says it ended. */
interface DrivenBy {
    deviceId: string;
    name: string;
    until?: string;
}
/** A phone's conversation as the Mac island mirrors it: what was said, the answer in pieces, then its end. */
interface PhoneTurn {
    deviceId: string;
    name: string;
    said?: string;
    answer?: string;
    ended?: boolean;
}
/** The phone that holds the voice: while it drives or talks, it speaks and the Mac only shows. */
interface VoiceHolder {
    deviceId: string;
    name: string;
}
/** A phone took the voice from the Mac or gave it back, for the Mac island to say where it went. */
interface VoiceOn extends VoiceHolder {
    holding: boolean;
}
interface RemoteRequestFields {
    /** On pair-pending, pair-accept and pair-decline. */
    pairingId?: string;
    /** On pair-accept where no Mac key is kept: the six digits the device shows, typed by the person. */
    code?: string;
    /** On device-revoke, device-grant and device-ungrant. */
    deviceId?: string;
    /** On device-grant and device-ungrant. */
    capability?: string;
    /** On voice-choice: the Kokoro voice id; left out only asks which one is set. */
    voice?: string;
    /** On pair-begin: what to call this machine on the device. */
    name?: string;
    /** On drive: when driving ends, at most fifteen minutes ahead; absent stops it. */
    until?: string;
    /** On ask: set by the daemon from the session's principal, never taken from a client. */
    origin?: {
        deviceId: string;
    };
}
interface RemoteResponseFields {
    pairing?: PairingWire;
    /** On a device's ping and in the pairing welcome: whether this machine has a Kokoro voice to lend it. */
    speaks?: boolean;
    /** On a device's ping: what this device may do here, so it never offers what would be refused. */
    capabilities?: string[];
    /** On a refused pair-accept with digits: how many more the pairing takes before it closes. */
    triesLeft?: number;
    devices?: DeviceWire[];
    device?: DeviceWire;
    voice?: string;
    /** On drive: when the grant ends. */
    until?: string;
    /** To the device that asked: what the Mac did for it, for the phone to say. */
    done?: {
        text: string;
    };
}
interface RemoteEventFields {
    /** On SHOW: only the Mac app can do it, so it goes to the Mac whoever asked. */
    needsMac?: true;
    /** On a NOTICE to the Mac: a phone drives it until then, or stopped when until is absent. */
    drivenBy?: DrivenBy;
    /** On a NOTICE to the Mac app only, never through the relay: a phone's conversation to show without a sound. */
    phoneTurn?: PhoneTurn;
    /** On any event while a phone holds the voice: that phone says it and the Mac shows it without a sound. */
    heardOn?: VoiceHolder;
    /** On a NOTICE to the Mac app only: a phone took the voice or gave it back. */
    voiceOn?: VoiceOn;
    /** On an event done for a phone's ask: the phone that asked, so the Mac stays quiet and that phone hears it. */
    origin?: {
        deviceId: string;
    };
    /**
     * On a held call or a proposal while a paired phone may answer it: that phone, which puts the yes to Face ID,
     * so the Mac leaves it there rather than putting it to Touch ID, since the person may be far from the Mac.
     */
    answerOn?: VoiceHolder;
}
/** What the Mac signs to let a phone in: the pairing and the phone's two keys. */
declare function pairMessage(pairingId: string, fingerprint: string): string;
/** What the Mac signs to give a device one more capability. */
declare function grantMessage(deviceId: string, capability: string): string;
/** What a phone signs to drive the Mac until a time. */
declare function driveMessage(deviceId: string, until: string): string;
/**
 * What a person signs to type their own words into one session, the words included so a signature
 * for one message never carries another. The Mac's key or the asking phone's, after Touch ID or Face ID.
 */
declare function followUpMessage(sessionId: string, words: string): string;
/** How a follow up reached its session, for the screen that sent it to say in its own words. */
declare const FOLLOW_UP_OUTCOME: {
    /** Working: it reads the words at its next step. */
    readonly QUEUED: "queued";
    /** Waiting at its prompt: the Mac is typing the words in and sending them. */
    readonly TYPED: "typed";
    /** Waiting where nothing can type: it reads the words the next time it is prompted. */
    readonly LATER: "later";
};
type FollowUpOutcome = (typeof FOLLOW_UP_OUTCOME)[keyof typeof FOLLOW_UP_OUTCOME];
/** What a phone signs at pairing to prove it holds the key it sent. */
declare function deviceProofMessage(handshakeHash: Buffer): string;

/**
 * The part of the daemon protocol that says one line in the person's Kokoro voice, rendered on the
 * Mac and played by whoever asked, so a phone in the background, where iOS allows no GPU, still
 * speaks with the voice the person chose.
 */
declare const SPEECH_METHOD: {
    /** One line rendered by the Mac app's Kokoro server, streamed back as pieces of PCM. */
    readonly SPEAK: "speak";
};
/** A piece of the rendered line: little endian signed 16 bit mono PCM, base64, at `rate`. */
interface AudioPiece {
    rate: number;
    samples: string;
    /** The line's final piece, which may still carry samples. */
    last: boolean;
}
interface SpeechRequestFields {
    /** On SPEAK: the one sentence to say. The Kokoro voice is `voice`, absent for the Mac's own. */
    line?: string;
    /** On SPEAK: how fast to say it, held to a sane range; absent is the Mac's unhurried pace. */
    speed?: number;
}
interface SpeechResponseFields {
    /** On SPEAK, one per line in order until a piece whose `last` is true. */
    audio?: AudioPiece;
}

/**
 * A rule a person says on the phone or the Mac, drafted by the daemon and read back before
 * anything is written: the phone asks again with the answers, then confirms the proposal it got.
 */
declare const SPOKEN_RULE_METHOD: {
    /** One sentence drafted into a rule; with no open question left it is proposed for Touch ID or Face ID. */
    readonly RULE: "rule";
};
/** Who drafted it, said out loud so a model's guess never reads as the grammar's reading. */
declare const RULE_DRAFTED_BY: {
    readonly PATTERN: "pattern";
    readonly MODEL: "model";
};
type RuleDraftedBy = (typeof RULE_DRAFTED_BY)[keyof typeof RULE_DRAFTED_BY];
interface SpokenRuleAnswer {
    draft: SpokenRuleDraft;
    /** The rule in plain words, to be said back before the person confirms. */
    readBack: string;
    /** What the sentence left for the person; nothing is proposed while any is open. */
    openQuestions: string[];
    draftedBy: RuleDraftedBy;
    /** Said beside a draft the workspace's grammar read, such as on a plan that drafts with no model. */
    note?: string;
    /** The proposal to confirm with the usual CONFIRM, once nothing is left open. */
    proposed?: string;
    /** Whether confirming also offers it to the team, where a second admin approves it. */
    offeredToTeam: boolean;
}
interface SpokenRuleRequestFields {
    /** On RULE: the destinations the person named as approved, joined by commas, answering that question. */
    approved?: string;
}
interface SpokenRuleResponseFields {
    /** On RULE, the draft and either its open questions or the proposal to confirm. */
    rule?: SpokenRuleAnswer;
    /** On a refused RULE: the workspace's plan drafts with its grammar alone, so the phone offers the upgrade. */
    upgrade?: boolean;
}

/**
 * Questions a team routed to the person reach only the devices that hold their sign in, never this
 * machine. A device names them when it asks the voice, so "allow it" can mean one of them, and the
 * answer goes back to that device as a proposal it carries out with the workspace.
 */
/** A question the team routed to the person, as a device tells the voice about it. */
interface TeamCallBrief {
    /** The workspace's id for the call, the subject a device signs a yes over. */
    id: string;
    /** "Codex on build-box, from Ana's team", the same label every door shows. */
    label: string;
    /** What it wants, in plain words. */
    what: string;
}
/** On a proposal: the answer a device carries out with the workspace before it confirms here. */
interface TeamAnswerBrief {
    callId: string;
    answer: string;
    label: string;
}

/**
 * What the Mac draws for the person's own tools: the icons of the tools they still have to sign in
 * to, and a draft of what is about to go out in their name, drawn the way that tool draws it, Slack
 * as a message, GitHub as a review comment, Gmail as a mail, read whole before Touch ID sends it.
 */
/** A tool the person asked for and has not signed in to, with the page that signs them in. */
interface ToolSignIn {
    toolkit: string;
    url: string;
    /** Signed in before as somebody else's account, so this is to sign in again with their own. */
    again?: boolean;
}
/** A sign in that finished, or never did, as the notch and the voice are told of it. */
interface SignedIn {
    toolkit: string;
    /** The account it reached; absent on a sign in that never finished. */
    account?: WorkAccount;
    /** What the person asked for before they signed in, asked again so it carries on. */
    resume?: string;
    /** Where nothing ties the account to them: the proposal "that's me" confirms, and "not me" declines. */
    confirm?: string;
}
/** Whether the account a sign in reached is known to be the person's own. */
declare const WORK_ACCOUNT_CHECK: {
    readonly MATCHED: "matched";
    readonly UNVERIFIED: "unverified";
    readonly MISMATCH: "mismatch";
    readonly UNKNOWN: "unknown";
};
type WorkAccountCheck = (typeof WORK_ACCOUNT_CHECK)[keyof typeof WORK_ACCOUNT_CHECK];
/** The account something goes out as, as the tool itself named it. */
interface WorkAccount {
    /** The id the control plane checks the run against, so a sign in changed since is refused. */
    key?: string;
    handle?: string;
    name?: string;
    check: WorkAccountCheck;
}
/** What kind of thing is drafted, which decides how the card is laid out. */
declare const WORK_DRAFT_KIND: {
    readonly MESSAGE: "message";
    readonly COMMENT: "comment";
    readonly EMAIL: "email";
    readonly ISSUE: "issue";
    readonly EVENT: "event";
    readonly PAGE: "page";
    readonly OTHER: "other";
};
type WorkDraftKind = (typeof WORK_DRAFT_KIND)[keyof typeof WORK_DRAFT_KIND];
interface WorkField {
    name: string;
    value: string;
}
/** Something about to go out in the person's name, as the Mac draws it before they confirm. */
interface WorkDraft {
    toolkit: string;
    tool: string;
    kind: WorkDraftKind;
    account?: WorkAccount;
    /** Who it goes to: people, addresses or a channel. A mail always shows its real addresses here. */
    to?: string[];
    /** On a mail, the name the voice found for whom it goes to, shown beside the address and never in its place. */
    toName?: string;
    /** On a mail, the person may rewrite its addresses on the card, which their Touch ID then covers. */
    toEditable?: boolean;
    /** Where it lands: `owner/repo#412`, an issue, a page. */
    where?: string;
    subject?: string;
    body?: string;
    /** On an event, when it starts and ends as the tool was given them, so the card shows the time it books. */
    starts?: string;
    ends?: string;
    /** Every other argument, as text, so nothing goes out that the card did not show. */
    fields: WorkField[];
}
/** What the card shows beside the arguments: whose account it goes out as and who it goes to by name. */
interface WorkDraftExtras {
    account?: WorkAccount;
    toName?: string;
}
/** The draft of one tool call, laid out from its slug and arguments, with nothing left off. */
declare function workDraftOf(toolkit: string, tool: string, args: Record<string, unknown>, { account, toName }?: WorkDraftExtras): WorkDraft;
/**
 * The arguments with the person's own words in place of the body the card showed, or null where the body
 * is not plain text or there is none, so an edit never lands in an argument the card did not draw as words.
 */
declare function editedArguments(argumentsText: string, edited: string): string | null;
/**
 * The arguments of a mail with the addresses the person typed on its card in place of the proposed ones, in the
 * shape the tool took them, or null where the toolkit is no mail, an address is malformed, or a single address
 * argument would be handed several.
 */
declare function editedRecipients(toolkit: string, argumentsText: string, editedTo: string): string | null;
/** Who a send in the person's name goes to, read off the arguments it went with, so "who did it go to" is fact. */
declare function recipientsOf(toolkit: string, tool: string, argumentsText: string, toName?: string): string[];
/** The draft of one tool call from the arguments as proposed text; text that is no object draws only the tool. */
declare function workDraftFromText(toolkit: string, tool: string, argumentsText: string, extras?: WorkDraftExtras): WorkDraft;
/** One plain address, refusing the colon, comma and space that would make the signed text read two ways. */
declare function isAddress(text: string): boolean;

/**
 * The fields each part of the protocol adds, gathered in one place so the core protocol reads as
 * its own few methods and a new part is one line here rather than a longer list there.
 */
interface TeamRequestFields {
    /** On ASK from a device signed in to its team: the team's questions waiting on the person. */
    teamCalls?: TeamCallBrief[];
}
interface TeamEventFields {
    /** On a PROPOSAL answering a team's question, which the device carries out with the workspace. */
    teamAnswer?: TeamAnswerBrief;
}
interface ProposalEventFields {
    /** On a PROPOSAL, what kind of change it is, a PROPOSAL_KIND value, so a surface words each kind its own way. */
    proposalKind?: string;
}
interface WorkRequestFields {
    /** On CONFIRM of a draft: the words the person rewrote on its card, which the signature then covers. */
    edited?: string;
    /** On CONFIRM of a mail: the addresses the person typed on its card, joined by commas, which the signature covers too. */
    editedTo?: string;
}
interface QuestionRequestFields {
    /** On CONFIRM of an agent's question: which of its questions the answer is for, from one. */
    questionNumber?: number;
}
interface QuestionEventFields {
    /** On a question NOTICE: what the agent asked with its choices, so a notch or a phone offers them as taps. */
    questions?: AgentQuestionItem[];
    /** On a question NOTICE: what is already picked, by question text, so a surface asks only what is left. */
    answers?: Record<string, string>;
}
interface SubscribeRequestFields {
    /** On SUBSCRIBE: send ACTIVITY too; asked for, since an app built before it would say every row aloud. */
    subscribeActivity?: boolean;
    /** On SUBSCRIBE: send WORK too, asked for for the same reason. */
    subscribeWork?: boolean;
}
interface AccountRequestFields {
    /** On PERSON_SIGN_IN: the Mac app's own waiting device code, so one approval signs both in. */
    companionOf?: string;
}
interface WorkEventFields {
    /** On a PROPOSAL to act in one of the person's tools, what goes out, drawn the way that tool draws it. */
    work?: WorkDraft;
    /** On SIGN_IN, the tools the person asked for and has not signed in to, each with its page. */
    signIn?: ToolSignIn[];
    /** On a PROPOSAL of `work`, raised by a working agent through Memnox rather than by the voice, so its card waits for Send unasked. */
    agentAsked?: true;
    /** On a PROPOSAL that an account is the person's own, answered from the signed in pill. */
    claim?: {
        toolkit: string;
        label: string;
    };
    /** On a SIGNED_IN or SIGN_IN_STALLED notice, which tool, as whom, and what to carry on with. */
    signedIn?: SignedIn;
}
interface ExtensionRequestFields extends RemoteRequestFields, FilesRequestFields, SpeechRequestFields, TeamRequestFields, WorkRequestFields, AccountRequestFields, SubscribeRequestFields, QuestionRequestFields, ConnectionsRequestFields, InterceptRequestFields, SpokenRuleRequestFields, McpHubRequestFields, PolicyRequestFields, ActivityRequestFields, AgentsRequestFields, SkillsRequestFields, HeldActionRequestFields, ProjectsRequestFields, BackupRequestFields, MemoryRequestFields, LanRequestFields, PersonalSyncRequestFields, ProfilesRequestFields, AgentWorkRequestFields, IndexRequestFields {
}
interface ExtensionResponseFields extends RemoteResponseFields, FilesResponseFields, SpeechResponseFields, HomeResponseFields, ConnectionsResponseFields, InterceptResponseFields, SpokenRuleResponseFields, McpHubResponseFields, PolicyResponseFields, ActivityResponseFields, AgentsResponseFields, SkillsResponseFields, ProjectsResponseFields, BackupResponseFields, MemoryResponseFields, LanResponseFields, PersonalSyncResponseFields, ProfilesResponseFields, AgentWorkResponseFields, IndexResponseFields {
}
interface ExtensionEventFields extends RemoteEventFields, TeamEventFields, WorkEventFields, QuestionEventFields, HeldActionEventFields, ProposalEventFields, ActivityEventFields, AgentWorkEventFields {
}

/**
 * Sessions as the Mac's switcher and live window show them: the cards, the view of one, and the
 * lines of its conversation, carried by the daemon protocol's SESSIONS_LIST and SESSION_VIEW answers.
 */
/** Who said a line of a session's conversation. */
declare const SPEAKER: {
    readonly PERSON: "person";
    readonly AGENT: "agent";
    /** A tool the agent ran, by its name and what it was for. */
    readonly TOOL: "tool";
};
type Speaker = (typeof SPEAKER)[keyof typeof SPEAKER];
/** A line of the conversation itself, as the live window shows it. */
interface ConversationLine {
    at: string;
    who: Speaker;
    text: string;
}
/** A session as one card in the switcher: who, on what, in what state, and where it runs. */
interface SessionCard {
    sessionId: string;
    /** Which agent it is, such as claude-code, so a screen can show its logo and keep its colour. */
    agent: string;
    agentName: string;
    task?: string;
    /**
     * What the session is about now, as its agent titles it, which a screen shows before the
     * task: the first thing asked is rarely what a long session turned into.
     */
    focus?: string;
    state: string;
    thinking: boolean;
    repository?: string;
    runningIn?: string;
    /** Where in that app, in words: a Terminal tab, an editor's terminal, or an agent's panel in it. */
    where?: string;
    lastActive?: string;
    /**
     * When the person last wrote to it themselves, so "the last session" is the one they last worked in
     * rather than whichever agent last ran a tool on its own.
     */
    spokenToAt?: string;
    /** When it began, so sessions can be told apart by the order they were started in. */
    startedAt?: string;
    /** What it has run, so a session that only said hello is never taken for the last one that worked. */
    actions?: number;
    host?: DisplayHost;
}
/** One thing a session did, as the live window lists it. */
interface SessionViewStep {
    at: string;
    /** shell, file, network, mcp, git, or whatever surface the action was on. */
    surface: string;
    /** What it did, in a line: the operation and its target. */
    text: string;
    /** It failed, or was refused, which the window marks. */
    failed?: boolean;
    refused?: boolean;
}
/** A session as it is right now: what it is on, what it just did, and what it changed. */
interface SessionView {
    sessionId: string;
    agent: string;
    agentName: string;
    /** What it was opened for: the task it was given, or the person's first request in it. */
    task?: string;
    /** The person's latest request in it, when it differs from the task, so a card says what it is on now. */
    lastAsk?: string;
    /** working, open, idle, quiet, ended or paused, as the sessions list says it. */
    state: string;
    /** Thinking through a turn even when nothing new is recorded. */
    thinking: boolean;
    repository?: string;
    /** The branch its repository has checked out. */
    branch?: string;
    runningIn?: string;
    /** Where in that app, in words: a Terminal tab, an editor's terminal, or an agent's panel in it. */
    where?: string;
    startedAt?: string;
    lastActive?: string;
    waitingOnYou: number;
    paused?: string;
    /** What its helpers are doing, one line each. */
    helpers: string[];
    /** Newest last, a dozen at most. */
    steps: SessionViewStep[];
    files: CardFile[];
    /** The changed lines of the file it changed most, so the code it is writing can be shown. */
    excerpt?: CardExcerpt;
    /** The conversation's latest lines, where the agent keeps a transcript Memnox can read. */
    conversation?: ConversationLine[];
    /** What the agent said to end its latest turn, cut short, which is where the work stands. */
    lastSaid?: string;
}
/** A file on a summary card, with its lines added and removed; a binary file has no counts. */
interface CardFile {
    path: string;
    added?: number;
    removed?: number;
}
/** A few changed lines of one file, so the card shows the code itself and not only its name. */
interface CardExcerpt {
    path: string;
    lines: string[];
}
/** Where a session runs, as far as its hook could see: the app, its terminal tab and its folder. */
interface DisplayHost {
    app?: string;
    appPath?: string;
    tty?: string;
    cwd?: string;
    /**
     * The agent's own id for the conversation, which is what an editor's agent panel opens by,
     * where Memnox keyed the session by another.
     */
    conversation?: string;
    /** Lines only this session's tab shows, so the Mac can find it among a terminal app's tabs by what is in it. */
    marks?: string[];
}

/**
 * A line-delimited JSON protocol over a Unix socket, or a named pipe on Windows, kept small
 * because an interceptor asks on every command, so asking has to cost a connect and a line.
 */

declare const DAEMON_METHOD: {
    readonly INDEX_LIST: "index-list";
    readonly INDEX_INSTALL: "index-install";
    readonly INDEX_SOURCE_SET: "index-source-set";
    readonly WORK: "agent-work";
    readonly WORK_START: "work-start";
    readonly WORK_STOP: "work-stop";
    readonly WORK_CLOSE: "work-close";
    readonly HANDOFF_ANSWER: "handoff-answer";
    readonly PROFILES: "profiles";
    readonly PROFILE_PUT: "profile-put";
    readonly PROFILE_REMOVE: "profile-remove";
    readonly PROFILE_APPLY: "profile-apply";
    readonly PROFILE_BIND: "profile-bind";
    readonly PROFILE_UNBIND: "profile-unbind";
    readonly TEMPLATES: "templates";
    readonly PROFILE_FROM_TEMPLATE: "profile-from-template";
    readonly PERSONAL_SYNC_STATUS: "personal-sync-status";
    readonly PERSONAL_SYNC_NOW: "personal-sync-now";
    readonly PERSONAL_SYNC_CONFLICTS: "personal-sync-conflicts";
    readonly PERSONAL_SYNC_RESOLVE: "personal-sync-resolve";
    readonly PERSONAL_SYNC_KEY_OFFER: "personal-sync-key-offer";
    readonly PERSONAL_SYNC_KEY_ACCEPT: "personal-sync-key-accept";
    readonly LAN_STATUS: "lan-status";
    readonly LAN_SET: "lan-set";
    readonly MEMORY_LAYERS: "memory-layers";
    readonly MEMORY_LAYERS_PLAN: "memory-layers-plan";
    readonly MEMORY_LAYERS_APPLY: "memory-layers-apply";
    readonly SESSION_COST: "session-cost";
    readonly MEMORY_SOURCES: "memory-sources";
    readonly MEMORY_SOURCE_ADD: "memory-source-add";
    readonly MEMORY_SOURCE_REMOVE: "memory-source-remove";
    readonly MEMORY_SOURCE_READ: "memory-source-read";
    readonly MEMORY_LEARN: "memory-learn";
    readonly MEMORY_CONFIRM: "memory-confirm";
    readonly MEMORY_REJECT: "memory-reject";
    readonly MEMORY_EDIT: "memory-edit";
    readonly MEMORY_SEARCH: "memory-search";
    readonly MEMORY_FACTS: "memory-facts";
    readonly MEMORY_FORGET: "memory-forget";
    readonly WORKSPACE_MEMORY: "workspace-memory";
    readonly WORKSPACE_GRAPH: "workspace-graph";
    readonly BACKUP_CREATE: "backup-create";
    readonly BACKUP_RESTORE: "backup-restore";
    readonly PROJECTS: "projects";
    readonly PROJECT_OPEN: "project-open";
    readonly PROJECT_PUT: "project-put";
    readonly PROJECT_APPLY: "project-apply";
    readonly SKILLS_HUB: "skills-hub";
    readonly SKILL_IMPORT: "skill-import";
    readonly SKILL_PUT: "skill-put";
    readonly SKILL_ASSIGN: "skill-assign";
    readonly SKILL_DISABLE: "skill-disable";
    readonly SKILL_ENABLE: "skill-enable";
    readonly SKILL_SYNC: "skill-sync";
    readonly SKILL_ROLLBACK: "skill-rollback";
    readonly SKILL_ACCEPT: "skill-accept";
    readonly SKILL_REMOVE: "skill-remove";
    readonly SKILL_STATS: "skill-stats";
    readonly SKILL_NOTE: "skill-note";
    readonly SKILL_CALIBRATE: "skill-calibrate";
    readonly AGENTS: "agents";
    readonly AGENT_PAUSE: "agent-pause";
    readonly AGENT_RESUME: "agent-resume";
    readonly SESSION_STOP: "session-stop";
    readonly AGENT_LAUNCH: "agent-launch";
    readonly AGENTS_SCAN: "agents-scan";
    readonly ACTIVITY: "activity";
    readonly DECISION: "decision";
    readonly ACTIVITY_EXPORT: "activity-export";
    readonly POLICY_RULES: "rules";
    readonly RULE_PROPOSE: "rule-propose";
    readonly RULE_REMOVE: "rule-remove";
    readonly RULE_TEST: "rule-test";
    readonly RULES_EXPORT: "rules-export";
    readonly RULE_PACK_IMPORT: "rule-pack-import";
    readonly RULE_PACKS: "rule-packs";
    readonly PROGRESS: "progress";
    readonly AUTOPILOT_REVOKE: "autopilot-revoke";
    readonly HUB: "mcp-hub";
    readonly SERVER_PUT: "mcp-server-put";
    readonly SERVER_REMOVE: "mcp-server-remove";
    readonly ASSIGN: "mcp-assign";
    readonly IMPORT: "mcp-import";
    readonly SYNC: "mcp-sync";
    readonly TEST: "mcp-test";
    readonly SECRET_SET: "mcp-secret-set";
    readonly SECRET_REMOVE: "mcp-secret-remove";
    readonly RULE: "rule";
    readonly INTERCEPT: "intercept";
    readonly INTERCEPT_ACTED: "intercept-acted";
    readonly INTERCEPT_RAN: "intercept-ran";
    readonly HOME: "home";
    readonly HAND_OVER: "hand-over";
    readonly MODE_ENFORCE: "mode-enforce";
    readonly SPEAK: "speak";
    readonly PAIR_BEGIN: "pair-begin";
    readonly PAIR_PENDING: "pair-pending";
    readonly PAIR_ACCEPT: "pair-accept";
    readonly PAIR_DECLINE: "pair-decline";
    readonly DEVICES_LIST: "devices-list";
    readonly DEVICE_REVOKE: "device-revoke";
    readonly DEVICE_GRANT: "device-grant";
    readonly DEVICE_UNGRANT: "device-ungrant";
    readonly VOICE_CHOICE: "voice-choice";
    readonly DRIVE: "drive";
    readonly VOICE_RELEASE: "voice-release";
    /** Rule on one action. The hot path, and the only one with a latency budget. */
    readonly EVALUATE: "evaluate";
    /** Ask a person, through whatever terminal the daemon owns. */
    readonly HOLD: "hold";
    /** Record how a command ended, so a session is one timeline and the breaker can count outcomes. */
    readonly RECORD: "record";
    /** Whether this session is held, asked before anything runs. */
    readonly STATUS: "status";
    /** Liveness, for `memnox doctor`. */
    readonly PING: "ping";
    /** Keeps the connection open and writes one line per thing that starts waiting on a person. */
    readonly SUBSCRIBE: "subscribe";
    /** What is waiting on a person right now: held calls and proposals. */
    readonly WAITING: "waiting";
    /** A person's answer to a held call or a proposal; a yes carries a signature unless the call stays within its session. */
    readonly CONFIRM: "confirm";
    /** The public half of the key a confirmation is signed with, trusted on first use. */
    readonly REGISTER_KEY: "register-key";
    /** What the person said, answered by their own agent CLI one chunk per line as it streams. */
    readonly ASK: "ask";
    /** Stops the answer in flight, usually because the person started talking over it. */
    readonly CANCEL: "cancel";
    /** Where a session's agent is on screen, so the Mac app can bring that window forward. */
    readonly LOCATE: "locate";
    /** Something happened rather than was asked: the brain says it, streamed like ASK. */
    readonly BRIEF: "brief";
    /** The person started talking: start the brain now so the answer skips the cold start. */
    readonly WARM: "warm";
    /** The names this machine uses, for the recognizer to listen for. */
    readonly VOCABULARY: "vocabulary";
    /** A session as it is right now, for the live window the Mac app opens on it. */
    readonly SESSION_VIEW: "session-view";
    /** The sessions lately, each as a card, for the switcher that turns through them. */
    readonly SESSIONS_LIST: "sessions-list";
    /** The Mac app saying whether an instruction it was asked to type landed, so nobody is told it did when it did not. */
    readonly DELIVERED: "delivered";
    /** The Mac app's own timings for the question just answered: hearing, waiting for the end, speaking. */
    readonly TRACE: "trace";
    /** Which of the person's agents can be the voice, and why the others cannot. */
    readonly VOICE_AGENTS: "voice-agents";
    /** The person picking which agent the voice thinks with, from the Mac app's settings. */
    readonly CHOOSE_VOICE_AGENT: "choose-voice-agent";
    /** Words the person fixed in what the Mac typed for them, kept so they are heard right next time. */
    readonly LEARN_WORDS: "learn-words";
    /** The Mac app answering a LOOK display with what was on screen: a capture and the window's outline. */
    readonly SEEN: "seen";
    /** One folder under the person's home, names and sizes only, so a phone browses the Mac without the brain or the screen. */
    readonly FILES_LIST: "files-list";
    /** Whether a person is signed in on this daemon, which is what the voice and the terminal act through. */
    readonly PERSON: "person";
    /** The Mac app starting the daemon's own sign in, which answers with the code and polls behind it. */
    readonly PERSON_SIGN_IN: "person-sign-in";
    /** The Mac app signing the daemon's person out, revoking this terminal on the control plane. */
    readonly PERSON_SIGN_OUT: "person-sign-out";
    /** The apps the person connected through the workspace, Gmail or Slack say, for the Mac's menu bar and notch. */
    readonly CONNECTIONS_LIST: "connections-list";
    /** Connecting one tool as the person, any toolkit and any role: answers its sign in page, opened on the Mac when asked there. */
    readonly CONNECTIONS_SIGN_IN: "connections-sign-in";
    /** Undoing every sign in the person made to one tool, answering the list as it now stands. */
    readonly CONNECTIONS_SIGN_OUT: "connections-sign-out";
    /** The tools anybody can connect, from the cloud's catalogue, so a screen offers more than the ones already known. */
    readonly TOOLKITS_SEARCH: "toolkits-search";
    /** Whether this machine is connected to a workspace, which is what carries rules, memory and phones to it. */
    readonly MACHINE: "machine";
    /** The Mac app connecting this machine to a workspace: the device flow `memnox login` runs, polled behind the answer. */
    readonly MACHINE_SIGN_IN: "machine-sign-in";
    /** The Mac app disconnecting this machine, which forgets its credential; rules already pulled stay in force. */
    readonly MACHINE_SIGN_OUT: "machine-sign-out";
    /** Dictation written the way the person would have typed it, by their own agent CLI kept warm for it. */
    readonly POLISH: "polish";
    /** Starts the process that polishes dictation, as the key goes down, so the answer skips its cold start. */
    readonly POLISH_WARM: "polish-warm";
    /** The person's own words typed into one session, verbatim and never read by the brain; signed over `followUpMessage` only at the Mac. */
    readonly FOLLOW_UP: "follow-up";
};
type DaemonMethod = (typeof DAEMON_METHOD)[keyof typeof DAEMON_METHOD];
interface DaemonRequest extends ExtensionRequestFields {
    id: number;
    method: DaemonMethod;
    /**
     * The session the request is about. On ASK: the session the person has open on the phone,
     * which the brain treats as the one they follow up on; it names a session and grants nothing.
     * On FOLLOW_UP: the session the words are typed into.
     */
    sessionId?: string;
    agent?: string;
    action?: string;
    target?: string;
    /** On EVALUATE: what the payload carries that is sensitive, as `classificationLabel` names it, for a rule's `dataClassifications`. */
    dataClassification?: string;
    /** A digest. Arguments travel only on INTERCEPT, ruled on in memory and never kept. */
    argsDigest?: string;
    reason?: string;
    /** On RECORD: how the command ended. The breaker's error and progress signals. */
    exitCode?: number;
    /** On RECORD: whether it fell outside the declared task. */
    outOfScope?: boolean;
    /** On RECORD: only the drift is being reported, so nothing is charged or counted as done. */
    driftOnly?: boolean;
    /** On RECORD: what it cost, when a surface can report one. Never estimated. */
    costUsd?: number;
    /** On CONFIRM: the held call or proposal being answered. */
    subject?: string;
    /** On CONFIRM: a hold answer for a held call, or confirmed / declined for a proposal. */
    answer?: string;
    /** On CONFIRM: base64 DER ECDSA over the confirmation message. Absent on a refusal. On FOLLOW_UP at the Mac: over `followUpMessage`, since a phone is known by its Noise session. */
    signature?: string;
    /** On REGISTER_KEY: the base64 X9.63 P-256 point. */
    point?: string;
    /** On ASK: what the person said, whole, in their own words. On FOLLOW_UP: what they typed, sent as it is. */
    said?: string;
    /** On ASK: they were waited on for the rest and said nothing more, so `said` is the whole of it. */
    finished?: boolean;
    /** On ASK: how the person asked, chosen by the keys they held rather than by any word they said. */
    intent?: AskIntent;
    /** On ASK: the Mac already greeted them out loud this sitting, so the answer does not open with another hello. */
    greeted?: boolean;
    /** On POLISH: where it lands (email, work_chat, prompt...), the person's spellings, and text they selected. */
    family?: string;
    vocabulary?: string[];
    selection?: string;
    /**
     * On ASK: what they have said so far, sent at a pause before the Mac is sure they finished,
     * so the answer can start early. Nothing of it is said until an ask with the same words.
     */
    speculative?: boolean;
    /** On LEARN_WORDS: each word as it was typed and as the person corrected it. */
    learned?: {
        heard: string;
        meant: string;
    }[];
    /** On ASK: the app in front of the person as they spoke, by name, so a misheard word is read against it. */
    lookingAt?: string;
    /** On ASK: the title of that app's window in front, which names the project an editor has open. */
    lookingAtWindow?: string;
    /** On any voice request: the name the person asked to be called. */
    owner?: string;
    /** On BRIEF: held, paused or back. */
    briefing?: string;
    /** On BRIEF back: when the person went away. */
    since?: string;
    /** On TRACE: the Mac's own steps for the question just answered. */
    spans?: MacSpan[];
    /** On VOICE_AGENTS: ask every installed agent again rather than answer from the last check. */
    recheck?: boolean;
    /** On CHOOSE_VOICE_AGENT: the agent's kind, such as cursor. */
    voiceAgent?: string;
    /** On DELIVERED: what the Mac read back after acting, which a verified outcome must carry. */
    proof?: DeliveryProof;
    /** On DELIVERED: the Mac already said out loud what the person has to do, so the brain adds nothing. */
    told?: boolean;
    /** On SEEN: what was on screen when the brain asked to look. */
    sight?: Sight;
    /** On delivered: the target's window just before and just after acting, with the words read off it. */
    evidence?: Witness;
}
/** One agent as the voice's settings show it: there or not, whether it answered, and whether it is the one. */
interface VoiceAgentStatus {
    kind: string;
    label: string;
    installed: boolean;
    /** Kept to reading; one that is not is used only when nothing else answered. */
    sealed: boolean;
    /** Absent until it has been asked, true once it called a Memnox tool and said what it was asked to. */
    works?: boolean;
    /** Why it did not, in words a person can act on. */
    because?: string;
    /** Its own account's words when it answered something else, such as a spent plan or a missing model. */
    reply?: string;
    checkedAt?: string;
    chosen: boolean;
    /** What to install, or set up, when it is missing or cannot answer. */
    install: string;
}
/** One app the person connected through the workspace, by the cloud's lowercase toolkit slug. */
interface ToolConnection {
    toolkit: string;
    /** Whether any of their sign ins to it is active and enabled, rather than pending, expired, failed or turned off. */
    connected: boolean;
    /** Reached on this machine itself, an MCP server or a signed in command line tool, so nothing is connected or disconnected here. */
    local?: true;
    /** When its working sign in was made, as the cloud says, for a card's "Connected since". */
    connectedAt?: string;
    /** The agents that worked in it through Memnox lately, newest first, from this machine's ledger. */
    usedBy?: AppUse[];
}
/** One agent's latest call into an app through Memnox: who, in which session, and when. */
interface AppUse {
    agent: string;
    sessionId?: string;
    at: string;
}
/** A step the Mac timed, hung on the trace of the question it belongs to. */
interface MacSpan {
    name: string;
    startAt: string;
    endAt: string;
    attributes?: Record<string, string | number | boolean>;
}
declare const BRIEFING: {
    /** A held call, told with what its session has been doing. */
    readonly HELD: "held";
    /** A session the breaker stopped. */
    readonly PAUSED: "paused";
    /** The person came back to their Mac. */
    readonly BACK: "back";
    /** Something worth telling without being asked: a session finished, committed or pushed. */
    readonly NOTICE: "notice";
};
/** Where a session runs, as LOCATE answers it. */
interface DaemonLocation {
    sessionId: string;
    agent: string;
    /** False once the agent's process has ended, so nothing is shown that is gone. */
    alive: boolean;
    app?: string;
    appPath?: string;
    tty?: string;
    cwd?: string;
}
/** Kinds an ASK chunk ends a turn with; anything else is more of the same turn. */
declare const ASK_ENDS: readonly string[];
/** One piece of an answer: words to speak, a tool being read, or how the turn ended. */
interface DaemonAskChunk {
    kind: string;
    text?: string;
    tool?: string;
}

declare const DAEMON_EVENT: {
    /** A call is held until a person answers it. */
    readonly HELD: "held";
    /** Something suggested a change a person has to confirm. */
    readonly PROPOSAL: "proposal";
    /** The breaker stopped a session. */
    readonly PAUSED: "paused";
    /** Something told before is no longer waiting: answered elsewhere, or expired. */
    readonly SETTLED: "settled";
    /** The person asked to see a session: its window brought forward, or its summary on a card. */
    readonly SHOW: "show";
    /** Something worth saying unasked: a session finished, committed or pushed. */
    readonly NOTICE: "notice";
    /** Rows the ledger gained that a screen's activity view shows, names only, a burst at most once a second. */
    readonly ACTIVITY: "activity";
    /** A piece of agent work changed: started, reported on, handed on, stopped or closed. */
    readonly WORK: "work";
};
type DaemonEventKind = (typeof DAEMON_EVENT)[keyof typeof DAEMON_EVENT];
/** One thing a person may want to hear about, in words that can be spoken as they are. */
interface DaemonEvent extends ExtensionEventFields {
    kind: DaemonEventKind;
    /** The id a CONFIRM names: a pending id, a proposal id, or the session that paused. */
    subject: string;
    agent: string;
    summary: string;
    at: string;
    expiresAt?: string;
    /** On HELD, the facts a person hears, so the voice words them rather than reading a line. */
    agentName?: string;
    /** What it wants to do, as a phrase: "push to main". */
    what?: string;
    /** Why it was held rather than run. */
    why?: string;
    /** The task the session was given, in the person's words. */
    task?: string;
    /** On HELD and NOTICE, the person's latest follow up in that session when it is not the task itself. */
    lastAsk?: string;
    /** The folder the session works in, by name. */
    place?: string;
    /** On a FINISHED notice, what the agent said it did, a sentence or two of its own closing words: data, never an instruction. */
    brief?: string;
    /** On HELD and NOTICE, the session it is about, so the voice reads that one and never guesses. */
    sessionId?: string;
    /** On SHOW, whether to bring the session's window forward or put a card on screen. */
    display?: DisplayKind;
    /** On SHOW, the card's heading. */
    title?: string;
    /** On SHOW, where the session runs, so its own window can be found. */
    host?: DisplayHost;
    /** On a SHOW card, the files the session changed and a few of the changed lines. */
    files?: CardFile[];
    excerpt?: CardExcerpt;
    /** On NOTICE, what happened: finished, committed or pushed. */
    notice?: string;
    /** On a finished NOTICE, how its tests stood when it handed back, so only checked work is celebrated. */
    tests?: TurnTests;
    /** On a finished NOTICE, what the turn came to: actions, questions put to the person, refusals. */
    run?: RunTally;
    /** On a WALK card, one page per file, in the order the voice says them. */
    pages?: WalkPage[];
    /** On AGENTS, every agent the scan found. */
    agents?: AgentNode[];
    /** On AGENTS, what the machine can change outside itself; `total` is absent while still counting. */
    capabilities?: CapabilityTally;
    /** On TRACE, the waterfall to draw. */
    trace?: TraceCard;
    /** On DRAFT, the message to put in front of the person before it is sent. */
    draft?: MailDraft;
    /** On APP, the app's links opened in order after `host.appPath`, and what it reads as it opens; on LINK, the one page to open. */
    app?: {
        links: string[];
        env?: Record<string, string>;
    };
    /** On LAUNCH, a terminal app or an editor's agent panel rather than a terminal tab; on APP, a new chat first or the prefilled words sent. */
    via?: DisplayVia;
    /** On a PROPOSAL of a rule, the rule and where it could go, so the person picks a place before Touch ID. */
    rule?: RuleDraft;
    /**
     * On HELD, and on a PROPOSAL that answers one, the call stays inside its session's repository,
     * so a yes goes without Touch ID. Absent asks for it, which is every call that reaches further.
     */
    withinSession?: true;
}
/** A trace drawn as a waterfall: each step's place on the clock, how deep it sits, how it ended. */
interface TraceCard {
    totalMs: number;
    rows: {
        name: string;
        depth: number;
        offsetMs: number;
        durationMs: number;
        status: string;
    }[];
}
/** One agent on the scan screen: who it is, and counted facts about what it reaches. */
interface AgentNode {
    id: string;
    /** The product, which picks its logo: claude-code, cursor, codex-cli, hermes. */
    kind: string;
    name: string;
    /** MCP servers its configs launch. */
    servers: number;
    /** What else it can touch: shell, filesystem, git, network, browser, cloud, docker. */
    reaches: string[];
    /** Its sessions working right now, and open waiting on the person. */
    working: number;
    open: number;
    /** Each MCP server its configs launch, by name, with what the last scan heard it hold. */
    mcp?: AgentServer[];
    /** Command line tools signed in on this Mac that its shell can run, by name. */
    clis?: string[];
    /**
     * Each capability on the machine credited to the first agent that reaches it, so adding the
     * agents up gives the machine's real count. No `total` means still counting, never zero.
     */
    capabilities?: CapabilityTally;
}
/** One MCP server as the scan screen names it; counts are absent where no scan has asked it. */
interface AgentServer {
    name: string;
    /** The program its config starts, by file name only since a path names the user; absent for a server reached by URL. */
    command?: string;
    tools?: number;
    /** Of those, the ones that change something outside it. */
    changing?: number;
}
/** One file of a walk through: what the voice says about it and the lines it is about. */
interface WalkPage {
    path: string;
    note: string;
    added?: number;
    removed?: number;
    lines: string[];
}
interface DaemonResponse extends ExtensionResponseFields {
    id: number;
    ok: boolean;
    effect?: DecisionEffect;
    reason?: string;
    alternative?: {
        action: string;
        resource?: string;
        note: string;
    };
    /** Set when a limit stopped this rather than a rule. */
    limit?: string;
    /** Set when the breaker held the session. Different from a denial, and said so. */
    paused?: {
        signal: string;
        reason: string;
    };
    /** On SUBSCRIBE, one per line after the first acknowledgement. */
    event?: DaemonEvent;
    /** On WAITING. */
    waiting?: readonly DaemonEvent[];
    /** On LOCATE. */
    location?: DaemonLocation;
    /** On VOCABULARY. */
    words?: readonly string[];
    /** On SESSION_VIEW. */
    session?: SessionView;
    /** On SESSION_VIEW with a path: that file's diff, its hunks with the lines around each change. */
    diff?: CardExcerpt;
    /** On SESSIONS_LIST, the most recently active first. */
    sessions?: SessionCard[];
    /** On ASK, one per line; the turn ends with a chunk whose kind is in ASK_ENDS. */
    chunk?: DaemonAskChunk;
    /** On VOICE_AGENTS and CHOOSE_VOICE_AGENT, every agent the voice knows, preferred first. */
    voiceAgents?: VoiceAgentStatus[];
    /** On PERSON, PERSON_SIGN_IN and PERSON_SIGN_OUT: where the daemon's own sign in stands. */
    person?: PersonStanding;
    /** On MACHINE, MACHINE_SIGN_IN and MACHINE_SIGN_OUT: whether this machine is connected to a workspace. */
    machine?: MachineStanding;
    /** On CONNECTIONS_LIST and CONNECTIONS_SIGN_OUT: one per app the person connected, by toolkit. */
    connections?: ToolConnection[];
    /** On POLISH: the dictation as it should be typed. */
    polished?: string;
    /**
     * On CONFIRM and REGISTER_KEY, what happened in a word or two; on PING, which memnox answered; on
     * the hub's SERVER_PUT, how a server typed as a package install will be started instead.
     */
    outcome?: string;
    version?: string;
    error?: string;
}
declare function encode(message: DaemonRequest | DaemonResponse): string;

/**
 * The words a person answers with, kept apart from the hold and the proposal store so a screen
 * that runs no Node can send them.
 */
declare const HOLD_ANSWER: {
    /** This call only. The next identical one asks again. */
    readonly ONCE: "once";
    /** Every identical call for the rest of this session. */
    readonly SESSION: "session";
    readonly DENY: "deny";
    /** The command was wrong rather than the rule, so the person fixes it and the loop survives. */
    readonly EDIT: "edit";
};
type HoldAnswer = (typeof HOLD_ANSWER)[keyof typeof HOLD_ANSWER];
/**
 * The button a person presses, worded the same on the terminal, the console, the Mac and the
 * phone. Checked against `docs/ux/contract.json`, the copy the other repositories follow.
 */
declare const HOLD_ANSWER_LABEL: Readonly<Record<HoldAnswer, string>>;
/** The order every surface lists them in: the narrowest yes first, and Deny always last. */
declare const HOLD_ANSWER_ORDER: readonly HoldAnswer[];
/** What is left on screen once a call is decided: "allowed once", "denied". */
declare const HOLD_OUTCOME_WORD: Readonly<Record<HoldAnswer, string>>;
/** The answers that write a rule rather than deciding one call, offered only where a rule can be signed. */
declare const ALWAYS_ALLOW_LABEL = "Always allow";
declare const ALWAYS_DENY_LABEL = "Always deny";
declare const PROPOSAL_ANSWER: {
    readonly CONFIRMED: "confirmed";
    readonly DECLINED: "declined";
};
type ProposalAnswer = (typeof PROPOSAL_ANSWER)[keyof typeof PROPOSAL_ANSWER];

/**
 * What gets signed, apart from the key store so a screen that only signs imports it without Node. The subject is a
 * proposal or pending id, so an old signature confirms nothing new. Rewritten words go last and whole, and addresses
 * rewritten on a mail just before them, since an address never holds a colon and words may.
 */
declare function confirmationMessage(subject: string, answer: string, edited?: string, editedTo?: string): string;
/**
 * A yes to a held call bound to the exact call the person saw: the daemon works the digest out again from
 * the call it holds, so a call changed after it was shown no longer matches what was signed.
 */
declare function actionConfirmationMessage(subject: string, answer: string, actionDigest: string): string;

/**
 * What a paired device may do, as data the runtime decides and the apps only display. A remote
 * request is looked up here by the device the Noise handshake proved, never by a token or a header.
 * Kept apart from the gate's tables so a screen that runs no Node can name a capability.
 */
declare const REMOTE_CAPABILITY: {
    readonly SEE: "see";
    readonly ASK: "ask";
    /** A held call, or a proposal answering one. */
    readonly ANSWER: "answer";
    /** Stopping, freezing or resuming, and the person's own follow up typed into a session. */
    readonly STEER: "steer";
    readonly RULES: "rules";
    readonly REWIND: "rewind";
    /** Driving, and a proposal for something only the Mac can do. */
    readonly MAC: "mac";
};
type RemoteCapability = (typeof REMOTE_CAPABILITY)[keyof typeof REMOTE_CAPABILITY];

/**
 * Every method whose answer can name a proposal, in `proposed`, `packProposed`, `profileApplied.proposed`
 * or `indexInstalled.proposed`, so a screen counts only these as presses and a background read never
 * makes a proposal nobody asked for wait. The daemon's dispatch is checked against it in the CLI's tests.
 */
declare const PROPOSING_METHODS: readonly string[];

export { type RuleDraftInput as $, type AgentRef as A, INDEX_KIND as B, type CapabilityTally as C, type DetectionContext as D, type IndexNeedsView as E, type MemoryItem as F, type MemoryRule as G, type HardenWriter as H, type IndexKind as I, type MemoryStatus as J, type MemoryScope as K, type MemoryKind as L, type MachineReader as M, type NetworkProbe as N, type MemorySourceRecord as O, type ProjectManifest as P, type MemoryEvidence as Q, type Resource as R, type SkillManifest as S, type SourcePassage as T, type MemorySearchMode as U, type MemorySourceKind as V, type MemorySource as W, type SourceDocumentRef as X, type SourceDocument as Y, type SourceTrust as Z, type SpokenRuleReading as _, type Reachability as a, AGENT_SEAM as a$, type SessionTask as a0, type DaemonEvent as a1, type ActivityKind as a2, type ActivityRow as a3, type AnsweredHow as a4, type DecisionStep as a5, type DecisionTrace as a6, type LiveActivityRow as a7, type ActivityFilter as a8, type WorkClaims as a9, type Delivery as aA, type DeliveryProof as aB, type Witness as aC, type CardFile as aD, type CardExcerpt as aE, type WalkPage as aF, type AgentNode as aG, type TraceCard as aH, type DisplayVia as aI, type ToolSignIn as aJ, type Sight as aK, type DaemonRequest as aL, type DaemonResponse as aM, type WorkspaceMemory as aN, type WorkspaceSaid as aO, type WorkspaceGraphFallback as aP, type WorkspaceGraphView as aQ, type ModelPriceView as aR, type SessionCostView as aS, ACTIVITY_KIND as aT, ACTIVITY_METHOD as aU, AGENTS_METHOD as aV, AGENT_ID_PREFIX as aW, AGENT_QUESTIONS_DIR as aX, AGENT_QUESTION_MOST_MS as aY, AGENT_QUESTION_PREFIX as aZ, AGENT_QUESTION_WAIT_MS as a_, type AgentWork as aa, type ExternalTaskRef as ab, type Tracker as ac, type ProfileRulePack as ad, type Delegation as ae, type HoldAnswer as af, type TaskIntent as ag, type WorkClaim as ah, type RunTally as ai, type SessionTurn as aj, type TurnWindow as ak, type ProgressAlmost as al, type AutonomyLevel as am, type ProgressLadder as an, type ProgressWeek as ao, type ChainLink as ap, type RuleScope as aq, type WorkAccount as ar, type HubChange as as, type SkillsChange as at, type ProjectChange as au, type ProposalAnswer as av, type RemoteCapability as aw, type DisplayKind as ax, type DaemonEventKind as ay, type DeviceWire as az, type AgentChains as b, CONNECTION_STATUS as b$, AGENT_STATUS as b0, ALWAYS_ALLOW_LABEL as b1, ALWAYS_DENY_LABEL as b2, ANSWERED_HOW as b3, ANY_ACTION as b4, APPROVAL_STATE as b5, APPROVED_DESTINATIONS_QUESTION as b6, AREA_WORDS as b7, ASK_ENDS as b8, ASK_INTENT as b9, type AgentWorkResponseFields as bA, type AgentsRequestFields as bB, type AgentsResponseFields as bC, type AgentsScanView as bD, type AppUse as bE, type ApprovalPosture as bF, type AreaCount as bG, type Arrival as bH, type AskIntent as bI, type AudioPiece as bJ, type AuthenticatedCli as bK, type AwaitedSession as bL, BACKUP_METHOD as bM, BRIEFING as bN, BROWSER_LAUNCHERS as bO, BULK_ARRIVAL as bP, type BackupRequestFields as bQ, type BackupResponseFields as bR, type BackupSummary as bS, type BrowserFinding as bT, BrowserHosts as bU, CALL_SOURCE_KINDS as bV, CAPABILITY_AREA as bW, CAPABILITY_LEVEL as bX, CHAIN_LINK as bY, COMMIT_READ_TIMEOUT_MS as bZ, CONNECTION_KIND as b_, ASSIST_ASK_RATE as ba, AUTONOMY as bb, AUTONOMY_ORDER as bc, type AcceptedSkillVersion as bd, type ActivityEventFields as be, type ActivityPage as bf, type ActivityRequestFields as bg, type ActivityResponseFields as bh, type AgentAction as bi, type AgentConnection as bj, type AgentHost as bk, type AgentLaunched as bl, type AgentProof as bm, type AgentQuestion as bn, type AgentQuestionInput as bo, type AgentQuestionItem as bp, type AgentQuestionOption as bq, AgentQuestions as br, type AgentSeam as bs, type AgentServer as bt, type AgentSessions as bu, type AgentStatus as bv, type AgentToday as bw, type AgentView as bx, type AgentWorkEventFields as by, type AgentWorkRequestFields as bz, type AgentDetector as c, type FilesResponseFields as c$, CONNECTOR_SOURCE as c0, CONNECTOR_WEIGHT as c1, CONNECT_STATE as c2, CONTEXT_DOMAIN as c3, CONTEXT_SIGNAL_PREFIX as c4, type CandidateFound as c5, type CapabilityArea as c6, type CapabilityLevel as c7, type CapabilityLevels as c8, type CombinedCapability as c9, type DecisionView as cA, type DefinitionKind as cB, type DiscoveredHook as cC, type DiscoveredSkill as cD, type DiscoveredTool as cE, type DiscoveryOptions as cF, type DisplayHost as cG, type DraftMode as cH, type DrivenBy as cI, EMPTY_CONTEXT as cJ, ENFORCEMENT_SEAM as cK, ENTRY_KIND as cL, ENV_FILE_NAMES as cM, ENV_FILE_PATTERN as cN, EXCLUDE as cO, EXTRACTOR_STATE as cP, type EnforcementSeam as cQ, type EntryKind as cR, type EnvFinding as cS, type ExtractorState as cT, FAST_INTERCEPT_VERSION as cU, FINGERPRINTED_HOME_PATHS as cV, FOLLOW_UP_OUTCOME as cW, type FactFound as cX, type FactQuery as cY, type FileEntry as cZ, type FilesRequestFields as c_, type CommunityIndexView as ca, type ConnectState as cb, type ConnectionEvidence as cc, type ConnectionKind as cd, type ConnectionSignIn as ce, type ConnectionStatus as cf, type ConnectionsRequestFields as cg, type ConnectionsResponseFields as ch, type ConnectorSource as ci, type ContextDomain as cj, type ContextPart as ck, type ConversationLine as cl, type CoverageFacts as cm, type CredentialFinding as cn, DAEMON_EVENT as co, DAEMON_METHOD as cp, DEFAULT_COLLISION_WINDOW_MINUTES as cq, DEFINITION_KIND as cr, DELIVERY as cs, DISPLAY as ct, DISPLAY_VIA as cu, DRAFT_MODE as cv, type DaemonAskChunk as cw, type DaemonLocation as cx, type DaemonMethod as cy, type DecisionRule as cz, type DetectionResult as d, type LanRequestFields as d$, type FollowUpOutcome as d0, type FoundSkillView as d1, GRANT as d2, type GrantKind as d3, HANDOFF_ANSWER_WORD as d4, HANDOFF_STATE as d5, HELD_BY as d6, HOLD_ANSWER as d7, HOLD_ANSWER_LABEL as d8, HOLD_ANSWER_ORDER as d9, type HubAssignment as dA, type HubSkill as dB, type HubTransport as dC, INDEX_METHOD as dD, INDEX_SOURCE as dE, INTERCEPT_METHOD as dF, INTERCEPT_PLAN as dG, INVENTORY_HOOK_SCHEMA as dH, type IndexEntryView as dI, type IndexInstalled as dJ, type IndexPublisherView as dK, type IndexRequestFields as dL, type IndexResponseFields as dM, type InterceptLine as dN, type InterceptPlanKind as dO, type InterceptRequestFields as dP, type InterceptResponseFields as dQ, LAN_METHOD as dR, LEDGER_LATEST_ONLY as dS, LEDGER_LOOKUP_LIMIT as dT, LEDGER_RECENT_LIMIT as dU, LEDGER_SCAN_LIMIT as dV, LEDGER_SESSION_LIMIT as dW, LEDGER_WINDOW_LIMIT as dX, LIVE_STATUSES as dY, LONG_TURN_MS as dZ, type LanPhone as d_, HOLD_OUTCOME_WORD as da, HOME_METHOD as db, HOOK_HOST as dc, HOST_LOCATION as dd, HOST_SIGNATURE as de, HUB_TRANSPORT as df, HUB_VERSION as dg, type HandOverVerdict as dh, type HandoffAnswerWord as di, type HandoffParty as dj, type HandoffState as dk, type Harness as dl, type HeldActionEventFields as dm, type HeldActionRequestFields as dn, type HeldBy as dp, type HomeModeSet as dq, type HomeNotCovered as dr, type HomeReady as ds, type HomeResponseFields as dt, type HomeToday as du, type HomeView as dv, type HomeWorking as dw, type HookHost as dx, type HostSearch as dy, type HostedAgents as dz, type McpLister as e, type MemoryRouterLayerView as e$, type LanResponseFields as e0, type LanStatus as e1, type LevelEvidence as e2, MAIL_SERVICE as e3, MCP_HEALTH as e4, MCP_HUB_METHOD as e5, MCP_SCOPE as e6, MEDIATION as e7, MEMORY_KIND as e8, MEMORY_KINDS as e9, type McpHubEntryView as eA, type McpHubRequestFields as eB, type McpHubResponseFields as eC, type McpHubServerView as eD, type McpHubView as eE, type McpProjectAssignment as eF, type McpScope as eG, type McpSyncSummary as eH, type McpToolSummary as eI, type Mediation as eJ, type MemoryCallView as eK, type MemoryEditInput as eL, type MemoryEvidenceView as eM, type MemoryIndexLayerView as eN, type MemoryItemView as eO, type MemoryItemsView as eP, type MemoryLayer as eQ, type MemoryLayersApplied as eR, type MemoryLayersPlan as eS, type MemoryLayersRequestFields as eT, type MemoryLayersResponseFields as eU, type MemoryLayersView as eV, type MemoryOrigin as eW, type MemoryPassageView as eX, type MemoryReadSummary as eY, type MemoryRequestFields as eZ, type MemoryResponseFields as e_, MEMORY_LAYER as ea, MEMORY_LAYERS_METHOD as eb, MEMORY_METHOD as ec, MEMORY_ORIGIN as ed, MEMORY_SCOPE as ee, MEMORY_SEARCH_MODE as ef, MEMORY_SOURCE_KIND as eg, MEMORY_SOURCE_KINDS as eh, MEMORY_STATUS as ei, MEMORY_STATUSES as ej, MINIMUM_EVIDENCE as ek, MINIMUM_SHARED_TARGETS as el, MOST_HANDED_TARGETS as em, MOST_LIVE_ACTIVITY_ROWS as en, MOST_PRESSED_KEYS as eo, MOST_PROGRESS_CHARS as ep, MOST_PROGRESS_NOTES as eq, MOST_SKILL_BYTES as er, MOST_SKILL_FILES as es, MOST_TOOLKITS_FOUND as et, type MacSpan as eu, type MachineStanding as ev, type MailDraft as ew, type MailService as ex, type McpHealthState as ey, type McpHubAgentView as ez, type ApprovalState as f, type ProjectInstructionView as f$, type MemoryRuleView as f0, type MemorySkillLayerView as f1, type MemorySourceCounts as f2, type MemorySourceInput as f3, type MemorySourceView as f4, type MemoryValueView as f5, NOTICE_KIND as f6, type NetworkProbeInput as f7, type NoticeKind as f8, type NoticeWatch as f9, type PersonalSyncKindCount as fA, type PersonalSyncMachine as fB, type PersonalSyncRequestFields as fC, type PersonalSyncResponseFields as fD, type PersonalSyncState as fE, type PersonalSyncStatus as fF, type PhoneTurn as fG, type PolicyLoadProblem as fH, type PolicyRequestFields as fI, type PolicyResponseFields as fJ, type PolicyRuleMatch as fK, type PolicyRuleView as fL, type PolicyRulesView as fM, type ProfileApplied as fN, type ProfileBinding as fO, type ProfileDraft as fP, type ProfileJob as fQ, type ProfileTemplate as fR, type ProfileView as fS, type ProfilesRequestFields as fT, type ProfilesResponseFields as fU, type ProgressGrant as fV, type ProgressReady as fW, type ProgressView as fX, type ProjectApplySummary as fY, type ProjectDraft as fZ, type ProjectGrantView as f_, OPEN_STATUSES as fa, OUTBOUND_STATE as fb, type OutboundState as fc, PAIRING_STATE as fd, PERSONAL_SYNC_METHOD as fe, PERSONAL_SYNC_STATE as ff, POLICY_METHOD as fg, PROFILES_METHOD as fh, PROFILE_TEMPLATES as fi, PROJECTS_DIR as fj, PROJECTS_METHOD as fk, PROJECT_CREDENTIAL_FILES as fl, PROJECT_FILE as fm, PROJECT_SCOPE as fn, PROMOTION_THRESHOLD as fo, PROOF as fp, PROOF_RECORD_VERSION as fq, PROPOSAL_ANSWER as fr, PROPOSING_METHODS as fs, PROVABLE_SEAMS as ft, type PairingPhone as fu, type PairingState as fv, type PairingWire as fw, type PersonSignInCode as fx, type PersonStanding as fy, type PersonalSyncConflict as fz, type HostLocation as g, type SignedIn as g$, type ProjectLayersView as g0, type ProjectMissionView as g1, type ProjectOrganizationView as g2, type ProjectRulesView as g3, type ProjectScope as g4, type ProjectView as g5, type ProjectsRequestFields as g6, type ProjectsResponseFields as g7, type ProjectsView as g8, type ProofRecord as g9, SEAM_TEST as gA, SETTLED_STATUSES as gB, SKILLS_HUB_VERSION as gC, SKILLS_METHOD as gD, SKILL_INSTRUCTIONS as gE, SKILL_MANIFEST as gF, SKILL_SCOPE as gG, SKILL_STANDING as gH, SKIP_REASON as gI, SOURCE_TRUST as gJ, SPEAKER as gK, SPEECH_METHOD as gL, SPOKEN_RULE_METHOD as gM, SUPERVISED_ASK_RATE as gN, SYNC_KEEP as gO, type SeamCoverage as gP, type SeamProof as gQ, type SeamState as gR, type SeamTestResult as gS, type SessionCard as gT, type SessionNotice as gU, SessionTasks as gV, SessionTurns as gW, type SessionView as gX, type SessionViewStep as gY, type SessionWatch as gZ, SessionWatches as g_, type ProofState as ga, REF_KIND as gb, REMOTE_CAPABILITY as gc, REMOTE_METHOD as gd, REMOTE_OUTCOME as ge, REPOSITORY_TASK_HOURS as gf, RULE_DRAFTED_BY as gg, RULE_SCOPE as gh, RULE_SOURCE as gi, type ReachingCapability as gj, type RefKind as gk, type RemoteEventFields as gl, type RemoteRequestFields as gm, type RemoteResponseFields as gn, type RepositoryTask as go, RepositoryTasks as gp, type RuleDraft as gq, type RuleDraftedBy as gr, type RulePackView as gs, type RuleScopeKind as gt, type RuleSource as gu, type RuleTestInput as gv, type RuleVerdictView as gw, SANDBOX_PATHS as gx, SCANNED_CREDENTIAL_FILES as gy, SEAM_STATE as gz, type HostSignatureState as h, WORK_STATUS as h$, type SkillAgentView as h0, type SkillAssignment as h1, type SkillAssignmentView as h2, type SkillCompatibility as h3, type SkillDraft as h4, type SkillFinding as h5, type SkillHold as h6, type SkillPermissions as h7, type SkillPermissionsView as h8, type SkillStanding as h9, type TeamAnswerBrief as hA, type TeamCallBrief as hB, type TerminalKey as hC, type TestRun as hD, type ToolConnection as hE, type ToolGrant as hF, type ToolkitKind as hG, type ToolkitSummary as hH, type ToolkitSupport as hI, type TurnSpan as hJ, type TurnTests as hK, type VoiceAgentStatus as hL, type VoiceHolder as hM, type VoiceOn as hN, WATCHES_DIR as hO, WATCH_FOR as hP, WATCH_TTL_MS as hQ, WORKSPACE_GRAPH_FALLBACK as hR, WORKSPACE_GRAPH_SOURCE as hS, WORKSPACE_LINK_KIND as hT, WORKSPACE_NODE_KIND as hU, WORKSPACE_NODE_STATUS as hV, WORK_ACCOUNT_CHECK as hW, WORK_CLAIM_FORM as hX, WORK_CLAIM_SOURCE as hY, WORK_DRAFT_KIND as hZ, WORK_METHOD as h_, type SkillStandingNow as ha, type SkillVersionView as hb, type SkillWritten as hc, type SkillsHubView as hd, type SkillsRequestFields as he, type SkillsResponseFields as hf, type SkillsSyncSummary as hg, type SkipReason as hh, type SkippedDocument as hi, type Speaker as hj, type SpeechRequestFields as hk, type SpeechResponseFields as hl, type SpokenRuleAnswer as hm, type SpokenRuleDraft as hn, type SpokenRuleRequestFields as ho, type SpokenRuleResponseFields as hp, type SyncKeep as hq, TASK_DIR as hr, TASK_INTENT as hs, TERMINAL_KEY as ht, TOOLKIT_KIND as hu, TOOLKIT_SUPPORT as hv, TRACKER as hw, TURNS_DIR as hx, TURN_TESTS as hy, type TaskDeclaration as hz, type DiscoveryReport as i, decisionsBearingOn as i$, type WatchFacts as i0, type WatchFired as i1, type WatchFor as i2, type WatchInput as i3, type WorkAccountCheck as i4, type WorkDraft as i5, type WorkDraftExtras as i6, type WorkDraftKind as i7, type WorkField as i8, type WorkHandoff as i9, approvalPostureOf as iA, areaOf as iB, areaPhrase as iC, attributeResources as iD, authenticatedClis as iE, bulkArrivals as iF, candidateOrigin as iG, candidatesAbout as iH, capabilitiesOf as iI, chainLinkOfName as iJ, chainsFor as iK, changedOf as iL, classifyResourceKind as iM, classifySensitivity as iN, combinedCapabilities as iO, commitClaimsAt as iP, compareVersions as iQ, computeReachability as iR, confirmationMessage as iS, connectionKindOf as iT, connectionsFor as iU, connectorSourceOf as iV, countLogins as iW, coverageFor as iX, coverageSummary as iY, creditedTallies as iZ, databasesIn as i_, type WorkOutcome as ia, type WorkProgress as ib, type WorkRef as ic, type WorkStart as id, type WorkStatus as ie, type WorkspaceCandidate as ig, type WorkspaceFact as ih, type WorkspaceGraphLink as ii, type WorkspaceGraphNode as ij, type WorkspaceGraphSource as ik, type WorkspaceLinkKind as il, type WorkspaceNodeKind as im, type WorkspaceNodeStatus as io, actionConfirmationMessage as ip, actionContextOf as iq, agentHostOf as ir, agentIdFor as is, agentNameIn as it, agentPatterns as iu, agentProofOf as iv, agentRefOf as iw, agentsOf as ix, agentsReachingPath as iy, answerFor as iz, type AcceptedSkill as j, isInterceptMethod as j$, delegations as j0, describeBrowser as j1, describeCandidate as j2, describeCombined as j3, describeDrift as j4, describeFact as j5, describeGrant as j6, describeHandedReach as j7, describeHarness as j8, describeHooks as j9, findBrowserAutomation as jA, findCredentials as jB, findEnvFiles as jC, fingerprint as jD, finishedWork as jE, followUpMessage as jF, foreignHooks as jG, fullyAnswered as jH, grantMessage as jI, grantOf as jJ, grantWidened as jK, handOverVerdict as jL, handable as jM, harnessOf as jN, hasRecordedContext as jO, hasServerIn as jP, hubServerProblems as jQ, interruptions as jR, isAddress as jS, isAgentQuestionId as jT, isBrowserLauncher as jU, isCallSource as jV, isCredentialPath as jW, isEmptyScope as jX, isFileSource as jY, isFinished as jZ, isInsideFolder as j_, describeLevel as ja, describeNetwork as jb, describeProof as jc, describeRun as jd, describeSkill as je, detectTools as jf, deviceProofMessage as jg, disagrees as jh, discover as ji, discoverAgents as jj, discoverDefinitions as jk, discoverHooks as jl, discoverSkills as jm, draftFromTemplate as jn, driveMessage as jo, editedArguments as jp, editedRecipients as jq, emptyHub as jr, emptyManifest as js, emptySkillsHub as jt, encode as ju, encodeInterceptLine as jv, enforcementFailed as jw, evidenceRef as jx, factOrigin as jy, factsAbout as jz, type HostInspector as k, summarize as k$, isOutdated as k0, isProjectId as k1, isSkillName as k2, isTestCommand as k3, joinedBy as k4, keysInText as k5, levelsOf as k6, locationOf as k7, looksLikeCredential as k8, manifestProblems as k9, rankedBySource as kA, reachOf as kB, reachesOf as kC, readBackOfSpokenRule as kD, readEnvFile as kE, recipientsOf as kF, remoteAddressProblem as kG, restates as kH, reviewSkills as kI, runTally as kJ, scopeOf as kK, seamConfigDigestOf as kL, seamTestsOf as kM, secretsOfServer as kN, serversFor as kO, sessionTaskOfWork as kP, skillNameOf as kQ, skillNamed as kR, skillProblems as kS, skillStandingOf as kT, spokenRuleFromModel as kU, spokenRuleProblems as kV, standingOf as kW, startWatch as kX, startedWork as kY, statementKey as kZ, subjectOf as k_, mediationOf as ka, navigationHost as kb, needsOf as kc, networkReach as kd, newestCandidates as ke, newestFacts as kf, noLevels as kg, noticeSubject as kh, noticesFrom as ki, numberClaimOfBranch as kj, pairMessage as kk, parseProjectToml as kl, parseWorkspaceMemory as km, policyOfSpokenRule as kn, principalCount as ko, probeNetwork as kp, productionLooking as kq, profileIdFor as kr, profileLevelsOf as ks, programOf as kt, projectIdOf as ku, projectToml as kv, projectsOf as kw, promotable as kx, proxyIsBypassedEntirely as ky, quarantined as kz, type HostSignature as l, summarizeProof as l0, tallyOf as l1, taskDirFor as l2, taskFor as l3, templateNamed as l4, terminalKeys as l5, termsOf as l6, trustOf as l7, turnTests as l8, urlArgumentIn as l9, watchFired as la, wentIn as lb, withAccepted as lc, withAssignment as ld, withChange as le, withHandoffAnswer as lf, withHandoffRequest as lg, withProgress as lh, withServer as li, withSkill as lj, withSkillAssignment as lk, withoutServer as ll, withoutSkill as lm, wordOverlap as ln, workClaimsAt as lo, workDraftFromText as lp, workDraftOf as lq, workspaceCandidateId as lr, workspaceFactId as ls, workspaceSourceId as lt, type DiscoveredAgent as m, type HubServer as n, type Hub as o, type HubWritten as p, type McpServerHealth as q, type CanonicalSkill as r, type SkillScope as s, type SkillFile as t, type SkillsHub as u, type SkillView as v, type SkillStatsView as w, type SkillCalibration as x, type MemoryLayerFilePlan as y, type ProfileBindings as z };
