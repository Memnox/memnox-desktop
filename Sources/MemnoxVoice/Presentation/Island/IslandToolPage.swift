import MemnoxVoiceCore
import SwiftUI

/// What a person can ask Memnox about each of their apps, offered as taps on that app's page in the notch.
/// Each one goes whole to ask as if it were said, so the daemon decides what it means and nothing here acts on it.
enum ToolAsks {
    private static let asks: [String: [String]] = [
        "slack": [
            "Catch me up on Slack since this morning",
            "What did people ask me on Slack today?",
            "Post a status update in Slack about what I shipped today",
        ],
        "linear": [
            "What is on my plate in Linear this week?",
            "Which of my Linear issues are blocked?",
            "File a Linear issue for what I am working on",
        ],
        "gmail": [
            "What in my inbox needs a reply?",
            "Summarise my unread email",
            "Draft a reply to my latest email",
        ],
        "github": [
            "Which pull requests are waiting on my review?",
            "What failed in CI today?",
            "Summarise what merged this week",
        ],
        "notion": [
            "What changed in Notion this week?",
            "Find my latest notes in Notion",
            "Write today's progress into Notion",
        ],
        "googledocs": [
            "Which Google Docs were shared with me this week?",
            "Summarise the doc I opened last",
            "Draft a doc from what I worked on today",
        ],
    ]

    static func of(_ toolkit: String) -> [String] {
        if let known = asks[toolkit] { return known }
        let name = ToolkitName.of(toolkit)
        return ["What is new in \(name)?", "What needs me in \(name)?", "Summarise my week in \(name)"]
    }
}

/// One app up close in the notch: its logo lit in its own colour, how it stands, and the things to ask about it,
/// each a tap that starts the conversation as if it had been said.
struct IslandToolPage: View {
    let connection: ToolConnection
    let ask: (String) -> Void
    @State private var lit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let markSide: CGFloat = 54
        static let haloSide: CGFloat = 104
        static let haloBlur: CGFloat = 22
        static let haloRest = 0.35
        static let haloPeak = 0.7
        static let leftWidth: CGFloat = 132
        static let columnGap: CGFloat = 14
        static let nameSize: CGFloat = 15
        static let statusSize: CGFloat = 11
        static let dotSide: CGFloat = 6
        static let askHeight: CGFloat = 36
        static let askRadius: CGFloat = 11
        static let askSize: CGFloat = 12
        static let askSymbol: CGFloat = 11
        static let askSpacing: CGFloat = 6
        static let labelSize: CGFloat = 10
        static let hintSize: CGFloat = 10
        static let labelTracking: CGFloat = 0.6
        /// Lets a long ask shrink a little before it is cut.
        static let shrink: CGFloat = 0.85
        /// The logo sits a little above its halo, as an app icon sits on the Dock.
        static let markShadow = 0.4
        static let markShadowRadius: CGFloat = 8
        static let markShadowDrop: CGFloat = 4
        /// The halo breathes this slowly, so it reads as alive rather than as a warning.
        static let breath: TimeInterval = 2.4
    }

    private enum Symbol {
        static let ask = "arrow.up.right"
        static let talk = "waveform"
    }

    var body: some View {
        HStack(alignment: .center, spacing: Layout.columnGap) {
            identity.frame(width: Layout.leftWidth)
            VStack(alignment: .leading, spacing: Layout.askSpacing) {
                Text("ASK MEMNOX")
                    .font(.system(size: Layout.labelSize, weight: .semibold, design: .rounded))
                    .tracking(Layout.labelTracking)
                    .foregroundStyle(Color.white.opacity(NotchMetrics.captionInk))
                    .notchArrival(order: 0)
                ForEach(Array(ToolAsks.of(connection.toolkit).enumerated()), id: \.offset) { index, words in
                    askButton(words).notchArrival(order: index + 1)
                }
                hint.notchArrival(order: 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: Layout.breath).repeatForever(autoreverses: true)) { lit = true }
        }
    }

    private var tint: Color { ToolBrand.color(connection.toolkit) }

    private var identity: some View {
        VStack(spacing: Memnox.Spacing.small) {
            ZStack {
                Circle()
                    .fill(tint)
                    .frame(width: Layout.haloSide, height: Layout.haloSide)
                    .blur(radius: Layout.haloBlur)
                    .opacity(lit ? Layout.haloPeak : Layout.haloRest)
                ToolMark(toolkit: connection.toolkit, side: Layout.markSide)
                    .shadow(color: .black.opacity(Layout.markShadow), radius: Layout.markShadowRadius, y: Layout.markShadowDrop)
            }
            .frame(height: Layout.markSide + Memnox.Spacing.medium)
            .notchArrival(order: 0)
            Text(ToolkitName.of(connection.toolkit))
                .font(.system(size: Layout.nameSize, weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
            HStack(spacing: Memnox.Spacing.xSmall) {
                Circle()
                    .fill(connection.connected ? Memnox.Palette.success : IslandPalette.amber)
                    .frame(width: Layout.dotSide, height: Layout.dotSide)
                Text(connection.connected ? "Connected" : "Needs a sign in")
                    .font(.system(size: Layout.statusSize, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(NotchMetrics.captionInk))
            }
        }
    }

    private func askButton(_ words: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: Layout.askRadius, style: .continuous)
        return Button { ask(words) } label: {
            HStack(spacing: Memnox.Spacing.small) {
                Text(words)
                    .font(.system(size: Layout.askSize, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(Layout.shrink)
                Spacer(minLength: 0)
                Image(systemName: Symbol.ask)
                    .font(.system(size: Layout.askSymbol, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(NotchMetrics.symbolInk))
            }
            .padding(.horizontal, Memnox.Spacing.medium)
            .frame(height: Layout.askHeight)
            .background(Color.white.opacity(NotchMetrics.tileFill), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(NotchMetrics.tileRim), lineWidth: Memnox.Stroke.hairline))
            .contentShape(shape)
        }
        .buttonStyle(NotchPressStyle(cornerRadius: Layout.askRadius))
        .help("Ask \u{201C}\(words)\u{201D}")
        .accessibilityLabel("Ask Memnox: \(words)")
    }

    /// Anything else is a sentence away; a tool not signed in to opens its sign in once something is asked of it.
    private var hint: some View {
        HStack(spacing: Memnox.Spacing.xSmall) {
            Image(systemName: Symbol.talk).foregroundStyle(Memnox.Palette.sky)
            Text(connection.connected
                 ? "Or press \u{2325} Space and ask anything about \(ToolkitName.of(connection.toolkit))."
                 : "Ask anything and Memnox opens the sign in first.")
                .foregroundStyle(Color.white.opacity(NotchMetrics.captionInk))
                .lineLimit(1)
                .minimumScaleFactor(Layout.shrink)
        }
        .font(.system(size: Layout.hintSize, weight: .medium))
        .padding(.top, Memnox.Spacing.xSmall)
    }
}
