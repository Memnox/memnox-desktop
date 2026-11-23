import Foundation

/// The counts Home's steps are read off, each one something the runtime or this Mac reports, never an estimate.
public struct HomeStanding: Equatable, Sendable {
    /// Whether the two onboarding steps were finished, which is the first rung until they are.
    public var setupFinished = true
    public var agents = 0
    public var agentsProtected = 0
    public var rulesInForce = 0
    public var actionsRecorded = 0
    public var phonesPaired = 0
    /// Whether the runtime said it enforces rather than observes; nil before it answered.
    public var mode: HomeMode?
    public var appsConnected = 0
    public var sourcesLinked = 0
    public var skillsShared = 0
    public var serversShared = 0

    public init() {}
}

/// How the runtime applies a verdict, as it names it on its home.
public enum HomeMode: String, Sendable {
    case observe
    case enforce

    /// The badge beside Home's greeting, so the mode the runtime reported is read at a glance.
    public var badge: String {
        switch self {
        case .observe: return "Watching only"
        case .enforce: return "Protecting"
        }
    }
}

/// Where this Mac is, read off what is true rather than how many steps are ticked, as the cloud console's home reads it.
public enum HomeStage: String, CaseIterable, Sendable {
    case ungoverned
    case observing
    case enforcing

    public var label: String {
        switch self {
        case .ungoverned: return "Not set up yet"
        case .observing: return "Watching only"
        case .enforcing: return "Protecting"
        }
    }

    public var means: String {
        switch self {
        case .ungoverned: return "Memnox cannot see your agents yet. Connecting them takes one press, and nothing is stopped."
        case .observing: return "Memnox writes down what your agents do and stops nothing yet."
        case .enforcing: return "Memnox stops anything risky until you say yes, and lets the rest run."
        }
    }
}

/// The two tracks the steps are listed under, the same split as the cloud console's home.
public enum HomeTrack: String, CaseIterable, Sendable {
    case mac
    case work

    public var label: String {
        switch self {
        case .mac: return "Your agents"
        case .work: return "Where your work lives"
        }
    }

    public var lead: String {
        switch self {
        case .mac: return "What Memnox sees and stops, decided on this Mac with no network in the path."
        case .work: return "What your agents can reach and start from. Linked where it is, and read on this Mac."
        }
    }
}

/// Every step, in the order a Mac earns them: three at most, so getting started never reads as a project.
public enum HomeStepID: String, CaseIterable, Sendable {
    case protectAgents
    case chooseCare
    case answerAway
}

/// One rung: what it is, what it gives, how to do it, and whether it is done.
public struct HomeStep: Equatable, Identifiable, Sendable {
    public let id: HomeStepID
    public let title: String
    /// What it gives, in the person's terms, never what it costs.
    public let value: String
    public let how: String
    /// The one press that moves it on.
    public let action: String
    public let track: HomeTrack
    public let done: Bool
    /// True where nobody can hurry it, such as an agent doing something for the record to hold.
    public let waitsOnAnAgent: Bool
}

/// A count already won, by its label.
public struct HomeCount: Equatable, Sendable {
    public let label: String
    public let count: Int
}

/// The whole of Home's steps: the stage, the next thing to do, what waits, every step by track and what is won.
public struct HomeSetup: Equatable, Sendable {
    public let stage: HomeStage
    public let steps: [HomeStep]
    /// The first unfinished step the person can go and do; nil once only waits are left.
    public let next: HomeStep?
    public let waiting: [HomeStep]
    public let standing: [HomeCount]

    public var completed: Int { steps.filter(\.done).count }
    public var total: Int { steps.count }
    /// Nothing left at all, waits included, which is when Home stops showing the steps.
    public var climbed: Bool { next == nil && waiting.isEmpty }

    /// The steps of one track that are neither the next one nor waiting, since those are drawn above the tracks.
    public func rest(of track: HomeTrack) -> [HomeStep] {
        steps.filter { step in
            step.track == track && step.id != next?.id && !waiting.contains { $0.id == step.id }
        }
    }
}

/// Home's getting started steps, mirroring the cloud console's ladder in memnox-cloud's onboarding.ts: the same stage
/// line, the same Get set up rung, the same tracks and the same counts won, read off this Mac.
public enum HomeSteps {
    /// The card's title on every surface, from the contract's Home block of that name.
    public static let cardTitle = "Get set up"
    public static let allSteps = "Show all steps"
    public static let fewerSteps = "Show fewer steps"
    public static let waitingLabel = "Waiting on an agent"
    public static let waitingMeans = "This closes the first time an agent on this Mac does something. Use one as you normally would."

    public static func setup(_ standing: HomeStanding) -> HomeSetup {
        let steps = self.steps(standing)
        let open = steps.filter { !$0.done }
        return HomeSetup(stage: stage(standing), steps: steps, next: open.first { !$0.waitsOnAnAgent },
                         waiting: open.filter(\.waitsOnAnAgent), standing: won(standing))
    }

    /// "3 of 8 done", beside the stage as the cloud counts it.
    public static func progress(_ setup: HomeSetup) -> String {
        "\(setup.completed) of \(setup.total) done"
    }

    static func stage(_ standing: HomeStanding) -> HomeStage {
        if standing.agentsProtected == 0 { return .ungoverned }
        return standing.mode == .enforce ? .enforcing : .observing
    }

    static func steps(_ standing: HomeStanding) -> [HomeStep] {
        [
            HomeStep(id: .protectAgents, title: "Connect your agents",
                     value: "Memnox sees what each agent does and can stop what is risky, from Claude Code to Cursor.",
                     how: "Press Connect, and Memnox puts itself beside each agent it found. Nothing is stopped yet.",
                     action: "Open Agents", track: .mac,
                     done: standing.agents > 0 && standing.agentsProtected == standing.agents, waitsOnAnAgent: false),
            HomeStep(id: .chooseCare, title: "Choose how careful Memnox is",
                     value: "Just watch, ask before risky things, or ask about almost everything. You can change it any time.",
                     how: "Pick one, then confirm each rule with Touch ID on the island.",
                     action: "Choose", track: .mac,
                     done: standing.setupFinished || standing.rulesInForce > 0, waitsOnAnAgent: false),
            HomeStep(id: .answerAway, title: "Answer from your phone",
                     value: "When an agent waits for you and you are away, the question reaches your iPhone and you answer with Face ID.",
                     how: "Pair your iPhone once.",
                     action: "Pair your iPhone", track: .mac, done: standing.phonesPaired > 0, waitsOnAnAgent: false),
        ]
    }

    /// Only the counts above zero, in the order a Mac earns them.
    static func won(_ standing: HomeStanding) -> [HomeCount] {
        let all = [
            HomeCount(label: "Agents protected", count: standing.agentsProtected),
            HomeCount(label: "Rules in force", count: standing.rulesInForce),
            HomeCount(label: "Actions recorded", count: standing.actionsRecorded),
            HomeCount(label: "Phones paired", count: standing.phonesPaired),
            HomeCount(label: "Apps connected", count: standing.appsConnected),
            HomeCount(label: "Sources linked", count: standing.sourcesLinked),
            HomeCount(label: "Skills shared", count: standing.skillsShared),
            HomeCount(label: "Servers shared", count: standing.serversShared),
        ]
        return all.filter { $0.count > 0 }
    }
}
