// src/daemon/community-index.ts
var INDEX_METHOD = {
  /** The index, filtered by words and kind, read fresh or from what was last read. */
  INDEX_LIST: "index-list",
  /** Fetches one version, checks its digest, and holds the skill or proposes the pack's rules. */
  INDEX_INSTALL: "index-install",
  /** Where the index is read from: a new one is a proposal the Mac signs, the marketplace again is at once. */
  INDEX_SOURCE_SET: "index-source-set"
};
var INDEX_SOURCE = {
  /** Memnox Cloud's marketplace, of the workspace this machine is on: the default. */
  MARKETPLACE: "marketplace"
};
var INDEX_KIND = {
  SKILL: "skill",
  RULE_PACK: "rule_pack"
};

// src/daemon/memory-layers.ts
var MEMORY_LAYERS_METHOD = {
  /** Each project's three layers as they stand: MEMORY.md, the router files, and the SKILL.md skills. */
  MEMORY_LAYERS: "memory-layers",
  /** The proposed MEMORY.md index and router lines for one project, a preview that writes nothing. */
  MEMORY_LAYERS_PLAN: "memory-layers-plan",
  /** Writes the plan the person confirmed, refused when the files changed since it was shown. */
  MEMORY_LAYERS_APPLY: "memory-layers-apply",
  /** The last thirty days of chats: how often a cold cache was loaded again, and what keeping it warm saves. */
  SESSION_COST: "session-cost"
};
var MEMORY_LAYER = {
  /** MEMORY.md, read in every chat: one line per memory, each linked to its file. */
  INDEX: "index",
  /** CLAUDE.md, AGENTS.md, GEMINI.md or Cursor's rules: one line per department. */
  ROUTER: "router",
  /** One memory written as its own file, which the index links to. */
  MEMORY: "memory"
};

// src/daemon/memory.ts
var MEMORY_METHOD = {
  /** Every source with where it is, its trust, when it was last read and what it taught. */
  MEMORY_SOURCES: "memory-sources",
  /** Adds a folder, a repository's instruction files, an export, Supermemory or a hub server. */
  MEMORY_SOURCE_ADD: "memory-source-add",
  /** Takes a source away; what it taught goes outdated rather than vanishing. */
  MEMORY_SOURCE_REMOVE: "memory-source-remove",
  /** Reads a source again now and extracts what changed, with the person's own agent CLI. */
  MEMORY_SOURCE_READ: "memory-source-read",
  /** The Learn queue: candidates and conflicts waiting on a person. */
  MEMORY_LEARN: "memory-learn",
  /** A fact becomes verified; a rule candidate raises a signed rule proposal. */
  MEMORY_CONFIRM: "memory-confirm",
  /** Rejected, and remembered so the same words are never proposed again. */
  MEMORY_REJECT: "memory-reject",
  /** A candidate's words or its rule changed before it is confirmed. */
  MEMORY_EDIT: "memory-edit",
  /** Search over what was learned: keyword, and by meaning too where a local embedding model is turned on. */
  MEMORY_SEARCH: "memory-search",
  /** What was learned, by status and scope; verified by default. */
  MEMORY_FACTS: "memory-facts",
  /** Deletes one item and its evidence. */
  MEMORY_FORGET: "memory-forget",
  /**
   * What the workspace settled and what its connected tools said, as this machine last pulled
   * it, read off disk with no network near it. Only a read down: nothing local goes up with it.
   */
  WORKSPACE_MEMORY: "workspace-memory",
  /**
   * The workspace's memory graph as the console draws it, read live off the control plane on this
   * machine's own credential and held only in memory, folded with the saved facts. Where the cloud
   * cannot be reached or refuses, the saved facts alone, saying why.
   */
  WORKSPACE_GRAPH: "workspace-graph",
  ...MEMORY_LAYERS_METHOD
};
var EXTRACTOR_STATE = {
  ANSWERED: "answered",
  /** No agent CLI could be asked, so the new passages wait for the next read. */
  UNAVAILABLE: "unavailable",
  /** It answered in no shape that could be read. */
  UNREADABLE: "unreadable",
  /** Nothing new to read. */
  IDLE: "idle"
};
var MEMORY_SEARCH_MODE = {
  KEYWORD: "keyword",
  SEMANTIC: "semantic"
};

// src/daemon/activity.ts
var ACTIVITY_METHOD = {
  /** One page of the ledger, newest first, filtered and bounded. */
  ACTIVITY: "activity",
  /** One decision whole: its rule, who handed the work down, what led up to it, and the trace. */
  DECISION: "decision",
  /** The rows a filter selects, as a signed bundle an auditor can check. */
  ACTIVITY_EXPORT: "activity-export"
};
var ACTIVITY_KIND = {
  TOOL: "tool",
  COMMAND: "command",
  FILE: "file",
  MCP: "mcp"
};
var ANSWERED_HOW = {
  /** With Touch ID or Face ID. */
  SIGNED: "signed",
  /** On the Mac, for a call that stayed inside its session's repository. */
  WITHIN_SESSION: "within-session",
  /** By voice, in a terminal, or any route that names itself otherwise. */
  OTHER: "other"
};
var MOST_LIVE_ACTIVITY_ROWS = 20;

// src/daemon/home.ts
var HOME_METHOD = {
  /** The five blocks, read once, so a screen draws them without asking five questions. */
  HOME: "home",
  /** Turns the ready suggestion into a rule proposal the person confirms with Touch ID or Face ID. */
  HAND_OVER: "hand-over",
  /**
   * Puts this machine from observe into enforce, unsigned because it only narrows what agents may do. Going back
   * to observe widens, so no surface offers it here and it stays `memnox protect --observe` at the terminal.
   */
  MODE_ENFORCE: "mode-enforce"
};

