import Foundation

// The person inbox as memnox-cloud/docs/person-inbox.md names it, field for field.

/// What the workspace calls a device when it introduces itself.
public enum PersonDeviceKind {
    public static let desktop = "desktop"
}

/// The code a person approves in the console, and how often to ask whether they have.
public struct PersonCode: Decodable, Equatable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let intervalSeconds: Double
    /// Epoch milliseconds, as the cloud sends it.
    public let expiresAt: Double
    public let verificationUri: String?
    public let verificationUriComplete: String?

    public init(deviceCode: String, userCode: String, intervalSeconds: Double, expiresAt: Double,
                verificationUri: String? = nil, verificationUriComplete: String? = nil) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.intervalSeconds = intervalSeconds
        self.expiresAt = expiresAt
        self.verificationUri = verificationUri
        self.verificationUriComplete = verificationUriComplete
    }

    public var expiry: Date { Date(timeIntervalSince1970: expiresAt / Self.millisecondsPerSecond) }

    /// The page to open, the one that already carries the code when the cloud gave it; nil where no console is configured.
    public var page: URL? {
        (verificationUriComplete ?? verificationUri).flatMap(URL.init(string:))
    }

    private static let millisecondsPerSecond: Double = 1_000
}

/// The credential the console granted once the person approved the code.
public struct PersonToken: Decodable, Equatable, Sendable {
    public let token: String
    public let tokenId: String
    /// The member held calls are routed to.
    public let personId: String
    public let name: String
    public let role: String
    public let orgId: String
}

/// This Mac as the workspace registered it, whose id every answer names.
public struct RegisteredDevice: Decodable, Equatable, Sendable {
    public let id: String
    public let name: String?
    public let kind: String?
}

/// One workspace the person reaches, as `GET /v1/me` lists it.
public struct WorkspaceRef: Decodable, Equatable, Sendable {
    public let id: String
    public let orgId: String?
}

/// The part of `GET /v1/me` this app reads: the workspaces whose inboxes it polls.
public struct PersonView: Decodable, Equatable, Sendable {
    public let workspaces: [WorkspaceRef]
}

/// A held call a teammate's agent raised that the workspace routed to this person. With `include=recent` the
/// inbox also lists calls settled a moment ago, with who answered and where; any field may be missing but the id.
public struct WorkspaceHeldCall: Decodable, Equatable, Sendable {
    public let id: String
    public let machineId: String
    public let machineLabel: String?
    public let machineClass: String
    public let agent: String
    public let operation: String
    public let target: String?
    public let summary: String?
    public let why: String?
    public let reason: String
    public let askedAt: String
    public let expiresAt: String
    public let escalated: Bool
    public let approvalsNeeded: Int
    public let approvedByYou: Bool
    /// Whose team the call came from, by the teammate's name; read where the workspace sends it.
    public let ownerName: String?
    /// On a settled call: the answer that settled it, who gave it and on what.
    public let answer: String?
    public let answeredBy: String?
    public let answeredOn: String?

    private enum Field: String, CodingKey {
        case id, machineId, machineLabel, machineClass, agent, operation, target, summary, why, reason, askedAt,
             expiresAt, escalated, approvalsNeeded, approvedByYou, ownerName, answer, answeredBy, answeredOn
    }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: Field.self)
        id = try fields.decode(String.self, forKey: .id)
        machineId = (try? fields.decodeIfPresent(String.self, forKey: .machineId)) ?? ""
        machineLabel = try? fields.decodeIfPresent(String.self, forKey: .machineLabel)
        machineClass = (try? fields.decodeIfPresent(String.self, forKey: .machineClass)) ?? Self.workstation
        agent = (try? fields.decodeIfPresent(String.self, forKey: .agent)) ?? ""
        operation = (try? fields.decodeIfPresent(String.self, forKey: .operation)) ?? ""
        target = try? fields.decodeIfPresent(String.self, forKey: .target)
        summary = try? fields.decodeIfPresent(String.self, forKey: .summary)
        why = try? fields.decodeIfPresent(String.self, forKey: .why)
        reason = (try? fields.decodeIfPresent(String.self, forKey: .reason)) ?? ""
        askedAt = (try? fields.decodeIfPresent(String.self, forKey: .askedAt)) ?? ""
        expiresAt = (try? fields.decodeIfPresent(String.self, forKey: .expiresAt)) ?? ""
        escalated = (try? fields.decodeIfPresent(Bool.self, forKey: .escalated)) ?? false
        approvalsNeeded = (try? fields.decodeIfPresent(Int.self, forKey: .approvalsNeeded)) ?? 1
        approvedByYou = (try? fields.decodeIfPresent(Bool.self, forKey: .approvedByYou)) ?? false
        ownerName = try? fields.decodeIfPresent(String.self, forKey: .ownerName)
        answer = try? fields.decodeIfPresent(String.self, forKey: .answer)
        answeredBy = try? fields.decodeIfPresent(String.self, forKey: .answeredBy)
        answeredOn = try? fields.decodeIfPresent(String.self, forKey: .answeredOn)
    }

    /// The class the contract reads a machine nobody can find as.
    private static let workstation = "workstation"

    /// The teammate's machine, by the name it was given, else its id.
    public var place: CallPlace {
        .team(machine: CallLabel.trimmed(machineLabel) ?? machineId, person: ownerName)
    }

    /// "codex on build-box, from Ana's team", so the person sees whose machine waits and that it came through the workspace.
    public var who: String {
        CallLabel.label(agent, at: place)
    }

    /// Settled already, listed only so the card can say who answered it before it leaves.
    public var isSettled: Bool {
        answer != nil || answeredBy != nil || answeredOn != nil
    }

    /// "Allowed once by Ana in the console", from whatever the workspace reported.
    public var settledLine: String {
        SettledLine.line(answer: answer, by: answeredBy, on: answeredOn)
    }

    /// What it wants, in the cloud's own words where it gave some, else the operation and its target.
    public var what: String {
        if let summary, !summary.isEmpty { return summary }
        return [operation, target].compactMap { $0 }.joined(separator: " ")
    }

    /// Why it is held: the rule's own sentence where there is one, else the reason the policy gave.
    public var whyHeld: String {
        if let why, !why.isEmpty { return why }
        return reason
    }

    /// When the machine stops waiting, nil when the cloud sent a date this app cannot read.
    public var expiry: Date? { WorkspaceDates.read(expiresAt) }
}

/// What an answer from the inbox did.
public struct InboxAnswerReply: Decodable, Equatable, Sendable {
    public let id: String
    /// `answered` went back to the machine; `counted` waits on more yeses.
    public let status: String
    public let answer: String?
    public let approvalsNeeded: Int

    public static let counted = "counted"
}

/// What the Keychain keeps for the signed in person: the credential, where to poll and the device answers name.
public struct WorkspaceCredential: Codable, Equatable, Sendable {
    public let token: String
    public let tokenId: String
    public let personId: String
    public let name: String
    public let orgId: String
    public let workspaces: [String]
    public let deviceId: String

    public init(token: String, tokenId: String, personId: String, name: String, orgId: String, workspaces: [String], deviceId: String) {
        self.token = token
        self.tokenId = tokenId
        self.personId = personId
        self.name = name
        self.orgId = orgId
        self.workspaces = workspaces
        self.deviceId = deviceId
    }
}

/// The cloud writes ISO 8601 with milliseconds; one without is read as well rather than dropped.
enum WorkspaceDates {
    static func read(_ text: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
