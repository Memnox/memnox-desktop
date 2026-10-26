import Foundation

// The Skills Hub on the wire, mirrored from the runtime's daemon/skills-hub.ts: skills kept once, written into each
// agent's own format, and held when their folder no longer matches what somebody accepted.

/// Where a skill lives, as the runtime's SKILL_SCOPE names it.
public enum SkillScope: String, CaseIterable, Sendable {
    case personal
    case project
}

/// Why a skill is held, as the runtime's SkillHold names its standing.
public enum SkillStanding: String, CaseIterable, Sendable {
    /// Its folder changed since it was accepted.
    case changed
    /// Its folder reaches further than the accepted version did.
    case widened
    /// Nobody has accepted its folder yet.
    case new
}

/// What one agent keeps of a skill once it is written in that agent's format.
public struct SkillCompatibility: Decodable, Equatable, Sendable {
    public let agent: String
    public let label: String
    public let supported: Bool
    /// What the agent's format cannot carry, in a sentence each; empty when nothing is lost.
    public let loses: [String]

    public init(agent: String, label: String, supported: Bool, loses: [String]) {
        self.agent = agent
        self.label = label
        self.supported = supported
        self.loses = loses
    }
}

public struct SkillVersionView: Decodable, Equatable, Sendable {
    public let version: String
    public let current: Bool
    /// When somebody accepted it; absent for a version never accepted.
    public let acceptedAt: String?
    public let digest: String?
}

/// Why a skill is held, and what accepting it asks for.
public struct SkillHold: Decodable, Equatable, Sendable {
    public let standing: String
    /// Tools and commands it reaches now that the accepted version did not.
    public let gained: [String]
    /// Accepting it needs the person's signature.
    public let signed: Bool

    public init(standing: SkillStanding, gained: [String], signed: Bool) {
        self.standing = standing.rawValue
        self.gained = gained
        self.signed = signed
    }

    /// The standing as a known case, or nil for one this app does not know yet.
    public var skillStanding: SkillStanding? { SkillStanding(rawValue: standing) }
}

public struct SkillAssignmentView: Decodable, Equatable, Sendable {
    public let agent: String
    /// A repository it is written into; absent is the home folder.
    public let project: String?
}

public struct SkillPermissionsView: Decodable, Equatable, Sendable {
    public let filesystem: [String]
    public let network: [String]
    public let commands: [String]
}

public struct SkillView: Decodable, Equatable, Identifiable, Sendable {
    public let name: String
    public let scope: String
    public let project: String?
    public let category: String?
    public let version: String
    public let description: String
    public let publisher: String?
    public let enabled: Bool
    /// The folder digest as it is now.
    public let digest: String
    /// Present only while it is held, and then nothing new of it is handed out.
    public let held: SkillHold?
    /// Each agent it is given to, once.
    public let agents: [String]
    public let assignments: [SkillAssignmentView]
    public let compatibility: [SkillCompatibility]
    /// Oldest first.
    public let versions: [SkillVersionView]
    public let updatedAt: String
    /// Every file beside the instructions, by path.
    public let files: [String]
    public let instructions: String
    public let tools: [String]
    public let mcpServers: [String]
    public let permissions: SkillPermissionsView
    public let dependencies: [String]
    /// Why its folder would not read, when it would not.
    public let problems: [String]?

    public var id: String { name }
    public var skillScope: SkillScope? { SkillScope(rawValue: scope) }
}

/// A skill or persona found in an agent's own folder, offered for import.
public struct FoundSkillView: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let agent: String
    /// skill or agent.
    public let kind: String
    public let path: String
    public let tools: [String]
    /// Its grant in words, as `memnox skills` says it.
    public let grant: String
    /// Already in the hub under this name.
    public let imported: Bool

    public init(id: String, name: String, agent: String, kind: String, path: String, tools: [String], grant: String, imported: Bool) {
        self.id = id
        self.name = name
        self.agent = agent
        self.kind = kind
        self.path = path
        self.tools = tools
        self.grant = grant
        self.imported = imported
    }
}

/// An agent a skill can be written into, and whether it is installed here.
public struct SkillAgentView: Decodable, Equatable, Sendable {
    public let agent: String
    public let label: String
    public let installed: Bool
}