// src/daemon/intercept.ts
var INTERCEPT_METHOD = {
  /** Rule on a whole command line, as `memnox-intercept` would before running it. */
  INTERCEPT: "intercept",
  /** The client acted on the plan it was given, so the daemon may write the row for it. */
  INTERCEPT_ACTED: "intercept-acted",
  /** The command the plan allowed has ended, with its exit code. */
  INTERCEPT_RAN: "intercept-ran"
};
var FAST_INTERCEPT_VERSION = 1;
var INTERCEPT_PLAN = {
  /** Run the real binary and report how it ended, which writes the row. */
  RUN: "run",
  /** Run the real binary with nothing recorded: a person typed it, or protection is stopped. */
  PASS: "pass",
  /** Print the message and exit with the code given, without running anything. */
  REFUSE: "refuse",
  /** Hand the same argv to the Node interceptor, which is always right. */
  NODE: "node"
};
function encodeInterceptLine(line) {
  const env = `{${line.env.map(([name, value]) => `${JSON.stringify(name)}:${JSON.stringify(value)}`).join(",")}}`;
  return `{"id":1,"method":${JSON.stringify(INTERCEPT_METHOD.INTERCEPT)},"fast":${FAST_INTERCEPT_VERSION},"argv":${JSON.stringify(line.argv)},"cwd":${JSON.stringify(line.cwd)},"ppid":${line.ppid},"env":${env}}
`;
}
function isInterceptMethod(method) {
  return Object.values(INTERCEPT_METHOD).includes(method);
}

// src/daemon/mcp-hub.ts
var MCP_HUB_METHOD = {
  /** Servers, agents, and what each agent's config holds that the hub did not write. */
  HUB: "mcp-hub",
  /** Adds or replaces a server; widening, so it becomes a proposal the person signs. */
  SERVER_PUT: "mcp-server-put",
  /** Takes a server away from the hub and from every agent it was given to. */
  SERVER_REMOVE: "mcp-server-remove",
  /** Gives a server to an agent, signed, or takes it away, unsigned. */
  ASSIGN: "mcp-assign",
  /** Takes a server the person configured themselves into the hub, for that same agent. */
  IMPORT: "mcp-import",
  /** Writes what the hub says into every agent's config it can write. */
  SYNC: "mcp-sync",
  /** Asks one server for its tools, on request and never on a timer. */
  TEST: "mcp-test",
  /** Keeps a credential in the OS store, typed on this machine and never sent from afar. */
  SECRET_SET: "mcp-secret-set",
  SECRET_REMOVE: "mcp-secret-remove"
};
var MCP_HEALTH = {
  UNKNOWN: "unknown",
  HEALTHY: "healthy",
  ERROR: "error"
};
var MCP_SCOPE = {
  PERSONAL: "personal",
  ORGANIZATION: "organization"
};

// src/daemon/policies.ts
var POLICY_METHOD = {
  /** Every rule in force on this machine, with where it came from and what would not load. */
  POLICY_RULES: "rules",
  /** A rule filled in on a form; it holds only once the person signs the proposal it raises. */
  RULE_PROPOSE: "rule-propose",
  /** Removing a person's rule: an allow goes at once, a deny or an ask waits on a signature. */
  RULE_REMOVE: "rule-remove",
  /** One action ruled on against the rules in force, recording and changing nothing. */
  RULE_TEST: "rule-test",
  /** The rules a person added here, as TOML text. */
  RULES_EXPORT: "rules-export",
  /** A pack of rules as TOML, each turned into its own signed proposal. */
  RULE_PACK_IMPORT: "rule-pack-import",
  /** The packs Memnox ships, each offered whole and imported through RULE_PACK_IMPORT. */
  RULE_PACKS: "rule-packs",
  /** What could be handed over, what the autopilot holds, and where the machine stands. */
  PROGRESS: "progress",
  /** Takes one autopilot grant back at once, since that only narrows. */
  AUTOPILOT_REVOKE: "autopilot-revoke"
};
var RULE_SOURCE = {
  /** A person added it on this machine, by voice, a form or a hand over. */
  PERSON: "person",
  /** A rule file in a repository, the person's to edit and commit. */
  FILE: "file",
  /** Published by the workspace and pulled here; nothing on this machine loosens it. */
  WORKSPACE: "workspace",
  /** The baseline setup wrote. */
  DEFAULT: "default",
  /** Handed to one agent by the autopilot, for a while. */
  AUTOPILOT: "autopilot",
  /** Allowed for a while with `memnox allow`. */
  ALLOWANCE: "allowance",
  /** A pause or a freeze in force, which ends on its own. */
  FREEZE: "freeze",
  /** Read out of the person's notes, confirmed in Learn and signed; it names where it was read. */
  EXTRACTED: "extracted"
};

// src/daemon/agents-view.ts
var AGENTS_METHOD = {
  /** Every agent found here, one card each. */
  AGENTS: "agents",
  /** Holds one agent at once, since that only narrows. */
  AGENT_PAUSE: "agent-pause",
  /** Lets a paused agent carry on, which waits on the person's signature. */
  AGENT_RESUME: "agent-resume",
  /** Holds one session before its next action, at once. */
  SESSION_STOP: "session-stop",
  /** Opens the agent in a new terminal in a folder, for an agent with a known launch command. */
  AGENT_LAUNCH: "agent-launch",
  /**
   * Every agent the scan finds now, with the counted facts the full screen scan draws, read and never shown, so a
   * screen draws it without asking the voice. A server never asked starts one full count behind the answer.
   */
  AGENTS_SCAN: "agents-scan"
};
var AGENT_STATUS = {
  /** Its hook is in, or every server it starts runs through Memnox, so whatever Memnox can see of it is ruled on. */
  PROTECTED: "protected",
  /** Found here and running outside Memnox. */
  UNPROTECTED: "unprotected",
  /** Silent for a month and still holding reach. */
  DORMANT: "dormant",
  /** A person paused it; nothing it asks for runs. */
  PAUSED: "paused"
};
var AGENT_SEAM = {
  /** Its own hook, which every action passes. */
  HOOK: "hook",
  /**
   * Only the MCP servers it starts, as for Claude Desktop, which has no hook. It reads its config when it
   * opens, so servers put behind Memnox reach it once it is quit and opened again.
   */
  SERVERS: "servers"
};

