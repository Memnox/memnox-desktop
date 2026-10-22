import AppKit
import MemnoxVoiceCore
import SwiftUI

/// The measurements and timings the island is drawn and moved with.
enum Island {
    /// Close to Vorssaint's open notch, wide enough for two cards side by side and no wider.
    static let width: CGFloat = 560
    /// The concave curve where the island meets the screen edge on either side.
    static let flare: CGFloat = 14
    /// How far an open island's content sits in from its sides and bottom.
    static let contentInset: CGFloat = 10
    static let voiceWidth: CGFloat = 440
    /// Big enough that the orb reads as the one thing on screen while you talk.
    static let voiceOrb: CGFloat = 150
    static let window = CGSize(width: width + 2 * flare + windowMargin, height: tallestIsland + hangingBelow)
    /// Room left around the island inside its window.
    private static let windowMargin: CGFloat = 40 + 2 * NotchMetrics.satelliteReach
    /// Room under the tallest island for the pills that hang below it, the signed in pill over the sign in icons,
    /// since a pill past the window's edge is drawn cut off and its clicks fall through to whatever is behind.
    private static let hangingBelow: CGFloat = 112
    /// The tallest the island may grow, which sizes the window it grows inside: the answer opened up.
    private static let tallestIsland: CGFloat = Height.answer
    /// Long enough that passing the pointer across the menu bar never opens it.
    static let dwellResting: TimeInterval = 0.65
    static let dwellBusy: TimeInterval = 0.2
    /// Open and untouched this long, it puts itself away; the last ten seconds are shown as a shrinking line.
    static let idleClose: TimeInterval = 20
    static let countdownFrom: TimeInterval = 10
    /// How long a finished session stays up before the island folds back.
    static let finishedFor = UInt64(finishedSeconds * nanosecondsPerSecond)
    private static let finishedSeconds: TimeInterval = 5.2
    /// How long a phone's finished turn stays up, long enough to read the end of its answer before it folds back.
    static let phoneTurnFor = UInt64(phoneTurnSeconds * nanosecondsPerSecond)
    private static let phoneTurnSeconds: TimeInterval = 8
    /// How long a card says who answered its call elsewhere before it goes, long enough to read one short line.
    static let settledFor = UInt64(settledSeconds * nanosecondsPerSecond)
    private static let settledSeconds: TimeInterval = 2.8
    /// How long a session's logo jitters after something went wrong, matching the orb's own stumble.
    static let stumbleFor = UInt64(stumbleSeconds * nanosecondsPerSecond)
    private static let stumbleSeconds: TimeInterval = 0.9
    private static let nanosecondsPerSecond: TimeInterval = 1_000_000_000

    /// How much wider than the notch the small modes are, leaving room for the orb and the session dots.
    private enum Widening {
        static let peek: CGFloat = 64
        static let compact: CGFloat = 96
    }

    /// Each open mode's height, just tall enough for what that mode holds.
    private enum Height {
        /// Measured from where content starts, since the voice mode sits below the notch row.
        static let voiceBelowTop: CGFloat = 190
        /// Four session rows and the list card's inset below the header, which 180 cut off at the fourth.
        static let overview: CGFloat = 196
        static let session: CGFloat = 256
        static let empty: CGFloat = 150
        static let held: CGFloat = 206
        /// Who asks, the question, and up to four choices with two lines each under them.
        static let question: CGFloat = 372
        static let finished: CGFloat = 170
        /// The header and two rows of Vorssaint's tiles.
        static let launcher: CGFloat = 230
        /// The orb and up to three lines of what is being said under it.
        static let hearingBelowTop: CGFloat = 196
        /// The question and an answer card tall enough for a short reply to sit whole.
        static let conversation: CGFloat = 372
        /// A reply's thread, recipients, subject, a few lines of body and Send.
        static let draft: CGFloat = 430
        /// Tall enough for a file tree or a long list to read without scrolling much.
        static let answer: CGFloat = 560
        /// The question, the rule and its details, three places to pick from and the answers.
        static let rule: CGFloat = 470
    }

    /// The talking modes are narrower than the open island, so the words keep a comfortable line length.
    private enum Width {
        static let hearing: CGFloat = 500
        static let conversation: CGFloat = 540
        /// A row of Vorssaint's tiles, the gaps between them, and the island's inset either side.
        static let launcher: CGFloat = NotchMetrics.tileWidth * CGFloat(NotchMetrics.tileColumns)
            + NotchMetrics.tileSpacing * CGFloat(NotchMetrics.tileColumns - 1) + 2 * contentInset
    }

