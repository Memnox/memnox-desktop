import Foundation

/// The counts Home's steps are read off, each one something the runtime or this Mac reports, never an estimate.
public struct HomeStanding: Equatable, Sendable {
    /// Whether the five onboarding steps were finished, which is the first rung until they are.
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
        case .observe: return "Observing on this Mac"
        case .enforce: return "Enforcing on this Mac"
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
        case .ungoverned: return "Nothing governed yet"
        case .observing: return "Observing"
        case .enforcing: return "Enforcing"
        }
    }

    public var means: String {
        switch self {
        case .ungoverned: return "No agent on this Mac is under Memnox yet, so Memnox decides nothing here. Protecting them takes one press."
        case .observing: return "Your agents record what a rule would have stopped, and nothing is blocked. Read a week before enforcing."
        case .enforcing: return "This Mac applies the verdict rather than recording it, on the rules you put in force."
        }
    }
}

/// The two tracks the steps are listed under, the same split as the cloud console's home.
public enum HomeTrack: String, CaseIterable, Sendable {
    case mac
    case work

    public var label: String {
        switch self {
        case .mac: return "The agents on this Mac"
        case .work: return "Where your work lives"
        }
    }

    public var lead: String {
        switch self {
        case .mac: return "Where a verdict is reached. Decided on this Mac, with no network in the path."
        case .work: return "What your agents can reach and start from. Linked where it is, and read on this Mac."
        }
    }
}

/// Every step, in the order a Mac earns them.
public enum HomeStepID: String, CaseIterable, Sendable {
    case finishSetup
    case protectAgents
    case rulesInForce
    case actionsRecorded
    case answerAway
    case enforce
    case connectApps
    case linkSource
    case shareSkills
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
/// line, the same Do this next rung, the same two tracks and the same counts won, read off this Mac.
public enum HomeSteps {
    /// The card's title on every surface, from the contract's Home block of that name.
    public static let cardTitle = "Do this next"
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
            HomeStep(id: .finishSetup, title: "Finish setting up this Mac",
                     value: "Five short steps put your agents under Memnox and choose where it asks you, so the rest of these can start.",
                     how: "Who it is for, your agents, this Mac, where Memnox asks you, and your starting rules.",
                     action: "Run setup", track: .mac, done: standing.setupFinished, waitsOnAnAgent: false),
            HomeStep(id: .protectAgents, title: "Put your agents under Memnox",
                     value: "Every agent on this Mac, Claude Code through Cursor, reports to one place under one rule set.",
                     how: "Press Protect, and Memnox puts itself under each agent it found. Nothing is stopped on the first day.",
                     action: "Open Agents", track: .mac,
                     done: standing.agents > 0 && standing.agentsProtected == standing.agents, waitsOnAnAgent: false),
            HomeStep(id: .rulesInForce, title: "Let your rules reach them",
                     value: "Memnox decides on this Mac with no network in the path. This is the moment it controls something rather than watching it.",
                     how: "Add a ready-made pack, then confirm each rule with Touch ID on the island.",
                     action: "Add rules", track: .mac, done: standing.rulesInForce > 0, waitsOnAnAgent: false),
            HomeStep(id: .actionsRecorded, title: "See what your agents actually did",
                     value: "Every action, the verdict it met and the rule that decided, in one record rather than one terminal's scrollback.",
                     how: "Use an agent as you normally would. What it does shows up in Activity.",
                     action: "Open Activity", track: .mac, done: standing.actionsRecorded > 0, waitsOnAnAgent: true),
            HomeStep(id: .answerAway, title: "Answer an agent without going to its terminal",
                     value: "An agent stops for a question and you answer it from the notch, out loud with Option Space, or from your iPhone when you are away.",
                     how: "Pair your iPhone, so a question reaches you with Face ID wherever you are.",
                     action: "Pair your iPhone", track: .mac, done: standing.phonesPaired > 0, waitsOnAnAgent: false),
            HomeStep(id: .enforce, title: "Turn this Mac from watching to stopping",
                     value: "Observe mode records what it would have stopped. Enforce mode stops it. Do this once a week of the record reads right.",
                     how: "Read the record in Activity for what would have been stopped, then turn on stopping here.",
                     action: "Turn on stopping", track: .mac, done: standing.mode == .enforce, waitsOnAnAgent: false),
            HomeStep(id: .connectApps, title: "Connect the apps you work in",
                     value: "Gmail, Slack, GitHub and the rest. Agents act in them as you, and ask before anything goes out.",
                     how: "Pick an app under Connectors and sign in to it once.",
                     action: "Connect an app", track: .work, done: standing.appsConnected > 0, waitsOnAnAgent: false),
            HomeStep(id: .linkSource, title: "Give your agents memory",
                     value: "Your notes and instruction files, linked where they are and read only on this Mac, so every agent starts from what you know.",
                     how: "Add a folder or an instruction file as a source.",
                     action: "Add a source", track: .work, done: standing.sourcesLinked > 0, waitsOnAnAgent: false),
            HomeStep(id: .shareSkills, title: "Share skills and servers across agents",
                     value: "Kept once in Memnox and written into each agent's own format, so one added once reaches every agent you choose.",
                     how: "Bring in the skills your agents already keep, then give them to the agents you choose.",
                     action: "Open Skills", track: .work,
                     done: standing.skillsShared + standing.serversShared > 0, waitsOnAnAgent: false),
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