// src/daemon/skills-hub.ts
var SKILLS_METHOD = {
  /** Skills, the agents that take them, and skills found on this machine to import. */
  SKILLS_HUB: "skills-hub",
  /** Takes a skill found in an agent's folder into the hub, its files with it. */
  SKILL_IMPORT: "skill-import",
  /** Adds a skill or a new version; one reaching further than the accepted version waits on a signature. */
  SKILL_PUT: "skill-put",
  /** Gives a skill to an agent, signed, or takes it away, unsigned. */
  SKILL_ASSIGN: "skill-assign",
  /** Takes a skill out of every agent at once, keeping its assignments for later. */
  SKILL_DISABLE: "skill-disable",
  /** Hands a disabled skill back to the agents it was given to, as accepted. */
  SKILL_ENABLE: "skill-enable",
  /** Writes what the hub says into every agent it can write. */
  SKILL_SYNC: "skill-sync",
  /** Hands out an older accepted version again; signed where it reaches further than the current one. */
  SKILL_ROLLBACK: "skill-rollback",
  /** Accepts a held skill's folder as it is now; signed where it reaches further. */
  SKILL_ACCEPT: "skill-accept",
  /** Takes a skill out of the hub and every agent at once, its kept versions with it, since that only narrows. */
  SKILL_REMOVE: "skill-remove",
  /** How often each skill was used lately, and how often what ran inside it failed or was refused. */
  SKILL_STATS: "skill-stats",
  /** Adds one line to a skill's fix backlog, which nothing reads until the person calibrates it. */
  SKILL_NOTE: "skill-note",
  /** A suggested SKILL.md built from the backlog and the failures, a preview that changes nothing. */
  SKILL_CALIBRATE: "skill-calibrate"
};

// src/daemon/projects.ts
var PROJECTS_METHOD = {
  /** Every project on this machine, opened or found, most recently active first. */
  PROJECTS: "projects",
  /** Takes a folder in as a project and applies it; what widens an agent waits on a signature. */
  PROJECT_OPEN: "project-open",
  /** Writes a project's `.memnox/project.toml` from a form, applying nothing until asked. */
  PROJECT_PUT: "project-put",
  /** Hands the project's instructions to its agents at once, and proposes its servers, skills and rules. */
  PROJECT_APPLY: "project-apply"
};
var PROJECT_SCOPE = {
  /** Shared by the organization in Memnox Cloud and laid over the clone, read only here. */
  ORGANIZATION: "organization"
};

// src/daemon/backup.ts
var BACKUP_METHOD = {
  /** Seals the setup under a passphrase and hands the archive back as text. */
  BACKUP_CREATE: "backup-create",
  /** Opens an archive and proposes putting it back, which holds once the person signs it. */
  BACKUP_RESTORE: "backup-restore"
};

// src/daemon/lan.ts
var LAN_METHOD = {
  /** Whether the local network is on, where it listens, whether it is advertised, and which phones reach it. */
  LAN_STATUS: "lan-status",
  /** Turns it off at once, or proposes turning it on, which holds once the person signs it on the Mac. */
  LAN_SET: "lan-set"
};

// src/daemon/personal-sync.ts
var PERSONAL_SYNC_METHOD = {
  /** Where sync stands here: the key, the last run, what was left out, and any machine waiting. */
  PERSONAL_SYNC_STATUS: "personal-sync-status",
  /** Pulls what the person's other machines sent, then sends what changed here. */
  PERSONAL_SYNC_NOW: "personal-sync-now",
  /** The copies a sync replaced without having seen them, opened for the person to choose from. */
  PERSONAL_SYNC_CONFLICTS: "personal-sync-conflicts",
  /** Keeps one side of a conflict: the copy taken back here, or this machine's own. */
  PERSONAL_SYNC_RESOLVE: "personal-sync-resolve",
  /** On a machine holding the key: proposes sealing it to a waiting machine whose fingerprint the person compared. */
  PERSONAL_SYNC_KEY_OFFER: "personal-sync-key-offer",
  /** On a new machine: proposes taking the key sealed to it, once the person compared the same fingerprint. */
  PERSONAL_SYNC_KEY_ACCEPT: "personal-sync-key-accept"
};
var PERSONAL_SYNC_STATE = {
  /** Not on Memnox Cloud, so there is nowhere to carry anything. */
  OFF: "off",
  /** No sync key here yet: another of the person's machines has to seal it to this one. */
  WAITING_FOR_KEY: "waiting-for-key",
  /** A key sealed to this machine arrived and waits for the person to compare and accept it. */
  KEY_ARRIVED: "key-arrived",
  READY: "ready",
  /** The plan does not carry personal sync; what is here stays here. */
  NOT_ON_PLAN: "not-on-plan",
  /** The credential speaks for no person, so it has nothing of its own to sync. */
  NO_PERSON: "no-person"
};
var SYNC_KEEP = {
  /** The copy the cloud kept, put back here and sent as the newest. */
  THEIRS: "theirs",
  /** What this machine holds now; the kept copy is let go. */
  MINE: "mine"
};

// src/daemon/profiles.ts
var PROFILES_METHOD = {
  /** Every profile kept here, with what of each the hubs no longer hold. */
  PROFILES: "profiles",
  /** Adds a profile or replaces one of the same name; it grants nothing until it is applied. */
  PROFILE_PUT: "profile-put",
  /** Forgets a profile; what it already handed out stays where it was given. */
  PROFILE_REMOVE: "profile-remove",
  /** Proposes giving an agent the profile's servers and skills, in a project, and its rule pack's rules. */
  PROFILE_APPLY: "profile-apply",
  /** Binds a kept profile to one agent found here; its ledger key stays `agt_<kind>`. */
  PROFILE_BIND: "profile-bind",
  /** Takes a binding off, which puts the agent back on its default profile. */
  PROFILE_UNBIND: "profile-unbind",
  /** The catalog of job descriptions, none with an agent behind it. */
  TEMPLATES: "templates",
  /** Copies a template's job into a new profile, with only the suggested skills a person took. */
  PROFILE_FROM_TEMPLATE: "profile-from-template"
};