public struct SkillsHubView: Decodable, Equatable, Sendable {
    public let skills: [SkillView]
    public let found: [FoundSkillView]
    public let agents: [SkillAgentView]
}

/// One skill wanted somewhere and not written, with why.
public struct SkillSkip: Decodable, Equatable, Sendable {
    public let skill: String
    public let agent: String
    public let path: String
    public let reason: String

    public init(skill: String, agent: String, path: String, reason: String) {
        self.skill = skill
        self.agent = agent
        self.path = path
        self.reason = reason
    }
}

/// What a sync changed, so a screen says it in a line.
public struct SkillsSyncSummary: Decodable, Equatable, Sendable {
    public let written: Int
    public let removed: Int
    public let files: [String]
    public let skipped: [SkillSkip]

    public init(written: Int, removed: Int, files: [String] = [], skipped: [SkillSkip] = []) {
        self.written = written
        self.removed = removed
        self.files = files
        self.skipped = skipped
    }
}

/// The part of a skill's reach a draft names; a list left out is empty.
public struct SkillDraftPermissions: Codable, Equatable, Sendable {
    public let filesystem: [String]?
    public let network: [String]?
    public let commands: [String]?

    public init(filesystem: [String]? = nil, network: [String]? = nil, commands: [String]? = nil) {
        self.filesystem = filesystem
        self.network = network
        self.commands = commands
    }
}

/// A text file beside a skill's instructions, by its path inside the skill.
public struct SkillDraftFile: Codable, Equatable, Sendable {
    public let path: String
    public let text: String

    public init(path: String, text: String) {
        self.path = path
        self.text = text
    }
}

/// A skill as a form fills it in, sent as `skillDraft`; every list left out is empty. A calibration from the runtime
/// carries every field, so accepting it sends the skill whole rather than dropping its files.
public struct SkillDraft: Codable, Equatable, Sendable {
    public let name: String
    public let version: String
    public let description: String
    public let category: String?
    public let publisher: String?
    public let instructions: String
    public let files: [SkillDraftFile]?
    public let tools: [String]?
    public let mcpServers: [String]?
    public let dependencies: [String]?
    public let agents: [String]?
    public let permissions: SkillDraftPermissions?

    public init(name: String, version: String, description: String, category: String? = nil, publisher: String? = nil,
                instructions: String, files: [SkillDraftFile]? = nil, tools: [String]? = nil, mcpServers: [String]? = nil,
                dependencies: [String]? = nil, agents: [String]? = nil, permissions: SkillDraftPermissions? = nil) {
        self.name = name
        self.version = version
        self.description = description
        self.category = category
        self.publisher = publisher
        self.instructions = instructions
        self.files = files
        self.tools = tools
        self.mcpServers = mcpServers
        self.dependencies = dependencies
        self.agents = agents
        self.permissions = permissions
    }
}

/// One skill's use over the chats lately, as the runtime read it from the transcripts it already reads.
public struct SkillStatsView: Decodable, Equatable, Identifiable, Sendable {
    public let name: String
    public let uses: Int
    /// Tool calls inside the skill's turn that ended in an error.
    public let failures: Int
    /// Tool calls inside the skill's turn that a permission or a rule refused.
    public let refusals: Int
    public let lastUsedAt: String?
    /// The fix backlog, oldest first.
    public let notes: [String]
    /// The first line of a few recent failures, newest first.
    public let recentFailures: [String]

    public var id: String { name }

    public init(name: String, uses: Int, failures: Int, refusals: Int, lastUsedAt: String? = nil, notes: [String] = [],
                recentFailures: [String] = []) {
        self.name = name
        self.uses = uses
        self.failures = failures
        self.refusals = refusals
        self.lastUsedAt = lastUsedAt
        self.notes = notes
        self.recentFailures = recentFailures
    }
}

/// A suggested change to one skill, built by the runtime from its backlog and failures; accepted through skill-put.
public struct SkillCalibration: Decodable, Equatable, Sendable {
    public let name: String
    public let section: String
    public let before: [String]
    public let after: [String]
    public let draft: SkillDraft
    public let notes: Int
    public let failures: Int

    public init(name: String, section: String, before: [String], after: [String], draft: SkillDraft, notes: Int, failures: Int) {
        self.name = name
        self.section = section
        self.before = before
        self.after = after
        self.draft = draft
        self.notes = notes
        self.failures = failures
    }
}
