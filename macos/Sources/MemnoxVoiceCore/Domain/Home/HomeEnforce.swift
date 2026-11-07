import Foundation

/// What asking the runtime to stop rather than watch came to.
public enum EnforceOutcome: Equatable, Sendable {
    /// The runtime moved the mode, from what it was to what it is now.
    case enforcing(HomeModeSet)
    /// The runtime said no, with why, or is too old to know the method.
    case refused(String)
    case unreachable
}

/// The words around turning this Mac from watching to stopping: the confirm that says what changes, and the line the
/// step shows once the runtime answered. Only ever toward enforce, since going back widens and stays at the terminal.
public enum HomeEnforce {
    public static let title = "Turn on stopping?"
    public static let message = "Today this Mac records what a rule would have stopped and lets it run. From now on, "
        + "what a rule denies is stopped, and what a rule asks about waits for you."
    public static let detail = "The record in Activity shows what would have been stopped so far, so you can read it first."
    public static let confirm = "Turn on stopping"
    public static let readFirst = "Read the record first"
    public static let remote = "This window talks to a server, so run memnox protect --enforce on that server instead."

    /// Said as setup finishes while this Mac only watches, so the person knows nothing is stopped yet and is asked
    /// whether to stop; nil once it enforces, or when the runtime did not say, since then there is nothing to ask.
    public static func afterSetup(_ mode: HomeMode?) -> String? {
        switch mode {
        case .observe:
            return "One more thing. Memnox is still in observing mode, so it records what a rule would stop but stops "
                + "nothing yet. Do you want to switch to enforcing mode? Choose on your screen."
        case .enforce, nil:
            return nil
        }
    }

    /// The line under the step once the runtime answered, saying where the mode went and how to put it back.
    public static func line(_ outcome: EnforceOutcome) -> String {
        switch outcome {
        case .enforcing(let set) where set.was == set.now:
            return "This Mac was already stopping what a rule denies."
        case .enforcing:
            return "This Mac now stops what a rule denies. memnox protect --observe in a terminal puts it back."
        case .refused(let why):
            return why
        case .unreachable:
            return "Memnox did not answer. Check that it is running, then try again."
        }
    }
}
