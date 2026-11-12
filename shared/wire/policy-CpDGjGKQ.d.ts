/** Declared scope: what the person asked for, as data the client already holds. */
interface DeclaredScope {
    paths?: readonly string[];
    repositories?: readonly string[];
    services?: readonly string[];
    environments?: readonly string[];
    resourceKinds?: readonly string[];
}
interface TaskRef {
    id: string;
    statement: string;
}
/** What a request touches, compared field by field against the declared scope. */
interface ScopeSubject {
    path?: string;
    repository?: string;
    service?: string;
    environment?: string;
    resourceKind?: string;
}
declare const SCOPE_MATCH: {
    readonly IN_SCOPE: "in_scope";
    readonly OUT_OF_SCOPE: "out_of_scope";
    /** The task declared nothing about this dimension, so there is nothing to compare. */
    readonly UNDECLARED: "undeclared";
};
type ScopeMatch = (typeof SCOPE_MATCH)[keyof typeof SCOPE_MATCH];
interface ScopeComparison {
    match: ScopeMatch;
    /** The dimension that fell outside, so the refusal can name it. */
    dimension?: keyof ScopeSubject;
    declared?: readonly string[];
    actual?: string;
}
/**
 * Scope is compared, not judged. No model is consulted and none ever will be here: an
 * undeclared dimension is undeclared, never a guess, and the ambiguous middle asks
 * because a rule said so rather than because a classifier had an opinion.
 */
declare function compareDeclaredScope(scope: DeclaredScope, subject: ScopeSubject, matches: (patterns: readonly string[], value: string) => boolean): ScopeComparison;

/** The core primitive: every AI action becomes an event Memnox can rule on and prove. */
interface ActionRequest {
    /** Namespaced verb, e.g. "database.delete", "code.modify", "deploy.service". */
    action: string;
    /** What the action operates on, e.g. "production.users", "payment/checkout.ts". */
    target?: string;
    environment?: string;
    /** Groups actions into one agent session for replay and reporting. */
    sessionId?: string;
    /** The governance unit, declared in a policy file, so repos sharing a name share one scope. */
    projectId?: string;
    /** Whose authority the agent draws on, not who the agent is, which is its credential. */
    principal?: string;
    /** Facts this action relies on, so "may not do" is tellable from "should not know". */
    reads?: readonly string[];
    /** What was actually asked for. Declared by the client; never inferred here. */
    task?: TaskRef;
    /** The agent's stated intent, recorded verbatim for the audit trail. */
    reason?: string;
    metadata?: Record<string, unknown>;
    /** Reference to a previously granted approval for this same action. */
    approvalId?: string;
    /** Model behind the action, e.g. "openai.gpt-4". Reported by the caller. */
    model?: string;
    /** Inference provider, e.g. "openai", "anthropic", "bedrock". */
    provider?: string;
    /** What kind of regulated data this touches, e.g. "pii.eu", "hipaa", "pci". */
    dataClassification?: string;
    /** Region the action executes in, e.g. "eu", "us". */
    jurisdiction?: string;
    /** How big the action is; size is often the whole rule. Read by `aboveAmount`. */
    amount?: number;
    /** Directory the agent is working in, e.g. "/srv/checkout". Reported by the caller. */
    workingDirectory?: string;
    /** Source control branch the work sits on, e.g. "main", "release/24.3". */
    branch?: string;
    /**
     * What the action does to the world, as the classifier that saw it named it: read, write,
     * destructive, communication or unknown. Absent means nothing classified it.
     */
    toolClass?: string;
    /** LOCAL ONLY: the raw payload. The SDK strips it; `signals` travel instead. */
    arguments?: Record<string, string>;
    /**
     * LOCAL ONLY: the lines a write is adding, for a rule's `content` convention. Read where
     * the call is made and never recorded, since a row carries names and never contents.
     */
    content?: readonly string[];
    /** What the local gate found. Testimony: it may ask, never loosen. */
    signals?: string[];
}

/**
 * The kinds of outgoing data a rule's `dataClassifications` can name, one vocabulary
 * shared by the runtime, the rule drafter and the console.
 */
