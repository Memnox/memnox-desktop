import Foundation

// Agent profiles and agent work as Memnox Cloud sends them, field for field from memnox-cloud's
// src/agent-profiles and src/agent-work, for agents hosted elsewhere that no daemon here reaches.

/// A job as the workspace keeps it.
public struct CloudProfile: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let purpose: String?
    public let role: String?
    public let responsibilities: [String]?
    public let responsiblePersonId: String?
    public let projects: [String]?
    public let templateOf: String?
}

/// One way the workspace reaches a profile's agent, and how sure it is through it.
public struct CloudProfileConnection: Decodable, Equatable, Sendable {
    public let machineId: String
    public let connection: String?
    public let label: String?
    public let live: Bool
    /// By capability, with enforcement as one level rather than by seam.
    public let levels: [String: String]
}

/// A profile as the person reads it, with what the workspace derived about it.
public struct CloudProfileView: Decodable, Equatable, Sendable {
    public let profile: CloudProfile
    /// The responsible person left or was never one, so an admin must reassign it.
    public let needsResponsiblePerson: Bool?
    /// The responsible person's display name, sent beside the profile by a cloud that knows it; absent from an older one.
    public let responsiblePersonName: String?
    public let connected: Bool?
    public let connections: [CloudProfileConnection]?
    public let levels: [String: String]?
}

public struct CloudProfiles: Decodable, Equatable, Sendable {
    public let profiles: [CloudProfileView]
}

public struct CloudWork: Decodable, Equatable, Sendable {
    public let id: String
    public let agentProfileId: String
    public let responsiblePersonId: String
    public let target: ExternalTaskRef
    public let status: String
    public let createdAt: String
    public let updatedAt: String
}

public struct CloudHandoff: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let workId: String
    public let fromProfileId: String
    public let toProfileId: String?
    public let toPersonId: String?
    public let reason: String
    public let state: String
    public let requestedAt: String
}

/// What `GET :ws/me/agent-work` answers: the work the person answers for and the handoffs waiting on them.
public struct CloudMyWork: Decodable, Equatable, Sendable {
    public let work: [CloudWork]
    public let handoffs: [CloudHandoff]
}

/// The workspace's shapes read into the ones every screen here already draws, so a hosted agent wears the same card,
/// pills and words as one on this Mac. Every level is the cloud's; nothing is worked out here.
public enum WorkspaceAgentsLines {
    /// The cloud states enforcement as one level, so it stands as a single seam of its own.
    public static let everySeam = "everything"

    public static func levels(_ cloud: [String: String]?) -> CapabilityLevels {
        guard let cloud else { return .outside }
        func level(_ key: String) -> CapabilityLevel { cloud[key].flatMap(CapabilityLevel.init(rawValue:)) ?? .noEvidence }
        return CapabilityLevels(context: level("context"), instructions: level("instructions"), tools: level("tools"),
                                activity: level("activity"), coordination: level("coordination"), approval: level("approval"),
                                enforcement: [everySeam: level("enforcement")])
    }

    /// The profile as a card draws it; the responsible person reads as you when it is the person signed in.
    public static func profileView(_ cloud: CloudProfileView, you: String?) -> ProfileView {
        let profile = cloud.profile
        let responsible = cloud.needsResponsiblePerson == true ? nil
            : responsibleName(id: profile.responsiblePersonId, name: cloud.responsiblePersonName, you: you)
        let connections = (cloud.connections ?? []).map { each in
            AgentConnection(id: "\(each.machineId)/\(each.connection ?? "")", profileId: profile.id, kind: each.connection ?? "observed",
                            agentKind: each.label, mediation: "", firstSeen: "", lastSeen: "", status: each.live ? "live" : "idle",
                            levels: levels(each.levels))
        }
        return ProfileView(id: profile.id, name: profile.name, updatedAt: "", purpose: profile.purpose, role: profile.role,
                           responsibilities: profile.responsibilities ?? [], responsiblePerson: responsible,
                           projects: profile.projects ?? [], templateOf: profile.templateOf, connections: connections,
                           levels: levels(cloud.levels))
    }

    /// Who answers for a job, as a card says it: you when it is the person signed in, else the name the cloud sent,
    /// else a teammate, so a person id never reaches the screen.
    public static func responsibleName(id: String?, name: String?, you: String?) -> String? {
        guard let id, !id.isEmpty else { return nil }
        if id == you { return "you" }
        return AgentWorkLines.filled(name) ?? "a teammate"
    }

    /// A piece of the workspace's work as the work lines read it, its waiting handoffs with it; the person who answers
    /// for it is named from the profiles the workspace sent, never by their id.
    public static func work(_ cloud: CloudWork, handoffs: [CloudHandoff], you: String? = nil, profiles: [CloudProfileView] = []) -> AgentWork {
        let named = profiles.first { $0.profile.responsiblePersonId == cloud.responsiblePersonId }?.responsiblePersonName
        let waiting = handoffs.filter { $0.workId == cloud.id }.map { each in
            WorkHandoff(id: each.id, from: HandoffParty(profileId: each.fromProfileId),
                        to: HandoffParty(profileId: each.toProfileId, person: responsibleName(id: each.toPersonId, name: nil, you: you)),
                        reason: each.reason,
                        state: each.state, requestedAt: each.requestedAt)
        }
        return AgentWork(id: cloud.id, profileId: cloud.agentProfileId,
                         responsiblePerson: responsibleName(id: cloud.responsiblePersonId, name: named, you: you) ?? "",
                         target: cloud.target, status: cloud.status, handoffs: waiting, createdAt: cloud.createdAt,
                         updatedAt: cloud.updatedAt)
    }
}
