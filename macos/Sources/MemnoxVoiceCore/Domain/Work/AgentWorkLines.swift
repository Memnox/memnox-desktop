import Foundation

/// What a screen says about agent work: the issue it joins, where it stands and the latest word from its agent. The
/// issue stays in its tracker; nothing here fetches it or decides what may happen to it.
public enum AgentWorkLines {
    /// Work a person still has to see to, newest change first: waiting on a handoff or a done claim, then the rest open.
    public static func open(_ work: [AgentWork]) -> [AgentWork] {
        work.filter { !isFinished($0) }
    }

    public static func finished(_ work: [AgentWork]) -> [AgentWork] {
        work.filter(isFinished)
    }

    public static func isFinished(_ work: AgentWork) -> Bool {
        work.workStatus == .done || work.workStatus == .stopped
    }

    /// The open work a profile's agent carries now, the newest first.
    public static func current(for profileId: String, in work: [AgentWork]) -> AgentWork? {
        open(work).first { $0.profileId == profileId }
    }

    /// The issue as a person names it: its key, and its title where one was given.
    public static func issue(_ work: AgentWork) -> String {
        guard let title = work.target.title, !title.isEmpty else { return work.target.externalId }
        return "\(work.target.externalId) \u{00B7} \(title)"
    }

    /// The tracker it lives in, by its own name.
    public static func trackerName(_ source: String) -> String {
        switch Tracker(rawValue: source) {
        case .linear: "Linear"
        case .jira: "Jira"
        case .github: "GitHub"
        case .asana: "Asana"
        case nil: source
        }
    }

    public static func status(_ work: AgentWork) -> String {
        switch work.workStatus {
        case .active: "Working"
        case .blocked: "Blocked"
        case .handoffRequested: "Wants to hand it on"
        case .doneClaimed: "Says it is done"
        case .done: "Done"
        case .stopped: "Stopped"
        case nil: work.status
        }
    }

    /// Whether it waits on the person: a handoff to answer or a done claim to check.
    public static func needsYou(_ work: AgentWork) -> Bool {
        work.workStatus == .doneClaimed || work.waitingHandoff != nil
    }

    /// The latest word from its agent, or what it is doing when it has said nothing yet.
    public static func latest(_ work: AgentWork) -> String {
        work.latestProgress?.note ?? "No word from the agent yet."
    }

    /// Who the handoff goes to, in a line: a profile by its name where the caller knows it, or a person, and never an
    /// id the person could not read.
    public static func handoffLine(_ handoff: WorkHandoff, profileName: (String) -> String?) -> String {
        let to = handoff.to.profileId.map { profileName($0) ?? anotherAgent } ?? filled(handoff.to.person) ?? "someone else"
        return "Wants to hand it to \(to): \(handoff.reason)"
    }

    /// Said for an agent whose job this Mac does not know by name.
    public static let anotherAgent = "another agent"

    /// The agent carrying the work by its job's name, or a plain word where the job is not known here.
    public static func agentName(_ work: AgentWork, profileName: (String) -> String?) -> String {
        profileName(work.profileId) ?? anotherAgent
    }

    /// The link to open, only a web address, so a tracker's link never starts an app.
    public static func link(_ work: AgentWork) -> URL? {
        guard let text = work.target.url, let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil else { return nil }
        return url
    }

    public static func started(_ target: String) -> String {
        "Started on \(target.trimmingCharacters(in: .whitespacesAndNewlines)). The agent sees it at its next pause."
    }

    public static func answered(_ word: HandoffAnswerWord) -> String {
        switch word {
        case .accept: "Handed on."
        case .decline: "Declined. The work stays with the agent that has it."
        }
    }

    /// What the start field says before it is sent, or nil when it will do.
    public static func targetProblem(_ target: String) -> String? {
        target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Paste the issue key, such as LIN-123, or its link." : nil
    }

    /// A field left blank is not sent, so the daemon never stores an empty title or folder.
    public static func filled(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