    /// Where content starts: never above this, and always a little below the notch itself.
    private static let minimumTop: CGFloat = 36
    private static let gapBelowNotch: CGFloat = 4

    /// Growing springs out past its size and back; shrinking eases in and settles.
    private enum Movement {
        static let growResponse = 0.5
        static let growDamping = 0.72
        static let shrinkDuration: TimeInterval = 0.34
        /// The control points of the shrinking curve: a gentle start and a long soft landing.
        static let shrinkStart = (x: 0.45, y: 0.0)
        static let shrinkEnd = (x: 0.2, y: 1.0)
    }

    /// The orb's place and size in each mode: beside the notch when small, left of the content when open.
    private enum OrbSpot {
        static let peekX: CGFloat = 19
        static let peekDiameter: CGFloat = 18
        static let peekHoverDiameter: CGFloat = 22
        static let compactX: CGFloat = 27
        static let compactDiameter: CGFloat = 20
        static let compactHoverDiameter: CGFloat = 23
        /// How far below the content top the large voice orb's centre sits.
        static let voiceBelowTop: CGFloat = 92
        static let overviewX: CGFloat = 54
        static let overviewDiameter: CGFloat = 58
        static let emptyX: CGFloat = 70
        static let emptyDiameter: CGFloat = 62
        static let heldX: CGFloat = 62
        static let heldDiameter: CGFloat = 56
        static let finishedX: CGFloat = 62
        static let finishedDiameter: CGFloat = 58
        /// Above the words it is hearing, smaller than the voice orb so three lines fit under it.
        static let hearingBelowTop: CGFloat = 50
        static let hearingDiameter: CGFloat = 84
        /// In the header row left of the notch, a small light while the words take the space below.
        static let headerX: CGFloat = 30
        static let headerDiameter: CGFloat = 20
    }

    static func size(_ mode: IslandMode, _ notch: NotchGeometry) -> CGSize {
        switch mode {
        case .peek: return CGSize(width: notch.width + Widening.peek, height: notch.height)
        case .compact: return CGSize(width: notch.width + Widening.compact, height: notch.height)
        case .voice: return CGSize(width: voiceWidth, height: top(notch) + Height.voiceBelowTop)
        case .overview: return CGSize(width: width, height: Height.overview)
        case .session: return CGSize(width: width, height: Height.session)
        case .empty: return CGSize(width: width, height: Height.empty)
        case .held: return CGSize(width: width, height: Height.held)
        case .question: return CGSize(width: width, height: Height.question)
        case .finished: return CGSize(width: width, height: Height.finished)
        case .launcher: return CGSize(width: Width.launcher, height: Height.launcher)
        case .hearing: return CGSize(width: Width.hearing, height: top(notch) + Height.hearingBelowTop)
        case .conversation: return CGSize(width: Width.conversation, height: Height.conversation)
        case .draft: return CGSize(width: Width.conversation, height: Height.draft)
        case .answer: return CGSize(width: width, height: Height.answer)
        case .rule: return CGSize(width: Width.conversation, height: Height.rule)
        }
    }

    /// The round buttons start just under the notch row, as Vorssaint's do, so the menu bar never hides the top pair.
    static func satelliteTop(_ notch: NotchGeometry) -> CGFloat { notch.height + satelliteGapBelowNotch }

    /// The height the round buttons beside the island take from its top, for the window to let their clicks in.
    static func satelliteColumn(_ notch: NotchGeometry) -> CGFloat {
        satelliteTop(notch) + NotchMetrics.satelliteStep + NotchMetrics.satelliteDiameter + satelliteGapBelowNotch
    }

    private static let satelliteGapBelowNotch: CGFloat = 6

    static func area(_ mode: IslandMode, _ notch: NotchGeometry) -> CGFloat {
        let size = size(mode, notch)
        return size.width * size.height
    }

    /// Where content starts below the notch row, which is also where the header sits.
    static func top(_ notch: NotchGeometry) -> CGFloat { max(minimumTop, notch.height + gapBelowNotch) }

    /// Growing overshoots a little, the way something springs out; shrinking settles with no bounce.
    static func motion(growing: Bool) -> Animation {
        growing
            ? .spring(response: Movement.growResponse, dampingFraction: Movement.growDamping)
            : .timingCurve(
                Movement.shrinkStart.x, Movement.shrinkStart.y, Movement.shrinkEnd.x, Movement.shrinkEnd.y,
                duration: Movement.shrinkDuration
            )
    }