// src/daemon/work.ts
var WORK_METHOD = {
  /** Every piece of agent work kept here, newest change first. */
  WORK: "agent-work",
  /** A person pointing a profile's agent at an issue: `LIN-123`, a Jira key, or an issue link. */
  WORK_START: "work-start",
  /** A person stopping it, whatever the agent said. */
  WORK_STOP: "work-stop",
  /** A person closing it as done, usually once the agent claimed it. */
  WORK_CLOSE: "work-close",
  /** A person accepting or declining an agent's request to hand the work on. */
  HANDOFF_ANSWER: "handoff-answer"
};
var HANDOFF_ANSWER_WORD = {
  ACCEPT: "accept",
  DECLINE: "decline"
};

// src/daemon/remote.ts
var REMOTE_METHOD = {
  /** Opens a pairing and answers the QR the Mac shows; refused while the machine is not on Memnox Cloud. */
  PAIR_BEGIN: "pair-begin",
  /** Streams where a pairing stands until it is paired, declined or expired. */
  PAIR_PENDING: "pair-pending",
  /** The person's yes to a device: signed by the Mac over `pairMessage`, or the device's digits where no Mac key is kept. */
  PAIR_ACCEPT: "pair-accept",
  /** The person's no to a phone, unsigned since saying no can do no harm. */
  PAIR_DECLINE: "pair-decline",
  DEVICES_LIST: "devices-list",
  /** Takes a device's access away, unsigned since it only narrows what is allowed. */
  DEVICE_REVOKE: "device-revoke",
  /** One more capability for a device, signed by the Mac over `grantMessage` wherever a Mac key is kept. */
  DEVICE_GRANT: "device-grant",
  /** One capability taken back from a device, unsigned since it only narrows what is allowed. */
  DEVICE_UNGRANT: "device-ungrant",
  /** The Kokoro voice the person picked on the Mac, handed to a paired phone inside the tunnel. */
  VOICE_CHOICE: "voice-choice",
  /** A phone driving the Mac until a time it signed for, or stopping when it names none. */
  DRIVE: "drive",
  /** A phone whose app left the screen handing the voice back to the Mac, unsigned since it only gives power up. */
  VOICE_RELEASE: "voice-release"
};
var REMOTE_OUTCOME = {
  PAIRING: "pairing",
  PAIRED: "paired",
  DECLINED: "declined",
  REVOKED: "revoked",
  GRANTED: "granted",
  UNGRANTED: "ungranted",
  REFUSED: "refused",
  DRIVING: "driving",
  STOPPED: "stopped"
};
var PAIRING_STATE = {
  /** The QR is up and no phone has reached it yet. */
  WAITING: "waiting",
  /** A phone finished the handshake and proved its key, and waits on the person. */
  ANSWERED: "answered",
  PAIRED: "paired",
  DECLINED: "declined",
  EXPIRED: "expired"
};
function pairMessage(pairingId, fingerprint) {
  return `memnox-pair:v1:${pairingId}:${fingerprint}`;
}
function grantMessage(deviceId, capability) {
  return `memnox-grant:v1:${deviceId}:${capability}`;
}
function driveMessage(deviceId, until) {
  return `memnox-drive:v1:${deviceId}:${until}`;
}
function followUpMessage(sessionId, words) {
  return `memnox-follow-up:v1:${sessionId}:${words}`;
}
var FOLLOW_UP_OUTCOME = {
  /** Working: it reads the words at its next step. */
  QUEUED: "queued",
  /** Waiting at its prompt: the Mac is typing the words in and sending them. */
  TYPED: "typed",
  /** Waiting where nothing can type: it reads the words the next time it is prompted. */
  LATER: "later"
};
function deviceProofMessage(handshakeHash) {
  return `memnox-device:v1:${handshakeHash.toString("base64")}`;
}

// src/daemon/speech.ts
var SPEECH_METHOD = {
  /** One line rendered by the Mac app's Kokoro server, streamed back as pieces of PCM. */
  SPEAK: "speak"
};

// src/daemon/spoken-rule.ts
var SPOKEN_RULE_METHOD = {
  /** One sentence drafted into a rule; with no open question left it is proposed for Touch ID or Face ID. */
  RULE: "rule"
};
var RULE_DRAFTED_BY = {
  PATTERN: "pattern",
  MODEL: "model"
};

// src/daemon/display.ts
var DISPLAY = {
  /** Bring the session's own window forward. */
  OPEN: "open",
  /** Put a summary card on screen while the voice reads it. */
  CARD: "card",
  /** Type the person's confirmed instruction into the terminal tab the agent waits in. */
  TYPE: "type",
  /** Open the session in its editor with the instruction in its input, for the person to send. */
  PREFILL: "prefill",
  /** Turn through the sessions to this one and bring its own terminal tab or editor forward. */
  FOCUS: "focus",
  /** Open a new terminal tab in a repository and type the line that starts an agent there. */
  LAUNCH: "launch",
  /** Open an agent's own desktop app on a repository, with the task handed to it through its links. */
  APP: "app",
  /** A card that pages through a session's changed files while the voice walks through them. */
  WALK: "walk",
  /** The whole screen: every agent on this Mac, found by a live scan, with what each reaches. */
  AGENTS: "agents",
  /** A trace as a waterfall card: what ran, inside what, for how long, and what failed. */
  TRACE: "trace",
  /** Every session lately as one card each, together, so they can be read at a glance. */
  SESSIONS: "sessions",
  /** Close the live window on a session and its own terminal tab, which ends the agent there. */
  CLOSE: "close",
  /** Press Escape in the terminal a session runs in, which stops its turn where it is and keeps the tab. */
  INTERRUPT: "interrupt",
  /** Take every Memnox card and window off the screen, leaving every agent and its tab alone. */
  DISMISS: "dismiss",
  /** A message from the person's connected mail, drafted for them to read; Send is a signed CONFIRM of `subject`. */
  DRAFT: "draft",
  /** Open a folder the person named; its title says where: finder, editor or terminal. */
  FOLDER: "folder",
  /** Look at the screen: the Mac captures the window in front, or the app named in the title, and answers with SEEN. */
  LOOK: "look",
  /** Press keys in the terminal a session runs in, the text naming them, to answer what its agent asks there. */
  PRESS: "press",
  /** The icons of tools the person asked for and has not signed in to; each opens that tool's own sign in. */
  SIGN_IN: "signin",
  /** A web page the person asked to open, its one http or https address in `links`, opened in their browser. */
  LINK: "link"
};
var DISPLAY_VIA = {
  /** Another terminal app, such as Ghostty, opened on the folder with the line typed into its new window. */
  TERMINAL_APP: "terminal-app",
  /** An editor's agent panel, opened on the folder with the task sent as a new conversation. */
  PANEL: "panel",
  /** On APP, a new chat started in the app before the words are typed, rather than the one open. */
  NEW_CHAT: "new-chat",
  /**
   * On APP, the words the app's own prompt link left in its chat sent with Return, only once the Mac
   * reads them in the focused chat input; the Mac answers verified when it sent them.
   */
  SEND_PREFILLED: "send-prefilled"
};
var TERMINAL_KEY = {
  UP: "up",
  DOWN: "down",
  LEFT: "left",
  RIGHT: "right",
  ENTER: "enter",
  ESCAPE: "escape",
  TAB: "tab",
  SPACE: "space"
};
var MOST_PRESSED_KEYS = 8;
var ONE_CHARACTER = /^[a-z0-9]$/;
var NAMED_KEYS = Object.values(TERMINAL_KEY);
function terminalKeys(said) {
  const keys = said.toLowerCase().split(/[\s,]+/).filter((word) => word !== "");
  if (keys.length === 0 || keys.length > MOST_PRESSED_KEYS) return null;
  return keys.every((key) => NAMED_KEYS.includes(key) || ONE_CHARACTER.test(key)) ? keys : null;
}