declare const DATA_CLASSIFICATION: {
    /** Every kind below; the word one rule uses to mean all of them. */
    readonly SENSITIVE: "sensitive";
    /** A credential: an API key or token, a private key, a password, a connection string. */
    readonly SECRET: "secret";
    /** A card, a bank account, an invoice or a payroll record. */
    readonly FINANCIAL: "financial";
    /** A diagnosis, a prescription, a medical record. */
    readonly HEALTH: "health";
    /** A national id, a social security number, a passport, a tax id. */
    readonly GOVERNMENT_ID: "government-id";
    /** One personal field on its own: an email, a phone number, an address. */
    readonly PERSONAL_DATA: "personal-data";
    /** Several personal fields about one person together, or a field under a customer key. */
    readonly CUSTOMER_RECORD: "customer-record";
    /** Text marked confidential, internal only or under NDA, or naming what the team listed. */
    readonly CONFIDENTIAL: "confidential";
    /** A program, or a file from inside the repository. */
    readonly SOURCE_CODE: "source-code";
    /** Many rows of anything: a table, an export, a database dump. */
    readonly BULK_RECORDS: "bulk-records";
};
type DataClassification = (typeof DATA_CLASSIFICATION)[keyof typeof DATA_CLASSIFICATION];
/** The vocabulary in one list, for a rule drafter or a screen offering the words. */
declare const DATA_CLASSIFICATIONS: readonly DataClassification[];
/** What each word means, in the words a person choosing one would use. */
declare const DATA_CLASSIFICATION_MEANING: Readonly<Record<DataClassification, string>>;
/** The need to know levels the kinds sit at; `restricted` is the ceiling. */
declare const DATA_SENSITIVITY: {
    readonly CONFIDENTIAL: "confidential";
    readonly RESTRICTED: "restricted";
};
type DataSensitivity = (typeof DATA_SENSITIVITY)[keyof typeof DATA_SENSITIVITY];
declare const SENSITIVITY_OF_CLASSIFICATION: Readonly<Record<DataClassification, DataSensitivity>>;
declare const SENSITIVITY_BY_NAME: ReadonlyMap<string, DataSensitivity>;
/**
 * A team's own words under a classification of its choosing, as a codename under
 * `confidential`. A pattern is a whole word matched in any case, or `/a regex/`.
 */
interface DataPattern {
    classification: string;
    patterns: readonly string[];
}
/** A pattern longer than this is refused, since a team's regex runs on every call. */
declare const MOST_PATTERN_CHARS = 200;
/** Rows of anything past which a payload is a bulk export rather than an answer. */
declare const BULK_ROWS = 20;
interface CompiledPattern {
    classification: string;
    expression: RegExp;
}

/** Three effects, not two: the third is what keeps a governed system from being a wall. */
declare const DECISION_EFFECT: {
    readonly ALLOW: "allow";
    readonly DENY: "deny";
    readonly ASK: "ask";
};
type DecisionEffect = (typeof DECISION_EFFECT)[keyof typeof DECISION_EFFECT];
/** Higher value wins when several rules match: deny overrides allow at equal priority. */
declare const EFFECT_PRECEDENCE: Record<DecisionEffect, number>;
declare const DECISION_REASON: {
    readonly NO_POLICY_MATCHED: "no policy matched, so the default effect applied";
    readonly UNKNOWN_AGENT: "unknown agent credentials, so this fails closed";
    readonly AGENT_SUSPENDED: "agent is suspended";
    readonly AGENT_QUARANTINED: "agent is quarantined, so reads pass and this does not";
    readonly APPROVAL_GRANTED: "human approval granted";
    readonly APPROVAL_PENDING: "human approval required and pending";
    readonly CAPABILITY: "capability: action is outside this agent's declared capabilities";
    readonly BREAK_GLASS_OVERRIDE: "break-glass override";
    readonly NON_OVERRIDABLE: "non-overridable deny, so no approval can satisfy this action";
    readonly RATE_LIMIT: "rate limit exceeded for this rule";
    readonly OUT_OF_DECLARED_SCOPE: "this was not part of what the task declared";
};

/** The ramp, softest first. One environment at a time is the only safe way to arrive. */
declare const ENFORCEMENT_MODE: {
    /** No policy evaluation at all, so the action proceeds and is audited as ungoverned. */
    readonly OFF: "off";
    /** Evaluate and record the real verdict, but never deny the action. */
    readonly OBSERVE: "observe";
    /** Tell the caller what the verdict was and let it proceed anyway. */
    readonly ADVISE: "advise";
    /** Apply the verdict. */
    readonly ENFORCE: "enforce";
};
type EnforcementMode = (typeof ENFORCEMENT_MODE)[keyof typeof ENFORCEMENT_MODE];
/** Fail-closed: observe-first belongs in a config file, never a library default. */
declare const DEFAULT_ENFORCEMENT_MODE: EnforcementMode;
/** Read at its softest wherever one state is drawn for several environments. */
declare const MODE_STRENGTH: Record<EnforcementMode, number>;

/** A kind, not a session: Claude Code on four machines is one agent kind. */
declare const DISCOVERED_AGENT_KIND: {
    readonly CLAUDE_CODE: "claude-code";
    readonly CLAUDE_DESKTOP: "claude-desktop";
    readonly CODEX_CLI: "codex-cli";
    readonly CURSOR: "cursor";
    readonly CLINE: "cline";
    readonly VS_CODE: "vscode";
    readonly GITHUB_ACTIONS: "github-actions";
    readonly HERMES: "hermes";
    readonly OPENCLAW: "openclaw";
    readonly RUFLO: "ruflo";
    readonly GEMINI_CLI: "gemini-cli";
    readonly WINDSURF: "windsurf";
    readonly COPILOT_CLI: "copilot-cli";
    readonly DEVIN: "devin";
    readonly OPENCODE: "opencode";
};
type DiscoveredAgentKind = (typeof DISCOVERED_AGENT_KIND)[keyof typeof DISCOVERED_AGENT_KIND];
/**
 * Kinds that run other agents rather than only themselves. The distinction matters
 * because their reach is the union of what they host, and a roster that lists a
 * harness as one row beside Claude Code understates it by however many it launches.
 */
