import Foundation

/// The one thing the end of the first run asks the person to do next.
public enum FirstRunNext: Equatable, Sendable {
    /// The microphone is allowed, so the quickest proof that Memnox works is to talk to it.
    case talk
    /// Anything else opens Memnox on Home, where what needs the person waits.
    case openHome

    public var title: String {
        switch self {
        case .talk: "Try it: press and talk"
        case .openHome: "Open Memnox"
        }
    }
}

/// What is optional after the steps, each done from the end itself or a link to the Settings page that holds it; the
/// phone and Memnox Cloud are offered on Where should Memnox ask you.
public enum FirstRunExtraId: String, CaseIterable, Sendable {
    case voice
    case keys

    /// The Settings tab it opens, as `Destinations.settingsTabs` names it.
    public var settingsTab: String {
        switch self {
        case .voice: "voice"
        case .keys: "listening"
        }
    }
}

public struct FirstRunExtra: Equatable, Sendable {
    public let id: FirstRunExtraId
    public let title: String
    public let detail: String
    /// Already in place, so the row shows a tick rather than asking.
    public let done: Bool
}

/// The end of the first run: a short greeting, one clear next action, and a short list of what is optional.
public enum FirstRunEnd {
    /// "You're set, Sam."
    public static func title(name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "You're set." : "You're set, \(trimmed)."
    }

    public static let lead = "Your agents work inside your starting rules now. Try one ask, then see what that covers."

    /// Talking once the microphone is allowed, since it shows Memnox at work in a second; Home otherwise.
    public static func next(hearing: Bool) -> FirstRunNext {
        hearing ? .talk : .openHome
    }

    /// What talking takes, said under the button that does it.
    public static let talkHint = "Press Option Space, talk, and let go. Memnox answers in the notch."

    /// The optional rows in the order a person would reach for them, each saying whether it is already done.
    public static func extras(hearing: Bool) -> [FirstRunExtra] {
        FirstRunExtraId.allCases.map { id in
            switch id {
            case .voice:
                return hearing
                    ? FirstRunExtra(id: id, title: "Talk to Memnox", detail: "The microphone is allowed. Pick the voice it answers in.", done: true)
                    : FirstRunExtra(id: id, title: "Talk to Memnox", detail: "Allow the microphone, and talk to your agents from anywhere.", done: false)
            case .keys:
                return FirstRunExtra(id: id, title: "Keys to try",
                                     detail: "Option Space to ask, Control Option to say a rule, Right Option to dictate.", done: false)
            }
        }
    }

    /// The one thing left that only the person can do, said and shown once: granting the microphone, which macOS asks
    /// for itself. Nil once it is granted, since nothing else waits on them.
    public static func permissionHint(hearing: Bool) -> String? {
        hearing ? nil : "One thing only you can do: press Allow beside Talk to Memnox, and say yes when macOS asks for the microphone."
    }
}