// src/daemon/session-view.ts
var SPEAKER = {
  PERSON: "person",
  AGENT: "agent",
  /** A tool the agent ran, by its name and what it was for. */
  TOOL: "tool"
};

// src/daemon/protocol.ts
var DAEMON_METHOD = {
  /** Rule on one action. The hot path, and the only one with a latency budget. */
  EVALUATE: "evaluate",
  /** Ask a person, through whatever terminal the daemon owns. */
  HOLD: "hold",
  /** Record how a command ended, so a session is one timeline and the breaker can count outcomes. */
  RECORD: "record",
  /** Whether this session is held, asked before anything runs. */
  STATUS: "status",
  /** Liveness, for `memnox doctor`. */
  PING: "ping",
  /** Keeps the connection open and writes one line per thing that starts waiting on a person. */
  SUBSCRIBE: "subscribe",
  /** What is waiting on a person right now: held calls and proposals. */
  WAITING: "waiting",
  /** A person's answer to a held call or a proposal; a yes carries a signature unless the call stays within its session. */
  CONFIRM: "confirm",
  /** The public half of the key a confirmation is signed with, trusted on first use. */
  REGISTER_KEY: "register-key",
  /** What the person said, answered by their own agent CLI one chunk per line as it streams. */
  ASK: "ask",
  /** Stops the answer in flight, usually because the person started talking over it. */
  CANCEL: "cancel",
  /** Where a session's agent is on screen, so the Mac app can bring that window forward. */
  LOCATE: "locate",
  /** Something happened rather than was asked: the brain says it, streamed like ASK. */
  BRIEF: "brief",
  /** The person started talking: start the brain now so the answer skips the cold start. */
  WARM: "warm",
  /** The names this machine uses, for the recognizer to listen for. */
  VOCABULARY: "vocabulary",
  /** A session as it is right now, for the live window the Mac app opens on it. */
  SESSION_VIEW: "session-view",
  /** The sessions lately, each as a card, for the switcher that turns through them. */
  SESSIONS_LIST: "sessions-list",
  /** The Mac app saying whether an instruction it was asked to type landed, so nobody is told it did when it did not. */
  DELIVERED: "delivered",
  /** The Mac app's own timings for the question just answered: hearing, waiting for the end, speaking. */
  TRACE: "trace",
  /** Which of the person's agents can be the voice, and why the others cannot. */
  VOICE_AGENTS: "voice-agents",
  /** The person picking which agent the voice thinks with, from the Mac app's settings. */
  CHOOSE_VOICE_AGENT: "choose-voice-agent",
  /** Words the person fixed in what the Mac typed for them, kept so they are heard right next time. */
  LEARN_WORDS: "learn-words",
  /** The Mac app answering a LOOK display with what was on screen: a capture and the window's outline. */
  SEEN: "seen",
  /** One folder under the person's home, names and sizes only, so a phone browses the Mac without the brain or the screen. */
  FILES_LIST: "files-list",
  /** Whether a person is signed in on this daemon, which is what the voice and the terminal act through. */
  PERSON: "person",
  /** The Mac app starting the daemon's own sign in, which answers with the code and polls behind it. */
  PERSON_SIGN_IN: "person-sign-in",
  /** The Mac app signing the daemon's person out, revoking this terminal on the control plane. */
  PERSON_SIGN_OUT: "person-sign-out",
  /** The apps the person connected through the workspace, Gmail or Slack say, for the Mac's menu bar and notch. */
  CONNECTIONS_LIST: "connections-list",
  /** Connecting one tool as the person, any toolkit and any role: answers its sign in page, opened on the Mac when asked there. */
  CONNECTIONS_SIGN_IN: "connections-sign-in",
  /** Undoing every sign in the person made to one tool, answering the list as it now stands. */
  CONNECTIONS_SIGN_OUT: "connections-sign-out",
  /** The tools anybody can connect, from the cloud's catalogue, so a screen offers more than the ones already known. */
  TOOLKITS_SEARCH: "toolkits-search",
  /** Whether this machine is connected to a workspace, which is what carries rules, memory and phones to it. */
  MACHINE: "machine",
  /** The Mac app connecting this machine to a workspace: the device flow `memnox login` runs, polled behind the answer. */
  MACHINE_SIGN_IN: "machine-sign-in",
  /** The Mac app disconnecting this machine, which forgets its credential; rules already pulled stay in force. */
  MACHINE_SIGN_OUT: "machine-sign-out",
  /** Dictation written the way the person would have typed it, by their own agent CLI kept warm for it. */
  POLISH: "polish",
  /** Starts the process that polishes dictation, as the key goes down, so the answer skips its cold start. */
  POLISH_WARM: "polish-warm",
  /** The person's own words typed into one session, verbatim and never read by the brain; signed over `followUpMessage` only at the Mac. */
  FOLLOW_UP: "follow-up",
  ...REMOTE_METHOD,
  ...SPEECH_METHOD,
  ...HOME_METHOD,
  ...INTERCEPT_METHOD,
  ...SPOKEN_RULE_METHOD,
  ...MCP_HUB_METHOD,
  ...POLICY_METHOD,
  ...ACTIVITY_METHOD,
  ...AGENTS_METHOD,
  ...SKILLS_METHOD,
  ...PROJECTS_METHOD,
  ...BACKUP_METHOD,
  ...MEMORY_METHOD,
  ...LAN_METHOD,
  ...PERSONAL_SYNC_METHOD,
  ...PROFILES_METHOD,
  ...WORK_METHOD,
  ...INDEX_METHOD
};
var BRIEFING = {
  /** A held call, told with what its session has been doing. */
  HELD: "held",
  /** A session the breaker stopped. */
  PAUSED: "paused",
  /** The person came back to their Mac. */
  BACK: "back",
  /** Something worth telling without being asked: a session finished, committed or pushed. */
  NOTICE: "notice"
};
var ASK_ENDS = ["done", "limited", "failed", "cancelled"];
var DAEMON_EVENT = {
  /** A call is held until a person answers it. */
  HELD: "held",
  /** Something suggested a change a person has to confirm. */
  PROPOSAL: "proposal",
  /** The breaker stopped a session. */
  PAUSED: "paused",
  /** Something told before is no longer waiting: answered elsewhere, or expired. */
  SETTLED: "settled",
  /** The person asked to see a session: its window brought forward, or its summary on a card. */
  SHOW: "show",
  /** Something worth saying unasked: a session finished, committed or pushed. */
  NOTICE: "notice",
  /** Rows the ledger gained that a screen's activity view shows, names only, a burst at most once a second. */
  ACTIVITY: "activity",
  /** A piece of agent work changed: started, reported on, handed on, stopped or closed. */
  WORK: "work"
};
function encode(message) {
  return `${JSON.stringify(message)}
`;
}

