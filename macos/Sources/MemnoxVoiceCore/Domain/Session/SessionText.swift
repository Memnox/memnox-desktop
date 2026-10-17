import Foundation

/// How a session, its steps and its timings read on screen, kept as plain text so it is tested without a window.
public enum SessionText {
    /// Sits between the parts of a subtitle, a middle dot with a space either side.
    public static let separator = " \u{00B7} "
    /// Said in a subtitle while the agent is busy, in place of how long ago it last did anything.
    public static let workingWord = "working"

    /// Under this many seconds it is still the moment that just passed, not a minute ago.
    private static let justNowSeconds = 45
    private static let secondsPerMinute = 60
    private static let secondsPerHour = 60 * 60
    private static let secondsPerDay = 24 * 60 * 60
    private static let millisecondsPerSecond = 1_000.0
    /// A folder and a file, which is how somebody names a file out loud.
    private static let spokenPathParts = 2
    /// The last two labels of a host name the site, so api.github.com reads as github.com.
    private static let siteLabels = 2
    private static let schemes = ["https://", "http://"]
    private static let brainPrefix = "brain."
    private static let operatorPrefix = "operator."
    /// The trace's own step names, as a person would say them.
    private static let traceStepNames = [
        "voice.turn": "Your question",
        "voice.context": "Reading the sessions",
        "brain.turn": "Thinking",
        "mac.waiting for the end": "Waiting for you to finish",
        "mac.first sentence ready": "Answer arriving",
        "mac.speaking": "Speaking",
    ]

    /// How long ago an ISO 8601 moment was, the way a person says it, or nil when there is no readable moment.
    /// A moment a little ahead of this clock is just now, since two machines rarely agree to the second.
    public static func ago(_ iso: String?, now: Date) -> String? {
        guard let iso, let date = parseMoment(iso) else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < justNowSeconds { return "just now" }
        if seconds < secondsPerHour { return "\(max(1, seconds / secondsPerMinute)) min ago" }
        if seconds < secondsPerDay { return "\(seconds / secondsPerHour) h ago" }
        return "\(seconds / secondsPerDay) d ago"
    }

    /// The steps worth reading: what it changed and ran, leaving out the hosts it called unless that is all
    /// it did, and one line, the latest, for the same thing done several times.
    public static func meaningful(_ steps: [SessionViewStep]) -> [SessionViewStep] {
        let work = steps.filter { $0.stepSurface != .network }
        var kept: [SessionViewStep] = []
        // The latest of each line only, since a session that only talks to the network reaches the same few sites over and over.
        for step in work.isEmpty ? steps : work {
            kept.removeAll { line(for: $0) == line(for: step) }
            kept.append(step)
        }
        return kept
    }

    /// True when all Memnox saw of a session is where it connected, as for a desktop app it does not
    /// hook, so an empty file list means its files are unseen rather than unchanged.
    public static func onlyNetwork(_ steps: [SessionViewStep]) -> Bool {
        !steps.isEmpty && steps.allSatisfy { $0.stepSurface == .network }
    }

    /// A step as a line: a host it called by its site's name, and anything else as the runtime wrote it with each path cut to its last part.
    public static func line(for step: SessionViewStep) -> String {
        guard step.stepSurface == .network, let target = step.text.split(separator: " ").last else {
            // A full path says nothing a glance can use; its last part is the file or folder.
            return step.text.split(separator: " ", omittingEmptySubsequences: false).map { word in
                word.contains("/") ? (String(word) as NSString).lastPathComponent : String(word)
            }.joined(separator: " ")
        }
        let bare = schemes.reduce(String(target)) { $0.replacingOccurrences(of: $1, with: "") }
        let host = bare.split(separator: "/").first.map(String.init) ?? bare
        let labels = host.split(separator: ".")
        let site = labels.count > siteLabels ? labels.suffix(siteLabels).joined(separator: ".") : host
        return "Reached \(site)"
    }

    /// A trace step as a person would name it, rather than the name it was recorded under.
    public static func traceStepName(_ name: String) -> String {
        if let said = traceStepNames[name] { return said }
        if name.hasPrefix(brainPrefix) { return "Asked \(name.dropFirst(brainPrefix.count))" }
        if name.hasPrefix(operatorPrefix) { return "Ran \(name.dropFirst(operatorPrefix.count))" }
        return name
    }

    /// Milliseconds under a second and seconds with one place above, the way a waterfall is read.
    public static func duration(milliseconds: Double) -> String {
        milliseconds < millisecondsPerSecond
            ? "\(Int(milliseconds)) ms"
            : String(format: "%.1f s", milliseconds / millisecondsPerSecond)
    }

    /// The last two parts of a path, which is how somebody names a file out loud.
    public static func shortPath(_ path: String) -> String {
        path.split(separator: "/").suffix(spokenPathParts).joined(separator: "/")
    }

    /// Reads a moment with or without fractional seconds, since the runtime writes both.
    private static func parseMoment(_ iso: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
}

extension SessionCard {
    /// What it is on, which is what tells two sessions of the same agent apart, with terminal glyphs taken out.
    public var title: String { SessionReading.readable(task) ?? SessionReading.repository(repository) ?? agentName }

    /// The agent, where it is if the title did not say, and how lately it did anything.
    public func subtitle(now: Date) -> String {
        var parts: [String] = []
        if title != agentName { parts.append(agentName) }
        if let repository = SessionReading.repository(repository), repository != title { parts.append(repository) }
        parts.append(status.isActive ? SessionText.workingWord : SessionText.ago(lastActive, now: now) ?? state)
        return parts.joined(separator: SessionText.separator)
    }
}

extension SessionView {
    /// Its repository and the branch there, the way a person names where the work happens.
    public var place: String? {
        guard let repository else { return runningIn }
        guard let branch else { return repository }
        return "\(repository) on \(branch)"
    }

    /// Where it runs, when it began and how lately it did anything, the quiet line under what it is about.
    public func context(now: Date) -> String? {
        let parts = [
            `where` ?? runningIn,
            SessionText.ago(startedAt, now: now).map { "started \($0)" },
            status.isActive ? SessionText.workingWord : SessionText.ago(lastActive, now: now).map { "active \($0)" },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: SessionText.separator)
    }
}
