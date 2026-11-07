import Foundation

// Personal sync on the wire, mirrored from the runtime's daemon/personal-sync.ts: one person's servers, skills,
// projects, rules and verified memory carried blind across their own machines, the key moved only behind a fingerprint
// signed on the island.

/// Where personal sync stands on this Mac.
public enum PersonalSyncState: String, Sendable {
    /// Not on Memnox Cloud, so there is nowhere to carry anything.
    case off
    /// No sync key here yet: another of the person's machines has to seal it to this one.
    case waitingForKey = "waiting-for-key"
    /// A key sealed to this Mac arrived and waits for the person to compare and accept it.
    case keyArrived = "key-arrived"
    case ready
    /// The plan does not carry personal sync; what is here stays here.
    case notOnPlan = "not-on-plan"
    /// The credential speaks for no person, so it has nothing of its own to sync.
    case noPerson = "no-person"
}

/// Which side of a conflict to keep.
public enum SyncKeep: String, Sendable {
    /// The copy the cloud kept, put back here and sent as the newest.
    case theirs
    /// What this Mac holds now; the kept copy is let go.
    case mine
}

/// One of the person's machines, as far as the sync key goes.
public struct PersonalSyncMachine: Decodable, Equatable, Sendable {
    public let machineId: String
    /// Compared with what the other machine shows before the key moves either way.
    public let fingerprint: String
    /// Another of the person's machines already sealed the key to it.
    public let sealed: Bool

    public init(machineId: String, fingerprint: String, sealed: Bool = false) {
        self.machineId = machineId
        self.fingerprint = fingerprint
        self.sealed = sealed
    }
}

/// How many items of one kind this Mac carries.
public struct PersonalSyncKindCount: Decodable, Equatable, Sendable {
    public let kind: String
    public let items: Int

    public init(kind: String, items: Int) {
        self.kind = kind
        self.items = items
    }
}

public struct PersonalSyncStatus: Decodable, Equatable, Sendable {
    /// Kept as written, so a state this app does not know yet still decodes.
    public let state: String
    /// Where it stands, in one sentence a screen shows as it is.
    public let said: String
    /// Which sync key this Mac holds, never the key.
    public let keyId: String?
    public let lastSyncedAt: String?
    public let kinds: [PersonalSyncKindCount]
    public let conflicts: Int
    /// Items left out of the last run, each said.
    public let skipped: [String]
    /// Repositories opened on the person's other machines and not here.
    public let openedElsewhere: [String]
    /// On a machine holding the key: the person's machines still waiting for it.
    public let waiting: [PersonalSyncMachine]
    /// On a machine waiting: the fingerprint of the key that arrived, to compare before accepting it.
    public let arrivedFingerprint: String?

    public var syncState: PersonalSyncState? { PersonalSyncState(rawValue: state) }

    public init(state: PersonalSyncState, said: String, keyId: String? = nil, lastSyncedAt: String? = nil,
                kinds: [PersonalSyncKindCount] = [], conflicts: Int = 0, skipped: [String] = [],
                openedElsewhere: [String] = [], waiting: [PersonalSyncMachine] = [], arrivedFingerprint: String? = nil) {
        self.state = state.rawValue
        self.said = said
        self.keyId = keyId
        self.lastSyncedAt = lastSyncedAt
        self.kinds = kinds
        self.conflicts = conflicts
        self.skipped = skipped
        self.openedElsewhere = openedElsewhere
        self.waiting = waiting
        self.arrivedFingerprint = arrivedFingerprint
    }
}

/// A conflict copy opened here, beside what this Mac holds of the same item now.
public struct PersonalSyncConflict: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: String
    public let name: String
    /// Which machine wrote the copy that lost.
    public let writtenBy: String
    public let keptAt: String
    /// The copy, as text a screen shows.
    public let theirs: String
    /// What this Mac holds now, nil where it holds nothing by that name.
    public let mine: String?

    public init(id: String, kind: String, name: String, writtenBy: String, keptAt: String, theirs: String, mine: String? = nil) {
        self.id = id
        self.kind = kind
        self.name = name
        self.writtenBy = writtenBy
        self.keptAt = keptAt
        self.theirs = theirs
        self.mine = mine
    }
}