// src/gate/answers.ts
var HOLD_ANSWER = {
  /** This call only. The next identical one asks again. */
  ONCE: "once",
  /** Every identical call for the rest of this session. */
  SESSION: "session",
  DENY: "deny",
  /** The command was wrong rather than the rule, so the person fixes it and the loop survives. */
  EDIT: "edit"
};
var HOLD_ANSWER_LABEL = {
  [HOLD_ANSWER.ONCE]: "Allow once",
  [HOLD_ANSWER.SESSION]: "Allow for this session",
  [HOLD_ANSWER.EDIT]: "Edit the command first",
  [HOLD_ANSWER.DENY]: "Deny"
};
var HOLD_ANSWER_ORDER = [
  HOLD_ANSWER.ONCE,
  HOLD_ANSWER.SESSION,
  HOLD_ANSWER.EDIT,
  HOLD_ANSWER.DENY
];
var HOLD_OUTCOME_WORD = {
  [HOLD_ANSWER.ONCE]: "allowed once",
  [HOLD_ANSWER.SESSION]: "allowed for this session",
  [HOLD_ANSWER.EDIT]: "editing",
  [HOLD_ANSWER.DENY]: "denied"
};
var ALWAYS_ALLOW_LABEL = "Always allow";
var ALWAYS_DENY_LABEL = "Always deny";
var PROPOSAL_ANSWER = {
  CONFIRMED: "confirmed",
  DECLINED: "declined"
};

// src/gate/confirm-message.ts
function confirmationMessage(subject, answer, edited, editedTo) {
  if (editedTo !== void 0)
    return `memnox-confirm:v3:${subject}:${answer}:${editedTo}:${edited ?? ""}`;
  if (edited === void 0) return `memnox-confirm:v1:${subject}:${answer}`;
  return `memnox-confirm:v2:${subject}:${answer}:${edited}`;
}
function actionConfirmationMessage(subject, answer, actionDigest) {
  return `memnox-confirm:v4:${subject}:${answer}:${actionDigest}`;
}

// src/gate/remote-capability.ts
var REMOTE_CAPABILITY = {
  SEE: "see",
  ASK: "ask",
  /** A held call, or a proposal answering one. */
  ANSWER: "answer",
  /** Stopping, freezing or resuming, and the person's own follow up typed into a session. */
  STEER: "steer",
  RULES: "rules",
  REWIND: "rewind",
  /** Driving, and a proposal for something only the Mac can do. */
  MAC: "mac"
};

// src/daemon/delivery.ts
var DELIVERY = {
  /** Typed into the agent's prompt and sent, though nothing read it back, so it is not known to have landed. */
  TYPED: "typed",
  /** Typed and sent, and the Mac read the target back and saw it land, which `proof` says how. */
  VERIFIED: "verified",
  /** Left for the session's next prompt, since reaching it now would have taken the person's window. */
  WAITING: "waiting",
  /** It could not be typed safely, so the words were left on the clipboard. */
  CLIPBOARD: "clipboard",
  /** The Mac is not allowed to press keys until the person turns Memnox on under Accessibility, so the words were left on the clipboard. */
  NOT_ALLOWED: "not-allowed",
  /** Nothing was typed anywhere. */
  FAILED: "failed"
};
function wentIn(outcome) {
  return outcome === DELIVERY.TYPED || outcome === DELIVERY.VERIFIED;
}

// src/daemon/voice-cards.ts
var ASK_INTENT = {
  RULE: "rule",
  /** What they asked before a sign in, asked again by the Mac once it finished, never something said just now. */
  RESUME: "resume"
};
var RULE_SCOPE = {
  MACHINE: "machine",
  REPOSITORY: "repository",
  /** Offered to the workspace, where a second admin approves it and every agent that reads the bundle follows it. */
  TEAM: "team"
};
var DRAFT_MODE = {
  COMPOSE: "compose",
  REPLY: "reply"
};
var MAIL_SERVICE = {
  GMAIL: "gmail"
};

