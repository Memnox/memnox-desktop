import Foundation

// What lights the brain. **Every pulse answers something that happened**: a fact the runtime now holds differently, a
// fact learned since the last look, or a source read again or newly kept, each seen by comparing what the runtime said
// with what it said before; and a slow bead from a conversation into the core while it is working. A filter that
// merely shows other facts is not news, so it lights nothing. Pulses are kept rare: one wave at a time, a calm gap
// between them, and what arrives in the gap waits for it rather than piling up.

/// Something on the record that changed, and the nodes that stand for it, the first one drawn being where it starts.
public struct BrainStir: Equatable, Sendable {
    public let nodes: [String]
    public let kind: MemoryMapNodeKind

    public init(nodes: [String], kind: MemoryMapNodeKind) {
        self.nodes = nodes
        self.kind = kind
    }
}

/// Remembers what the runtime last said about each fact and source, so the next answer says what changed.
public struct BrainWitness: Equatable, Sendable {
    private var facts: [String: String] = [:]
    private var sources: [String: String] = [:]
    /// When the first look was taken: a fact made after it is news, and an older one a filter shows is not.
    private var since: Date?
    private var seenSources = false
    /// The unit separator, which no statement or time carries, between the parts of what is compared.
    private static let between = "\u{1F}"

    public init() {}

    /// What changed since the last look, told the time of this one; the first look only remembers.
    public mutating func observe(items: [MemoryItemView], sources listed: [MemorySourceView], at now: Date) -> [BrainStir] {
        var stirs: [BrainStir] = []
        for item in items {
            let mark = Self.signature(item)
            if let before = facts[item.id] {
                if before != mark { stirs.append(BrainStir(nodes: [item.id], kind: .memory)) }
            } else if let since, let made = Self.moment(item.createdAt), made > since {
                stirs.append(BrainStir(nodes: [item.id], kind: .memory))
            }
            facts[item.id] = mark
        }
        if since == nil { since = now }
        for source in listed {
            let mark = Self.signature(source)
            let changed = sources[source.id].map { $0 != mark } ?? seenSources
            if changed {
                stirs.append(BrainStir(nodes: [MemoryMaps.sourceId(source.name), MemoryMaps.sourceId(source.id)], kind: .source))
            }
            sources[source.id] = mark
        }
        seenSources = seenSources || !listed.isEmpty
        return stirs
    }

    /// The runtime writes its times as ISO 8601, with or without fractions of a second.
    private static func moment(_ text: String) -> Date? {
        let whole = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? whole.date(from: text)
    }

    /// What about a fact counts as it changing: where it stands, when that was decided, and its words.
    private static func signature(_ item: MemoryItemView) -> String {
        [item.status, item.decidedAt ?? "", item.statement].joined(separator: between)
    }

    /// What about a source counts as it being read: when it last was, what it taught, and whether that failed.
    private static func signature(_ source: MemorySourceView) -> String {
        let counts = source.counts
        return [source.lastReadAt ?? "", source.lastError ?? "", "\(counts.candidate)", "\(counts.verified)",
                "\(counts.conflicting)", "\(counts.outdated)", "\(counts.rejected)"].joined(separator: between)
    }
}

/// One wave of light across the brain: where it starts and when, in seconds on the renderer's clock.
public struct BrainWave: Equatable, Sendable {
    public let origin: SurfacePoint
    public let started: Double

    public init(origin: SurfacePoint, started: Double) {
        self.origin = origin
        self.started = started
    }
}

/// The waves under way and the one waiting its turn, which keeps the brain calm however busy memory is.
public struct BrainPulseQueue: Equatable, Sendable {
    public private(set) var waves: [BrainWave] = []
    private var waiting: SurfacePoint?
    private var lastStarted: Double?

    public init() {}

    /// Whether anything is lit or about to be, so the renderer knows whether it needs every frame.
    public var busy: Bool { !waves.isEmpty || waiting != nil }

    /// A change to show: started now if the brain has rested long enough, otherwise kept, the latest replacing any
    /// earlier one still waiting, so a burst of changes is one wave and not a storm.
    public mutating func offer(_ origin: SurfacePoint, at now: Double) {
        waiting = origin
        advance(at: now, still: false)
    }

    /// Starts the waiting wave once the gap has passed and lets finished waves go.
    public mutating func advance(at now: Double, still: Bool) {
        waves.removeAll { BrainPulses.wave(age: now - $0.started, still: still) == nil }
        guard let origin = waiting, lastStarted.map({ now - $0 >= BrainPulses.calmGap }) ?? true else { return }
        waves.append(BrainWave(origin: origin, started: now))
        if waves.count > BrainPulses.mostWaves { waves.removeFirst(waves.count - BrainPulses.mostWaves) }
        lastStarted = now
        waiting = nil
    }
}

/// How far a wave has spread and how bright it still is, and where a conversation's bead is on its way to the core.
public enum BrainPulses {
    /// The least time between two waves, so even a busy afternoon reads as an occasional breath of light.
    public static let calmGap: TimeInterval = 4
    /// At most this many waves at once, since the second has started before the first has faded.
    public static let mostWaves = 2
    /// How fast a wave spreads, in world points a second, and how long it lives: it crosses the brain once, slowly.
    public static let waveSpeed = 380.0
    public static let waveLife: TimeInterval = 2.8
    /// With Reduce Motion a wave is a brief brightening where it starts and travels nowhere.
    public static let stillLife: TimeInterval = 1.2
    /// A working conversation's bead sets out this often, and spends this share of the beat travelling, the rest resting.
    public static let beat: TimeInterval = 5
    public static let travelShare = 0.55
    /// With Reduce Motion the conversation and the core brighten together instead, this much at the most.
    public static let stillGlow = 0.5
    /// How quickly a wave rises before it fades, as a share of its life.
    private static let rise = 0.12
    private static let beatSalt: UInt64 = 31

    /// A wave's reach and strength at an age, nil once it is over. Still, it does not travel and only glows.
    public static func wave(age: Double, still: Bool) -> (reach: Double, strength: Double)? {
        let life = still ? stillLife : waveLife
        guard age >= 0, age < life else { return nil }
        let share = age / life
        if still { return (0, sin(Double.pi * share)) }
        let strength = share < rise ? share / rise : pow((1 - share) / (1 - rise), 2)
        return (waveSpeed * age, strength)
    }

    /// Where a working conversation's bead is between it and the core, from 0 at the conversation to 1 at the core, and how bright;
    /// nil while it rests between beats. Each agent keeps its own phase, so two never march in step.
    public static func bead(_ id: String, seconds: Double, still: Bool) -> (along: Double, strength: Double)? {
        let phase = SurfaceOrbit.unit(id, salt: beatSalt)
        let into = (seconds / beat + phase).truncatingRemainder(dividingBy: 1)
        guard into < travelShare else { return nil }
        let share = into / travelShare
        let strength = sin(Double.pi * share)
        if still { return (0, strength * stillGlow) }
        // Eased at both ends, so the bead sets off and arrives gently.
        return (share * share * (3 - 2 * share), strength)
    }
}