declare const HARNESS_KINDS: readonly DiscoveredAgentKind[];
declare function isHarnessKind(kind: string): boolean;
/** What an agent can act through. Each is a seam Memnox can hold, or admit it cannot. */
declare const SURFACE_KIND: {
    readonly SHELL: "shell";
    readonly FILESYSTEM: "filesystem";
    readonly GIT: "git";
    readonly MCP: "mcp";
    readonly NETWORK: "network";
    readonly DOCKER: "docker";
    readonly CLOUD: "cloud";
    readonly BROWSER: "browser";
    /** The screen, keyboard and mouse of this machine, which no seam here sits in front of. */
    readonly DESKTOP: "desktop";
};
type SurfaceKind = (typeof SURFACE_KIND)[keyof typeof SURFACE_KIND];
/**
 * A shell short-circuits reachability: an agent that can run one reaches everything
 * the user reaches, and stating that plainly is most of the value of the map.
 */
declare const TRANSITIVE_SURFACES: readonly SurfaceKind[];
declare const RESOURCE_KIND: {
    readonly FILE: "file";
    readonly SECRET: "secret";
    readonly REPO: "repo";
    readonly DB: "db";
    readonly CLOUD: "cloud";
    readonly SOCKET: "socket";
    /** Not a file: what an agent with a shell or an HTTP tool can already reach. */
    readonly NETWORK: "network";
};
type ResourceKind = (typeof RESOURCE_KIND)[keyof typeof RESOURCE_KIND];
/** What one MCP tool does, which no client shows anywhere. */
declare const TOOL_EFFECT: {
    readonly READ: "read";
    readonly WRITE: "write";
    readonly DESTRUCTIVE: "destructive";
    readonly UNKNOWN: "unknown";
};
type ToolEffect = (typeof TOOL_EFFECT)[keyof typeof TOOL_EFFECT];
/** How the effect was arrived at, stated so a wrong guess is arguable. */
declare const EFFECT_INFERENCE: {
    readonly ANNOTATION: "annotation";
    readonly SCHEMA: "schema";
    readonly NAME: "name";
    readonly PROBE: "probe";
};
type EffectInference = (typeof EFFECT_INFERENCE)[keyof typeof EFFECT_INFERENCE];
declare const SENSITIVITY: {
    readonly ORDINARY: "ordinary";
    readonly SENSITIVE: "sensitive";
    readonly CRITICAL: "critical";
};
type Sensitivity = (typeof SENSITIVITY)[keyof typeof SENSITIVITY];
declare const FINDING_SEVERITY: {
    readonly LOW: "low";
    readonly MEDIUM: "medium";
    readonly HIGH: "high";
    readonly CRITICAL: "critical";
};
type FindingSeverity = (typeof FINDING_SEVERITY)[keyof typeof FINDING_SEVERITY];
/**
 * What kind of problem a finding is, apart from its wording, which a fleet groups by and
 * which keeps the same problem found twice from reading as two.
 */
declare const FINDING_KIND: {
    /** A sensitive file or store that agents on this machine can read. */
    readonly SENSITIVE_RESOURCE_REACHABLE: "sensitive_resource_reachable";
    /** Destructive tools on a surface with no rule in front of them. */
    readonly UNCHECKED_DESTRUCTIVE_TOOLS: "unchecked_destructive_tools";
    /** Production, reachable from a machine doing local work. */
    readonly PRODUCTION_REACHABLE: "production_reachable";
    /** Read, write and send held together: an export no single rule refuses. */
    readonly EXPORT_PATH: "export_path";
    /** A chain whose every step is ordinary and whose end is not. */
    readonly TOOL_CHAIN: "tool_chain";
    /** A shell surface, which makes everything the user reaches reachable. */
    readonly SHELL_SURFACE: "shell_surface";
};
type FindingKind = (typeof FINDING_KIND)[keyof typeof FINDING_KIND];
declare const SEVERITY_ORDER: Record<FindingSeverity, number>;
/** Where a harden step lands. Never in a file the reader's team reviews. */
declare const HARDEN_TARGET: {
    readonly POLICY: "policy";
    readonly SEAM: "seam";
};
type HardenTarget = (typeof HARDEN_TARGET)[keyof typeof HARDEN_TARGET];
/**
 * Anything ambiguous defaults to advise. Breaking somebody's work at 2am is the one
 * failure this product does not recover from.
 */
declare const HARDEN_MODE: {
    readonly ADVISE: "advise";
    readonly ENFORCE: "enforce";
};
type HardenMode = (typeof HARDEN_MODE)[keyof typeof HARDEN_MODE];
/** A fingerprint, never the value. The reader holds the secret; nothing downstream does. */
declare const FINGERPRINT_ALGORITHM = "sha256";
declare const FINGERPRINT_LENGTH = 16;
/**
 * Bounded because this is the one place discovery starts somebody else's process.
 * A server that will not answer in this long is a gap in the report, not a stall.
 */