    /// The orb's centre and diameter in each mode, so it travels and grows with the island as one piece.
    static func orb(_ mode: IslandMode, _ notch: NotchGeometry, hovering: Bool) -> (center: CGPoint, diameter: CGFloat) {
        let height = size(mode, notch).height
        let top = top(notch)
        let middle = top + (height - top - contentInset) / 2
        switch mode {
        case .peek:
            return (CGPoint(x: OrbSpot.peekX, y: notch.height / 2), hovering ? OrbSpot.peekHoverDiameter : OrbSpot.peekDiameter)
        case .compact:
            return (
                CGPoint(x: OrbSpot.compactX, y: notch.height / 2),
                hovering ? OrbSpot.compactHoverDiameter : OrbSpot.compactDiameter
            )
        case .voice: return (CGPoint(x: voiceWidth / 2, y: top + OrbSpot.voiceBelowTop), voiceOrb)
        case .overview: return (CGPoint(x: OrbSpot.overviewX, y: middle), OrbSpot.overviewDiameter)
        case .empty: return (CGPoint(x: OrbSpot.emptyX, y: middle), OrbSpot.emptyDiameter)
        case .held: return (CGPoint(x: OrbSpot.heldX, y: middle), OrbSpot.heldDiameter)
        case .finished: return (CGPoint(x: OrbSpot.finishedX, y: middle), OrbSpot.finishedDiameter)
        case .hearing: return (CGPoint(x: Width.hearing / 2, y: top + OrbSpot.hearingBelowTop), OrbSpot.hearingDiameter)
        // A question gives the agent's logo and its choices the whole width, so the orb waits in the header.
        case .session, .conversation, .draft, .answer, .rule, .launcher, .question:
            return (CGPoint(x: OrbSpot.headerX, y: notch.height / 2), OrbSpot.headerDiameter)
        }
    }
}

/// The colours the island is painted in: its cards, its veil and each agent's own colour.
enum IslandPalette {
    static let card = Color(hex: 0x141518)
    /// The answer that lets something happen: white on dark, near black on the light windows outside the notch.
    static let primaryFill = Color(light: 0x0D0D0D, dark: 0xF5F6F8)
    static let primaryText = Color(light: 0xFFFFFF, dark: 0x0B0C0E)
    static let quiet = Color(hex: 0x5F646D)
    static let soft = Color(light: 0x5F646D, dark: 0xC9CDD4)
    /// The system's own status hues as they show on black.
    static let red = Color(hex: 0xFF453A)
    static let green = Color(hex: 0x30D158)
    static let amber = Color(hex: 0xFF9F0A)
    static let indigo = Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255)

    /// Each agent keeps one colour everywhere it appears; any other takes one of these by its name.
    private static let known: [String: UInt32] = [
        "claude-code": 0xD97757, "claude": 0xD97757, "claude-desktop": 0xD97757,
        "codex": 0x2DD4BF, "codex-cli": 0x2DD4BF, "cursor": 0xC0C4CC, "gemini": 0x8AB4F8,
        "antigravity": 0xE879F9, "hermes": 0xA78BFA, "openclaw": 0xF7B32B, "cline": 0x38BDF8,
        "gemini-cli": 0x8AB4F8, "copilot-cli": 0x7EE787, "opencode": 0xFB7185,
    ]
    private static let others: [UInt32] = [0xF472B6, 0x34D399, 0xFB923C, 0x60A5FA, 0xE879F9]

    /// How the daemon prefixes an agent id, which is dropped to leave the agent's kind.
    private static let agentIdPrefix = "agt_"
    /// The multiplier and mask of the name hash, kept small so the index stays positive.
    private static let hashMultiplier = 31
    private static let hashMask = 0xFFFF

    static func kind(_ agent: String?) -> String {
        let id = agent ?? ""
        return id.hasPrefix(agentIdPrefix) ? String(id.dropFirst(agentIdPrefix.count)) : id
    }

    static func color(_ agent: String?) -> Color {
        let kind = kind(agent)
        if let hex = known[kind] { return Color(hex: hex) }
        let index = kind.unicodeScalars.reduce(0) { ($0 &* hashMultiplier &+ Int($1.value)) & hashMask }
        return Color(hex: others[index % others.count])
    }
}
