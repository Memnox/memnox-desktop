import Foundation

/// The parts of Memnox the notch plays in turn beside the steps, in the order it plays them.
enum Highlight: Int, CaseIterable, Identifiable {
    /// Every agent on the Mac at a glance, and one opened up as it works.
    case sessions
    /// An agent waits on the person, they answer from the notch, and the work carries on.
    case answer
    /// A rule said aloud, drawn as a card before it holds.
    case rule
    /// A reply on a pull request in their own name, after one tap to sign in, sent with Touch ID.
    case tools
    /// What every agent did, asked for out loud and answered in a sentence.
    case catchUp

    var id: Int { rawValue }

    var symbol: String {
        switch self {
        case .sessions: return "square.stack.3d.up"
        case .answer: return "hand.raised"
        case .rule: return "text.badge.checkmark"
        case .tools: return "paperplane"
        case .catchUp: return "waveform"
        }
    }

    var title: String {
        switch self {
        case .sessions: return "See every agent at a glance"
        case .answer: return "Answer your agents from the notch"
        case .rule: return "Say a rule out loud"
        case .tools: return "Act in your own tools, as you"
        case .catchUp: return "Catch up by asking"
        }
    }

    /// What the guide says as the notch plays this part, written to be heard rather than read.
    var spoken: String {
        switch self {
        case .sessions: return "Every agent you run, like Claude Code, Codex or Cursor, shows up here in the notch. Click one to see what it is changing."
        case .answer: return "When an agent wants to do something that matters, like pushing to main, it asks you here. One click, and it carries on."
        case .rule: return "Say a rule out loud, like never push to main without asking me, and every agent keeps it from then on."
        case .tools: return "I can act in your own tools as you, like replying on a pull request or sending a message. You see the draft first, and send it with Touch ID."
        case .catchUp: return "And when you come back, just ask what your agents did. I will tell you in a sentence."
        }
    }

    var detail: String {
        switch self {
        case .sessions: return "Claude Code, Codex and Cursor in the notch, each one a click from what it is changing."
        case .answer: return "When an agent wants to push to main, it asks you here. One click, and it carries on."
        case .rule: return "\u{201C}Never push to main without asking me.\u{201D} Memnox writes it down and every agent keeps it."
        case .tools: return "Reply on a pull request, send a Slack DM or an email in your own name. You see the draft and send it with Touch ID."
        case .catchUp: return "\u{201C}What did my agents do while I was out?\u{201D} The answer comes back in a sentence."
        }
    }
}