declare const MCP_PROBE_TIMEOUT_MS = 5000;
/** The revision the probe negotiates; a server that wants another still answers. */
declare const MCP_PROTOCOL_VERSION = "2025-06-18";
/**
 * Command-line tools an agent with a shell can invoke. Detected by looking where they
 * install, because a name on a list nobody checked is a claim rather than a finding.
 */
declare const KNOWN_TOOLS: readonly {
    name: string;
    paths: readonly string[];
}[];
/**
 * Connection strings worth naming. The scheme and whether it looks like production is
 * all that is kept: the URL itself holds a credential and never leaves the process.
 */
declare const DATABASE_SCHEMES: readonly string[];
/** Hosts that read as production, so the row can say which one it is. */
declare const PRODUCTION_HINTS: readonly string[];
/** Which way a change moved. A list mixing the two is a list nobody can act on. */
declare const CHANGE_DIRECTION: {
    readonly WIDENS: "widens";
    readonly NARROWS: "narrows";
};
type ChangeDirection = (typeof CHANGE_DIRECTION)[keyof typeof CHANGE_DIRECTION];
/** What moved. Named rather than typed as a string so a report can group by it. */
declare const CHANGE_SUBJECT: {
    readonly AGENT: "agent";
    readonly SERVER: "server";
    readonly TOOL: "tool";
    readonly SURFACE: "surface";
    readonly RESOURCE: "resource";
    /** A role, a hook or a federation link under something that runs other agents. */
    readonly HARNESS: "harness";
    /** A command an agent now runs on its own event, which no permission prompt covers. */
    readonly HOOK: "hook";
};
type ChangeSubject = (typeof CHANGE_SUBJECT)[keyof typeof CHANGE_SUBJECT];
/** Snapshots kept before the oldest is dropped: enough for "since last week". */
declare const SNAPSHOT_HISTORY_LIMIT = 30;

/** One tool on one server, with what it does and how that was decided. */
interface McpTool {
    server: string;
    name: string;
    description?: string;
    effect: ToolEffect;
    inferredFrom: EffectInference;
}
interface Surface {
    agentId: string;
    kind: SurfaceKind;
    /** The file that proved it. A surface with no evidence is a guess. */
    detectedFrom: string;
    tools?: McpTool[];
    /**
     * The launch lines a config declared. A config says what a server is called and
     * never what it can do, so these exist to be asked over the protocol.
     */
    servers?: McpServerLaunch[];
    /**
     * Tools the host's own filter takes away before the agent sees them. Counted rather
     * than dropped silently, because a client that already filters deserves the credit
     * and the reader deserves to know the number is smaller for a reason.
     */
    filteredOut?: number;
}
/** Enough to start one MCP server and ask it what it holds. */
interface McpServerLaunch {
    name: string;
    command: string;
    args: string[];
    /**
     * The credential names this config hands the server. Names only: what is stored is
     * a key, never the value behind it.
     */
    env?: string[];
    /** An allow/deny list the host applies before the agent ever sees the tool. */
    filter?: ToolFilter;
    /** A server the config declares and has switched off. Present, and not reachable. */
    disabled?: boolean;
}
/**
 * Hermes and OpenClaw resolve an include and exclude pair differently, so a filter carries
 * whose rules it is rather than one matcher guessing.
 */
declare const FILTER_PRECEDENCE: {
    /** A present include list decides alone. Hermes. */
    readonly INCLUDE_WINS: "include-wins";
    /** Deny is checked first, then any allow list. OpenClaw. */
    readonly EXCLUDE_WINS: "exclude-wins";
};
type FilterPrecedence = (typeof FILTER_PRECEDENCE)[keyof typeof FILTER_PRECEDENCE];
interface ToolFilter {
    /** Absent means no whitelist. Empty means a whitelist that admits nothing. */
    include?: string[];
    exclude: string[];
    precedence: FilterPrecedence;
}
declare function passesFilter(name: string, filter: ToolFilter | undefined): boolean;
/** The protocol's own annotation, when a server bothered to publish one. */
interface McpToolAnnotations {
    readOnlyHint?: boolean;
    destructiveHint?: boolean;
    idempotentHint?: boolean;
}
interface McpToolDeclaration {
    name: string;
    description?: string;
    annotations?: McpToolAnnotations;
    inputSchema?: {
        properties?: Record<string, unknown>;
    };
}
/**
 * Effect is taken from the tool's own annotation where it exists and inferred with a
 * stated method where it does not, so a wrong call can be seen and corrected rather
 * than quietly changing what a rule covers.
 */
declare function inferToolEffect(declaration: McpToolDeclaration): {
    effect: ToolEffect;
    inferredFrom: EffectInference;
};
/**
 * The verb in a name, which is all a name carries. Exported because an action on the
 * wire is named the same way a tool is, and two verb lists would drift apart.
 */
