import Foundation

// Projects on the wire, mirrored from the runtime's daemon/projects.ts: one repository, the agents seen in it, and the
// servers, skills, rules and instructions each agent opened there is given.

/// A server or skill the project names, and the agents here that already have it.
public struct ProjectGrantView: Decodable, Equatable, Sendable {
    public let name: String
    /// In the hub on this machine; a name the hub lacks is given to nobody.
    public let inHub: Bool
    /// Of the project's agents, those that have it now.
    public let agents: [String]

    public init(name: String, inHub: Bool, agents: [String]) {
        self.name = name
        self.inHub = inHub
        self.agents = agents
    }
}

public struct ProjectRulesView: Decodable, Equatable, Sendable {
    /// Relative to the repository, as the manifest names it.
    public let file: String?
    public let count: Int
    /// In the registry every seam loads.
    public let inForce: Bool
    /// Why the file would not load, when it would not.
    public let problem: String?

    public init(file: String? = nil, count: Int, inForce: Bool, problem: String? = nil) {
        self.file = file
        self.count = count
        self.inForce = inForce
        self.problem = problem
    }
}

/// One file an agent reads instructions from: a source the project imports, a file Memnox writes into, or both.
public struct ProjectInstructionView: Decodable, Equatable, Sendable {
    public let path: String
    /// The project reads it as its instructions.
    public let source: Bool
    public let present: Bool
    /// The agents that read this file.
    public let agents: [String]
    /// Holds a block or file of Memnox's own just now.
    public let written: Bool

    public init(path: String, source: Bool, present: Bool, agents: [String], written: Bool) {
        self.path = path
        self.source = source
        self.present = present
        self.agents = agents
        self.written = written
    }
}

public struct ProjectMissionView: Decodable, Equatable, Sendable {
    public let id: String
    public let statement: String
    public let startedAt: String

    public init(id: String, statement: String, startedAt: String) {
        self.id = id
        self.statement = statement
        self.startedAt = startedAt
    }
}

public struct ProjectSessionsView: Decodable, Equatable, Sendable {
    public let total: Int
    public let ended: Int

    public init(total: Int, ended: Int) {
        self.total = total
        self.ended = ended
    }
}

/// Where a project's setup comes from; absent is this machine's own.
public enum ProjectScope: String, Sendable {
    /// Shared by the organization in Memnox Cloud and laid over the clone, read only here.
    case organization
}

/// What the organization hands a shared project, its names looked up in the same bundle.
public struct ProjectOrganizationView: Decodable, Equatable, Sendable {
    /// The cloud's id, which the project's memory is kept under.
    public let id: String
    public let name: String
    /// `host/owner/name`, which this clone's `origin` reduces to.
    public let repository: String
    public let description: String?
    public let servers: [String]
    public let skills: [String]
    public let rulePack: String?
    /// Rules the organization publishes under the rule pack.
    public let rules: Int
    public let memory: String
    /// Each name the bundle did not carry, said in a sentence, and left out.
    public let skipped: [String]
    /// The line a local edit is refused with, for a screen to show before anybody tries.
    public let editedIn: String

    public init(id: String, name: String, repository: String, description: String? = nil, servers: [String] = [],
                skills: [String] = [], rulePack: String? = nil, rules: Int = 0, memory: String, skipped: [String] = [],
                editedIn: String) {
        self.id = id
        self.name = name
        self.repository = repository
        self.description = description
        self.servers = servers
        self.skills = skills
        self.rulePack = rulePack
        self.rules = rules
        self.memory = memory
        self.skipped = skipped
        self.editedIn = editedIn
    }
}

public struct ProjectView: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    /// `organization` where Memnox Cloud shares this repository with the person; nil is their own.
    public let scope: String?
    /// On an organization project: what it hands, read only.
    public let organization: ProjectOrganizationView?
    public let name: String
    public let path: String
    /// Has a committed `.memnox/project.toml`; otherwise what is shown is found rather than declared.
    public let declared: Bool
    /// Why the committed manifest would not read, when it would not.
    public let problems: [String]?
    /// Opened on this machine, which is when its instructions and grants are applied.
    public let opened: Bool
    /// The agents the manifest names, or every agent seen in it when it names none.
    public let agents: [String]
    /// Agents that ran a session here, by kind.
    public let agentsSeen: [String]
    public let sessions: ProjectSessionsView
    public let servers: [ProjectGrantView]
    public let skills: [ProjectGrantView]
    public let rules: ProjectRulesView
    public let instructions: [ProjectInstructionView]
    public let memoryScope: String
    public let openMissions: [ProjectMissionView]
    public let openQuestions: Int
    public let lastActive: String?
    public let appliedAt: String?

    public init(id: String, name: String, path: String, declared: Bool, problems: [String]? = nil, opened: Bool,
                agents: [String], agentsSeen: [String], sessions: ProjectSessionsView, servers: [ProjectGrantView],
                skills: [ProjectGrantView], rules: ProjectRulesView, instructions: [ProjectInstructionView],
                memoryScope: String, openMissions: [ProjectMissionView], openQuestions: Int,
                lastActive: String? = nil, appliedAt: String? = nil, scope: ProjectScope? = nil,
                organization: ProjectOrganizationView? = nil) {
        self.id = id
        self.scope = scope?.rawValue
        self.organization = organization
        self.name = name
        self.path = path
        self.declared = declared
        self.problems = problems
        self.opened = opened
        self.agents = agents
        self.agentsSeen = agentsSeen
        self.sessions = sessions
        self.servers = servers
        self.skills = skills
        self.rules = rules
        self.instructions = instructions
        self.memoryScope = memoryScope
        self.openMissions = openMissions
        self.openQuestions = openQuestions
        self.lastActive = lastActive
        self.appliedAt = appliedAt
    }

    /// What the organization hands it, or nil for the person's own, which is the only kind edited here.
    public var sharedBy: ProjectOrganizationView? {
        scope == ProjectScope.organization.rawValue ? organization : nil
    }
}

public struct ProjectsView: Decodable, Equatable, Sendable {
    public let projects: [ProjectView]
}

/// What applying did at once, and what it proposed for the person to sign.
public struct ProjectApplySummary: Decodable, Equatable, Sendable {
    /// Instruction files written or rewritten, relative to the repository.
    public let written: [String]
    /// Instruction files of ours taken out, since nothing was left to put in them.
    public let removed: [String]
    /// Files a person wrote in the way of one of ours, which were left alone.
    public let kept: [String]
    /// The repository's own servers put behind the proxy for Claude Code, which governs and never widens.
    public let governed: [String]
    /// Names the manifest gives that the hub on this machine does not have.
    public let missing: [String]

    public init(written: [String] = [], removed: [String] = [], kept: [String] = [], governed: [String] = [], missing: [String] = []) {
        self.written = written
        self.removed = removed
        self.kept = kept
        self.governed = governed
        self.missing = missing
    }
}

/// A project as a form fills it in, sent as `projectDraft`; every list left out is empty.
public struct ProjectDraft: Encodable, Equatable, Sendable {
    public let name: String
    public let instructions: [String]?
    public let servers: [String]?
    public let skills: [String]?
    public let agents: [String]?
    public let policy: String?
    public let memory: String?

    public init(name: String, instructions: [String]? = nil, servers: [String]? = nil, skills: [String]? = nil,
                agents: [String]? = nil, policy: String? = nil, memory: String? = nil) {
        self.name = name
        self.instructions = instructions
        self.servers = servers
        self.skills = skills
        self.agents = agents
        self.policy = policy
        self.memory = memory
    }
}