// src/daemon/work-cards.ts
var WORK_ACCOUNT_CHECK = {
  MATCHED: "matched",
  UNVERIFIED: "unverified",
  MISMATCH: "mismatch",
  UNKNOWN: "unknown"
};
var WORK_DRAFT_KIND = {
  MESSAGE: "message",
  COMMENT: "comment",
  EMAIL: "email",
  ISSUE: "issue",
  EVENT: "event",
  PAGE: "page",
  OTHER: "other"
};
var KIND_WORDS = [
  [WORK_DRAFT_KIND.COMMENT, ["COMMENT", "REVIEW", "REACTION"]],
  [WORK_DRAFT_KIND.EMAIL, ["EMAIL", "MAIL", "DRAFT"]],
  [WORK_DRAFT_KIND.EVENT, ["EVENT", "MEETING"]],
  [WORK_DRAFT_KIND.PAGE, ["PAGE", "DOCUMENT", "DOC"]],
  [WORK_DRAFT_KIND.ISSUE, ["ISSUE", "TICKET", "TASK"]],
  [WORK_DRAFT_KIND.MESSAGE, ["MESSAGE", "CHAT", "POST", "DM", "REPLY"]]
];
var BODY_KEYS = [
  "text",
  "body",
  // A Gmail reply carries its words here, and a card that missed it showed an empty box over them.
  "message_body",
  "message",
  "markdown",
  "markdown_text",
  "content",
  "comment"
];
var SUBJECT_KEYS = ["subject", "title", "summary"];
var TO_KEYS = [
  "to",
  "to_email",
  "recipient_email",
  "recipient",
  "recipients",
  "channel",
  "channel_id",
  "user",
  "users",
  "attendees",
  "cc"
];
var ADDRESS_KEYS = ["to", "to_email", "recipient_email", "recipients"];
var STARTS_KEYS = ["start_datetime", "start_time", "start", "start_date"];
var ENDS_KEYS = ["end_datetime", "end_time", "end", "end_date"];
var REPO_KEYS = ["owner", "repo"];
var NUMBER_KEYS = ["pull_number", "issue_number", "number"];
var PLACE_KEYS = [
  "issue_id",
  "issueId",
  "page_id",
  "document_id",
  "thread_id",
  "thread_ts"
];
var FIELD_TEXT_LIMIT = 300;
function workDraftOf(toolkit, tool, args, { account, toName } = {}) {
  const used = /* @__PURE__ */ new Set();
  const body = firstOf(args, BODY_KEYS, used);
  const subject = firstOf(args, SUBJECT_KEYS, used);
  const mail = MAIL_TOOLKITS.includes(toolkit);
  const toKeys = mail ? TO_KEYS.filter((key) => key !== "cc") : TO_KEYS;
  const ids = toKeys.flatMap((key) => {
    const value = textOf(args[key]);
    if (value === void 0) return [];
    used.add(key);
    return value.split(", ");
  });
  const named = !mail && toName !== void 0 && ids.length > 0;
  const to = named ? [toName] : ids;
  const where = placeOf(args, used);
  const kind = kindOf(toolkit, tool);
  const event = kind === WORK_DRAFT_KIND.EVENT;
  const starts = event ? firstOf(args, STARTS_KEYS, used) : void 0;
  const ends = event ? firstOf(args, ENDS_KEYS, used) : void 0;
  const fields = restOf(args, used);
  return {
    toolkit,
    tool,
    kind,
    ...account === void 0 ? {} : { account },
    ...to.length === 0 ? {} : { to },
    ...mail && toName !== void 0 && ids.length > 0 ? { toName } : {},
    ...mail && addressKeyOf(args) !== void 0 ? { toEditable: true } : {},
    ...where === void 0 ? {} : { where },
    ...subject === void 0 ? {} : { subject },
    ...body === void 0 ? {} : { body },
    ...starts === void 0 ? {} : { starts },
    ...ends === void 0 ? {} : { ends },
    fields
  };
}
function editedArguments(argumentsText, edited) {
  const record = argumentsRecord(argumentsText);
  if (record === null) return null;
  const key = BODY_KEYS.find((each) => textOf(record[each]) !== void 0);
  if (key === void 0 || typeof record[key] !== "string") return null;
  return JSON.stringify({ ...record, [key]: edited });
}
function editedRecipients(toolkit, argumentsText, editedTo) {
  if (!MAIL_TOOLKITS.includes(toolkit)) return null;
  const addresses = editedTo.split(",");
  if (!addresses.every(isAddress)) return null;
  const record = argumentsRecord(argumentsText);
  if (record === null) return null;
  const key = addressKeyOf(record);
  if (key === void 0) return null;
  const was = record[key];
  if (Array.isArray(was)) return JSON.stringify({ ...record, [key]: addresses });
  const several = typeof was === "string" && was.includes(",");
  if (addresses.length > 1 && !several) return null;
  return JSON.stringify({ ...record, [key]: addresses.join(", ") });
}
function recipientsOf(toolkit, tool, argumentsText, toName) {
  const extras = toName === void 0 ? {} : { toName };
  return workDraftFromText(toolkit, tool, argumentsText, extras).to ?? [];
}
function workDraftFromText(toolkit, tool, argumentsText, extras = {}) {
  return workDraftOf(toolkit, tool, argumentsRecord(argumentsText) ?? {}, extras);
}
function argumentsRecord(argumentsText) {
  let args;
  try {
    args = JSON.parse(argumentsText);
  } catch {
    return null;
  }
  if (args === null || typeof args !== "object" || Array.isArray(args)) return null;
  return args;
}
function isAddress(text) {
  return /^[^\s:,@]+@[^\s:,@]+\.[^\s:,@]+$/.test(text);
}
function addressKeyOf(args) {
  const held = ADDRESS_KEYS.filter((key) => textOf(args[key]) !== void 0);
  return held.length === 1 ? held[0] : void 0;
}
function firstOf(args, keys, used) {
  for (const key of keys) {
    const value = textOf(args[key]);
    if (value !== void 0) {
      used.add(key);
      return value;
    }
  }
  return void 0;
}
function restOf(args, used) {
  return Object.entries(args).filter(([name]) => !used.has(name)).flatMap(([name, value]) => {
    const text = textOf(value);
    return text === void 0 ? [] : [{ name, value: text.slice(0, FIELD_TEXT_LIMIT) }];
  });
}
var MAIL_TOOLKITS = ["gmail", "outlook"];
function kindOf(toolkit, tool) {
  if (MAIL_TOOLKITS.includes(toolkit)) return WORK_DRAFT_KIND.EMAIL;
  const words = tool.toUpperCase().split("_");
  for (const [kind, markers] of KIND_WORDS) {
    if (markers.some((marker) => words.includes(marker))) return kind;
  }
  return WORK_DRAFT_KIND.OTHER;
}
function placeOf(args, used) {
  const [owner, repo] = REPO_KEYS.map((key) => textOf(args[key]));
  const number = NUMBER_KEYS.map((key) => textOf(args[key])).find(
    (each) => each !== void 0
  );
  if (owner !== void 0 && repo !== void 0) {
    REPO_KEYS.forEach((key) => used.add(key));
    NUMBER_KEYS.forEach((key) => used.add(key));
    return number === void 0 ? `${owner}/${repo}` : `${owner}/${repo}#${number}`;
  }
  for (const key of PLACE_KEYS) {
    const value = textOf(args[key]);
    if (value !== void 0) {
      used.add(key);
      return value;
    }
  }
  return void 0;
}
function textOf(value) {
  if (typeof value === "string") return value.trim() === "" ? void 0 : value;
  if (typeof value === "number" || typeof value === "boolean") return String(value);
  if (Array.isArray(value)) {
    const parts = value.flatMap((each) => {
      const text = textOf(each);
      return text === void 0 ? [] : [text];
    });
    return parts.length === 0 ? void 0 : parts.join(", ");
  }
  if (value !== null && typeof value === "object") return JSON.stringify(value);
  return void 0;
}