declare function effectOfName(name: string): ToolEffect | null;
/**
 * Split on separators and camel humps rather than matching substrings: "widget"
 * contains "get", and a tool called `frobnicate_widget` read as a read is exactly the
 * wrong kind of confident.
 */
declare function nameSegments(name: string): string[];
/**
 * One entry per tool, however many clients declare its server, so four tools in five
 * editors are four and not twenty.
 */
declare function distinctTools(surfaces: readonly {
    tools?: McpTool[];
}[]): McpTool[];
declare function toMcpTool(server: string, declaration: McpToolDeclaration): McpTool;

/**
 * A tool that carries something out of the organization is its own class. It is not
 * destructive, because nothing is lost, and calling it a plain write hides the one property
 * that matters: the data has left, and no rule downstream can call it back.
 */
declare const TOOL_CLASS: {
    readonly READ: "read";
    readonly WRITE: "write";
    readonly DESTRUCTIVE: "destructive";
    readonly COMMUNICATION: "communication";
    readonly UNKNOWN: "unknown";
};
type ToolClass = (typeof TOOL_CLASS)[keyof typeof TOOL_CLASS];
interface Classification {
    class: ToolClass;
    /** How it was decided, so a wrong call is arguable rather than mysterious. */
    from: EffectInference | 'override';
}
type ToolOverrides = Readonly<Record<string, ToolClass>>;
/** A class named by a caller or a hand-edited file, narrowed before it is trusted. */
declare function isToolClass(value: string): value is ToolClass;
/**
 * Overrides are read from a file people edit by hand, so an unknown class is dropped
 * with the rest kept: refusing the whole file over one typo would leave a machine
 * ungoverned because somebody misspelled a word.
 */
declare function parseOverrides(raw: string): {
    overrides: ToolOverrides;
    rejected: string[];
};
/**
 * An override wins over everything, including a published annotation: the person who
 * wrote it has seen the tool behave and the server author has not seen this install.
 */
declare function classifyTool(declaration: McpToolDeclaration, overrides?: ToolOverrides): Classification;
/** Communication leaves the organization, so it counts with the writes, never the reads. */
declare function changesExternalState(classification: ToolClass): boolean;

/**
 * The risk vocabulary, and the verb tables the classifier reads. These decide what gets
 * asked about, so moving a verb between them is a security change and reviewed as one.
 */
declare const RISK_LEVEL: {
    readonly LOW: "low";
    readonly MEDIUM: "medium";
    readonly HIGH: "high";
    readonly CRITICAL: "critical";
};
type RiskLevel = (typeof RISK_LEVEL)[keyof typeof RISK_LEVEL];
declare const RISK_ORDER: readonly RiskLevel[];
/** Action verbs that read state without changing it. */
declare const READ_ONLY_VERBS: readonly string[];
/** Action verbs that change state reversibly. */
declare const MUTATING_VERBS: readonly string[];
/** Action verbs that destroy or exfiltrate, which carry the highest baseline risk. */
declare const DESTRUCTIVE_VERBS: readonly string[];
/** Environments where risk is raised one level. */
declare const RISK_ESCALATION_ENVIRONMENTS: readonly string[];

/** The ceiling only: counting is stateful, so the gateway owns the counter. */
interface RateLimitSpec {
    max: number;
    windowSeconds: number;
}
interface RuleRef {
    id: string;
    name: string;
    version: string;
}
/** Resolved from the rule that denied, never invented: this is why redirection works. */
interface Alternative {
    action: string;
    resource?: string;
    note: string;
}
interface MatchedPolicy {
    name: string;
    effect: DecisionEffect;
    reason?: string;
    approvers?: string[];
    minApprovals?: number;
    /** Set when the rule is in observe mode: it matched, but did not decide. */
    observed?: boolean;
    rateLimit?: RateLimitSpec;
    alternative?: Alternative;
    /** The workspace published it, so no allowance on this machine stands in for its answer. */
    workspace?: boolean;
    decidedBy?: string;
    decidedAt?: string;
    /** The ask rules this allow stands in for, by name. */
    relaxes?: string[];
}
interface Decision {
    /** ULID, assigned locally. Also the audit event id, so a verdict joins its record. */
    eventId: string;
    effect: DecisionEffect;
    /** What enforce WOULD have said. The hinge of observe mode and of simulation. */
    shadowEffect?: DecisionEffect;
    riskLevel: RiskLevel;
    reason: string;
    rule?: RuleRef;
    matchedPolicies: MatchedPolicy[];
    /** What the agent may do instead. Small field, most of the product's real work. */
    alternative?: Alternative;
    /** What the caller must do for the allow to stand, e.g. record an outcome. */
    obligations?: string[];
    /** Present when effect is ask, so poll or resolve this approval. */
    approvalId?: string;
    mode: EnforcementMode;
    /** Which compiled rule set decided this, and whether it was the current one. */
    bundleVersion?: string;
    bundleStale?: boolean;
    evaluatedAt: string;
    latencyUs: number;
}

/**
 * One thing an agent tried to do, and what happened to it: the row every surface writes,
 * versioned and frozen because a field that changed meaning would corrupt history.
 */

declare const EVENT_SCHEMA_VERSION = 1;
/** Where the attempt was caught. One per interception point the product ships. */
declare const EVENT_SURFACE: {
    readonly MCP: "mcp";
    readonly SHELL: "shell";
    readonly GIT: "git";
    readonly FILESYSTEM: "filesystem";
    readonly NETWORK: "network";
    /** A question somebody asked; recorded so `why` can answer about it later. */
    readonly QUESTION: "question";
    /** A change to an agent's configuration the daemon made or noticed. Not agent work. */
    readonly CONFIG: "config";
};
type EventSurface = (typeof EVENT_SURFACE)[keyof typeof EVENT_SURFACE];
/** Who was behind the attempt. Human actions on this machine are recorded too. */
declare const ACTOR_TYPE: {
    readonly AGENT: "agent";
    readonly HUMAN: "human";
    /** A pipeline or service token, which is neither and behaves like both. */
    readonly AUTOMATION: "automation";
};
type ActorType = (typeof ACTOR_TYPE)[keyof typeof ACTOR_TYPE];
/** How an attempt ended once it was allowed to run. */
declare const EXECUTION: {
    /** Allowed and completed. */
    readonly COMPLETED: "completed";
    /** Allowed and the process reported failure. Not a governance outcome. */
    readonly FAILED: "failed";
    /** Never ran, because the verdict stopped it. */
    readonly BLOCKED: "blocked";
    /** Held for a person and nobody answered in time. */
    readonly TIMED_OUT: "timed-out";
};
type Execution = (typeof EXECUTION)[keyof typeof EXECUTION];
/**
 * The rule that decided, named well enough to open the file and read the line. The
 * decision's own `RuleRef` identifies a rule; this one locates it, which is what
 * `memnox why` has to print.
 */
interface EventRuleRef {
    name: string;
    /** Which layer it came from: org, user or project. */
    layer: string;
    file: string;
    line?: number;
}
interface MemnoxEvent {
    /** Stable across a resend, so the cloud can dedupe on it. */
    id: string;
    schemaVersion: number;
    /** ISO 8601. Supplied by the caller so a replay is reproducible. */
    at: string;
    sessionId: string;
    /** The product, e.g. "claude-code". Never a credential. */
    agent: string;
    actorType: ActorType;
    /** The person whose authority this ran under, where one is known. */
    principal?: string;
    /**
     * The helper the agent handed this to, by the id its host gave it. Absent means the
     * agent's own turn: a session busy through three helpers is otherwise one agent doing everything.
     */
    subagent?: string;
    /** What kind of helper, as the host named it, e.g. "Explore". */
    subagentType?: string;
    surface: EventSurface;
    /** What was attempted, e.g. "github.merge_pull_request" or "rm". */
    operation: string;
    /** What it operated on, e.g. a path, a branch, a host. Never a payload. */
    target?: string;
    class: ToolClass;
    effect: DecisionEffect;
    /** What enforce would have said, when the mode kept it from being applied. */
    shadowEffect?: DecisionEffect;
    mode: EnforcementMode;
    reason: string;
    rule?: EventRuleRef;
    /** Resolved from the rule that denied. Never invented. */
    alternative?: Alternative;
    /**
     * Content hash of the rule set in force when this was decided, so `why` can say
     * what the rules were then rather than what they are now.
     */
    policyHash?: string;
    /**
     * The workspace bundle this machine was running when it decided, so a verdict replays
     * against what the workspace published rather than the stack this machine assembled.
     */
    bundleHash?: string;
    /** Ids of the conditions in force at the verdict, as ids because a label is derivable from one. */
    conditionsInForce?: readonly string[];
    /**
     * Ids of the settled decisions a file write bears on, as this machine's memory matched them,
     * so whoever answers for one can be asked to look at what was written.
     */
    decisionIds?: readonly string[];
    /**
     * What the gate found, as ids: the rules that matched, the part of the context each was
     * written about, and what noticing saw. Never the matched text, so `why` can say which
     * part of the context decided without the row carrying anything the call was handed.
     */
    signals?: readonly string[];
    /** A hash of the arguments. The arguments themselves never reach a row. */
    argsDigest?: string;
    execution?: Execution;
    exitCode?: number;
    durationMs?: number;
    /** A hash of what the command printed. Never the output. */
    outputDigest?: string;
    /** Who released a held call, once somebody did. */
    authorizedBy?: string;
    /**
     * What this action cost, when something able to price it said so. Memnox prices nothing,
     * and absent means nobody said, which differs from zero.
     */
    costUsd?: number;
}
/**
 * The one thing every surface writes through. Append-only by contract: a sink that
 * updated a row would make the record a claim about the past rather than the past.
 */