// src/daemon/files.ts
var ENTRY_KIND = {
  FOLDER: "folder",
  FILE: "file"
};

// src/daemon/proposing.ts
var PROPOSING_METHODS = [
  HOME_METHOD.HAND_OVER,
  SPOKEN_RULE_METHOD.RULE,
  MCP_HUB_METHOD.SERVER_PUT,
  MCP_HUB_METHOD.ASSIGN,
  POLICY_METHOD.RULE_PROPOSE,
  POLICY_METHOD.RULE_REMOVE,
  POLICY_METHOD.RULE_PACK_IMPORT,
  AGENTS_METHOD.AGENT_RESUME,
  AGENTS_METHOD.AGENT_LAUNCH,
  SKILLS_METHOD.SKILL_IMPORT,
  SKILLS_METHOD.SKILL_PUT,
  SKILLS_METHOD.SKILL_ASSIGN,
  SKILLS_METHOD.SKILL_ACCEPT,
  SKILLS_METHOD.SKILL_ROLLBACK,
  PROJECTS_METHOD.PROJECT_OPEN,
  PROJECTS_METHOD.PROJECT_APPLY,
  BACKUP_METHOD.BACKUP_RESTORE,
  MEMORY_METHOD.MEMORY_CONFIRM,
  LAN_METHOD.LAN_SET,
  PERSONAL_SYNC_METHOD.PERSONAL_SYNC_KEY_OFFER,
  PERSONAL_SYNC_METHOD.PERSONAL_SYNC_KEY_ACCEPT,
  PROFILES_METHOD.PROFILE_APPLY,
  INDEX_METHOD.INDEX_INSTALL,
  INDEX_METHOD.INDEX_SOURCE_SET
];

export {
  INDEX_METHOD,
  INDEX_SOURCE,
  INDEX_KIND,
  MEMORY_LAYERS_METHOD,
  MEMORY_LAYER,
  MEMORY_METHOD,
  EXTRACTOR_STATE,
  MEMORY_SEARCH_MODE,
  ACTIVITY_METHOD,
  ACTIVITY_KIND,
  ANSWERED_HOW,
  MOST_LIVE_ACTIVITY_ROWS,
  HOME_METHOD,
  INTERCEPT_METHOD,
  FAST_INTERCEPT_VERSION,
  INTERCEPT_PLAN,
  encodeInterceptLine,
  isInterceptMethod,
  MCP_HUB_METHOD,
  MCP_HEALTH,
  MCP_SCOPE,
  POLICY_METHOD,
  RULE_SOURCE,
  AGENTS_METHOD,
  AGENT_STATUS,
  AGENT_SEAM,
  SKILLS_METHOD,
  PROJECTS_METHOD,
  PROJECT_SCOPE,
  BACKUP_METHOD,
  LAN_METHOD,
  PERSONAL_SYNC_METHOD,
  PERSONAL_SYNC_STATE,
  SYNC_KEEP,
  PROFILES_METHOD,
  WORK_METHOD,
  HANDOFF_ANSWER_WORD,
  REMOTE_METHOD,
  REMOTE_OUTCOME,
  PAIRING_STATE,
  pairMessage,
  grantMessage,
  driveMessage,
  followUpMessage,
  FOLLOW_UP_OUTCOME,
  deviceProofMessage,
  SPEECH_METHOD,
  SPOKEN_RULE_METHOD,
  RULE_DRAFTED_BY,
  DISPLAY,
  DISPLAY_VIA,
  TERMINAL_KEY,
  MOST_PRESSED_KEYS,
  terminalKeys,
  SPEAKER,
  DAEMON_METHOD,
  BRIEFING,
  ASK_ENDS,
  DAEMON_EVENT,
  encode,
  HOLD_ANSWER,
  HOLD_ANSWER_LABEL,
  HOLD_ANSWER_ORDER,
  HOLD_OUTCOME_WORD,
  ALWAYS_ALLOW_LABEL,
  ALWAYS_DENY_LABEL,
  PROPOSAL_ANSWER,
  confirmationMessage,
  actionConfirmationMessage,
  REMOTE_CAPABILITY,
  DELIVERY,
  wentIn,
  ASK_INTENT,
  RULE_SCOPE,
  DRAFT_MODE,
  MAIL_SERVICE,
  WORK_ACCOUNT_CHECK,
  WORK_DRAFT_KIND,
  workDraftOf,
  editedArguments,
  editedRecipients,
  recipientsOf,
  workDraftFromText,
  isAddress,
  ENTRY_KIND,
  PROPOSING_METHODS
};