interface EventSink {
    append(event: MemnoxEvent): Promise<void>;
    /** Chronological. Callers on a hot path must pass a limit. */
    query(filter: EventQuery): Promise<MemnoxEvent[]>;
}
interface EventQuery {
    sessionId?: string;
    agent?: string;
    surface?: EventSurface;
    /** Only these effects, e.g. everything that was not an allow. */
    effects?: readonly DecisionEffect[];
    since?: string;
    until?: string;
    limit?: number;
    /** Config changes are left out unless asked for, so no count of agent work includes them. */
    withConfig?: boolean;
}

/** A recurring wall-clock window. Offsets are fixed minutes from UTC, with no zone database. */
interface TimeWindow {
    /** 0 = Sunday … 6 = Saturday. Omitted matches every day. */
    days?: number[];
    /** Inclusive, 0 to 23. */
    startHour: number;
    /** Exclusive, 1 to 24. A start after the end wraps past midnight. */
    endHour: number;
    /** Minutes from UTC; omitted is UTC. */
    utcOffsetMinutes?: number;
}
declare function isValidTimeWindow(window: unknown): window is TimeWindow;
/** Deterministic: the instant is an argument, never read from the clock here. */
declare function matchesTimeWindow(window: TimeWindow, at: Date): boolean;
declare function matchesAnyTimeWindow(windows: readonly TimeWindow[] | undefined, at: Date | undefined): boolean;

/** All match fields are lists of wildcard patterns; omitted fields match anything. */
interface PolicyMatch {
    actions: string[];
    targets?: string[];
    environments?: string[];
    agents?: string[];
    /**
     * The job rather than the product. A rule about "release-engineer" keeps holding
     * when the team swaps Claude Code for Codex, which `agents` cannot do.
     */
    roles?: string[];
    /** Distinct from `agents`: a delegation survives the agent being replaced. */
    principals?: string[];
    models?: string[];
    providers?: string[];
    dataClassifications?: string[];
    jurisdictions?: string[];
    /** Directory the agent is working in, e.g. "/srv/checkout/*". */
    workingDirectories?: string[];
    /** Source control branch, e.g. "main", "release/*". */
    branches?: string[];
    /**
     * What the action does, so one rule can let reads through and ask about changes. An
     * action nothing classified counts as unknown, which a rule lists to reach it.
     */
    classes?: string[];
    /**
     * What a change does, finer than its class: `transfer` moves money, `deploy` puts
     * something in front of users, `admin` hands out authority, and `execute`, `delete`,
     * `send`, `write` and `read` as they say.
     */
    capabilities?: string[];
    /** Every named argument must match; matched only by the in-process gate. */
    arguments?: Record<string, string[]>;
    /**
     * A convention on what a write adds: matches when any added line does, so a new
     * `console.log` is refused and one already there is not. In-process gate only.
     */
    content?: string[];
    /** An action that does not state its size still matches, because it cannot prove it is under. */
    aboveAmount?: number;
    /** The policy applies only inside these recurring windows. */
    windows?: TimeWindow[];
    /**
     * How the request sat against the task's declared scope. A comparison, never a
     * judgement: `out_of_scope` is a fact a rule matches on, exactly like an environment.
     */
    scope?: ScopeMatch[];
    /**
     * The company's current condition, distributed inside the bundle rather than queried.
     * A merge refused because incident 928 is open and the freeze is active is
     * organizational intelligence enforcing an action.
     */
    state?: string[];
    /**
     * Where this rule does not reach, because somebody approved an exception there. A
     * carve-out names at least one of its fields and matches only when all it names do,
     * so one the machine cannot place (no project reported, say) leaves the rule in force.
     */
    unless?: PolicyCarveOut[];
}
/** One scope a rule stands aside for. Every field it names must match. */
interface PolicyCarveOut {
    project?: string;
    agents?: string[];
    workingDirectories?: string[];
    /**
     * When the exception behind it ends. From then the rule holds again, whether or not
     * the control plane is reachable to say so.
     */
    expiresAt?: string;
}
/** Per-rule mode. An observed rule matches and is recorded, but never decides. */
declare const POLICY_MODE: {
    readonly ENFORCE: "enforce";
    readonly OBSERVE: "observe";
};
type PolicyMode = (typeof POLICY_MODE)[keyof typeof POLICY_MODE];
interface PolicyDecision {
    effect: DecisionEffect;
    reason?: string;
    approvers?: string[];
    /** Distinct people required to approve; defaults to one. */
    minApprovals?: number;
    /** "observe" records the verdict as denied and lets the action proceed. */
    mode?: PolicyMode;
    /** Counted by the gateway: a ceiling needs state and a clock, which the engine lacks. */
    rateLimit?: RateLimitSpec;
    /**
     * What the agent may do instead. Named by the rule that denies, never invented,
     * which is what makes redirection reliable enough for an agent to take.
     */
    alternative?: Alternative;
    /**
     * On an allow only: the ask rules, by name, it stands in for where both match, so a call a
     * person has said yes to often enough stops asking. Never over a deny, and only within one
     * layer, so nothing on this machine relaxes what the workspace asks.
     */
    relaxes?: string[];
}
interface Policy {
    /** Stable across a rename, so an old decision still cites the rule it matched. */
    id?: string;
    name: string;
    description?: string;
    match: PolicyMatch;
    decision: PolicyDecision;
    /** Unset = every project, so a single-project deployment is unaffected. */
    project?: string;
    /** Published by the workspace, so nothing on this machine may loosen it, `memnox allow` included. */
    workspace?: boolean;
    /** Who in the workspace approved it and when, so the reason an agent is given names a person and a day. */
    decidedBy?: string;
    decidedAt?: string;
    /** Where a rule learned from the person's notes was read, as `path#heading` or a link, so a stop cites it. */
    learnedFrom?: string[];
}
interface PolicyDocument {
    version: number;
    /** Repos declaring the same project share one policy and memory scope. */
    project?: string;
    policies: Policy[];
    /** The team's own patterns for sensitive data, each under the classification it adds. */
    classifications?: DataPattern[];
}
declare const POLICY_DOCUMENT_VERSION = 1;

export { type FindingKind as $, ACTOR_TYPE as A, BULK_ROWS as B, type Classification as C, type DataPattern as D, EFFECT_PRECEDENCE as E, type PolicyMatch as F, type PolicyMode as G, SENSITIVITY_OF_CLASSIFICATION as H, type ToolClass as I, type ToolOverrides as J, changesExternalState as K, classifyTool as L, MOST_PATTERN_CHARS as M, isToolClass as N, parseOverrides as O, type PolicyCarveOut as P, type ScopeMatch as Q, type RiskLevel as R, SENSITIVITY_BY_NAME as S, TOOL_CLASS as T, type MatchedPolicy as U, type RuleRef as V, type Alternative as W, type McpToolDeclaration as X, type EnforcementMode as Y, type Decision as Z, type ScopeComparison as _, type Policy as a, matchesTimeWindow as a$, type FindingSeverity as a0, type HardenTarget as a1, type SurfaceKind as a2, type HardenMode as a3, type Surface as a4, type ResourceKind as a5, type DiscoveredAgentKind as a6, type McpServerLaunch as a7, type ToolEffect as a8, type Sensitivity as a9, MODE_STRENGTH as aA, MUTATING_VERBS as aB, PRODUCTION_HINTS as aC, READ_ONLY_VERBS as aD, RESOURCE_KIND as aE, RISK_ESCALATION_ENVIRONMENTS as aF, RISK_LEVEL as aG, RISK_ORDER as aH, type RateLimitSpec as aI, SCOPE_MATCH as aJ, SENSITIVITY as aK, SEVERITY_ORDER as aL, SNAPSHOT_HISTORY_LIMIT as aM, SURFACE_KIND as aN, type ScopeSubject as aO, TOOL_EFFECT as aP, TRANSITIVE_SURFACES as aQ, type TaskRef as aR, type TimeWindow as aS, type ToolFilter as aT, compareDeclaredScope as aU, distinctTools as aV, effectOfName as aW, inferToolEffect as aX, isHarnessKind as aY, isValidTimeWindow as aZ, matchesAnyTimeWindow as a_, type McpToolAnnotations as aa, type ChangeSubject as ab, type ChangeDirection as ac, type McpTool as ad, CHANGE_DIRECTION as ae, CHANGE_SUBJECT as af, DATABASE_SCHEMES as ag, DEFAULT_ENFORCEMENT_MODE as ah, DESTRUCTIVE_VERBS as ai, DISCOVERED_AGENT_KIND as aj, type DeclaredScope as ak, EFFECT_INFERENCE as al, ENFORCEMENT_MODE as am, type EffectInference as an, FILTER_PRECEDENCE as ao, FINDING_KIND as ap, FINDING_SEVERITY as aq, FINGERPRINT_ALGORITHM as ar, FINGERPRINT_LENGTH as as, type FilterPrecedence as at, HARDEN_MODE as au, HARDEN_TARGET as av, HARNESS_KINDS as aw, KNOWN_TOOLS as ax, MCP_PROBE_TIMEOUT_MS as ay, MCP_PROTOCOL_VERSION as az, type ActionRequest as b, nameSegments as b0, passesFilter as b1, toMcpTool as b2, type ActorType as c, type CompiledPattern as d, DATA_CLASSIFICATION as e, DATA_CLASSIFICATIONS as f, DATA_CLASSIFICATION_MEANING as g, DATA_SENSITIVITY as h, DECISION_EFFECT as i, DECISION_REASON as j, type DataClassification as k, type DataSensitivity as l, type DecisionEffect as m, EVENT_SCHEMA_VERSION as n, EVENT_SURFACE as o, EXECUTION as p, type EventQuery as q, type EventRuleRef as r, type EventSink as s, type EventSurface as t, type Execution as u, type MemnoxEvent as v, POLICY_DOCUMENT_VERSION as w, POLICY_MODE as x, type PolicyDecision as y, type PolicyDocument as z };
