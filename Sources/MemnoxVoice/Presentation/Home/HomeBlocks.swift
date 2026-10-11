import MemnoxVoiceCore
import SwiftUI

/// The five blocks of the home, the same on the Mac, the iPhone and `memnox status`: what waits on the person, what
/// is working, today in plain words, the one thing that could run on its own, and what nothing covers. Counts only.
struct HomeBlocks: View {
    @ObservedObject var model: HomeModel

    var body: some View {
        if let home = model.home {
            VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
                HomeWaitingBlock(count: home.waiting, open: model.openWaiting)
                HomeWorkingBlock(working: home.working, open: model.openSession)
                HomeBlock(title: "Today") {
                    HomeLine(HomeLines.today(home.today))
                }
                if let ready = home.ready {
                    HomeReadyCard(ready: ready, busy: model.handingOver, note: model.handOverNote) { model.handOver(ready) }
                }
                HomeNotCoveredBlock(notCovered: home.notCovered, model: model)
            }
            .animation(.easeOut(duration: Memnox.Motion.standard), value: home)
        }
    }
}

/// A block's quiet heading over its own surface.
private struct HomeBlock<Content: View>: View {
    let title: String
    var accent: Color?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            MenuHeading(title: title)
            VStack(alignment: .leading, spacing: Memnox.Spacing.medium) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Memnox.Spacing.xLarge)
                .surface(accent: accent)
        }
    }
}

/// One line of the home in body text.
private struct HomeLine: View {
    let text: String
    var ink = Memnox.Ink.primary

    init(_ text: String, ink: Double = Memnox.Ink.primary) {
        self.text = text
        self.ink = ink
    }

    var body: some View {
        Text(text)
            .font(Memnox.sans(Memnox.TextSize.body))
            .foregroundStyle(Memnox.ink(ink))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// How many calls wait, and the way to them: the island, where each is answered.
private struct HomeWaitingBlock: View {
    let count: Int
    let open: () -> Void

    var body: some View {
        HomeBlock(title: "Waiting on you", accent: nil) {
            HStack(spacing: Memnox.Spacing.medium) {
                Text("\(count)")
                    .font(Memnox.sans(Memnox.TextSize.title, .semibold).monospacedDigit())
                    .foregroundStyle(Memnox.Palette.ink)
                    .contentTransition(.numericText(value: Double(count)))
                HomeLine(HomeLines.waiting(count), ink: Memnox.Ink.secondary)
                Spacer(minLength: 0)
                if count > 0 {
                    Button("Answer", action: open)
                        .buttonStyle(KitButton(kind: .secondary))
                        .help("Open the waiting calls on the island")
                }
            }
        }
    }
}

/// Each agent at work now, by name, with its task and where; a click opens the live window on it.
private struct HomeWorkingBlock: View {
    let working: [HomeWorking]
    let open: (HomeWorking) -> Void

    var body: some View {
        HomeBlock(title: "Working now") {
            if working.isEmpty {
                HomeLine("Nothing is working right now.", ink: Memnox.Ink.secondary)
            } else {
                ForEach(working) { session in
                    Button { open(session) } label: {
                        HStack(spacing: Memnox.Spacing.medium) {
                            BrandLogo(agent: session.agent, name: session.agentName, size: Layout.logo)
                                .overlay(alignment: .bottomTrailing) {
                                    Circle().fill(IslandPalette.green)
                                        .frame(width: Layout.dot, height: Layout.dot)
                                        .overlay(Circle().strokeBorder(Memnox.Palette.surface, lineWidth: 2))
                                        .offset(x: 2, y: 2)
                                }
                            VStack(alignment: .leading, spacing: MenuLayout.titleDetailSpacing) {
                                Text(session.agentName)
                                    .font(Memnox.sans(Memnox.TextSize.body, .semibold))
                                    .foregroundStyle(Memnox.Palette.ink)
                                Text(HomeLines.working(session))
                                    .font(Memnox.sans(Memnox.TextSize.footnote))
                                    .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: MenuSymbol.more)
                                .font(.system(size: Memnox.TextSize.caption, weight: .semibold))
                                .foregroundStyle(Memnox.ink(MenuLayout.dimInk))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(MenuPress())
                    .help("Watch \(session.agentName) live")
                }
            }
        }
    }

    private enum Layout {
        static let dot: CGFloat = 9
        static let logo: CGFloat = 32
    }
}

/// The one action people keep saying yes to: the question, what it would cover, and the button that proposes the rule.
private struct HomeReadyCard: View {
    let ready: HomeReady
    let busy: Bool
    let note: String?
    let handOver: () -> Void

    var body: some View {
        HomeBlock(title: "Ready to hand over", accent: nil) {
            Text(HomeLines.ready(ready))
                .font(Memnox.sans(Memnox.TextSize.headline, .semibold))
                .foregroundStyle(Memnox.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !ready.targets.isEmpty {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    ForEach(ready.targets, id: \.self) { target in
                        Text(target)
                            .font(.system(size: Memnox.TextSize.footnote, design: .monospaced))
                            .foregroundStyle(Memnox.ink(Memnox.Ink.primary))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            HomeLine(ready.because, ink: Memnox.Ink.secondary)
            HStack(spacing: Memnox.Spacing.medium) {
                Button(busy ? "Proposing the rule" : "Let it run on its own", action: handOver)
                    .buttonStyle(KitButton(kind: .primary))
                    .disabled(busy)
                    .help("Proposes an allow rule for exactly these; nothing changes until you confirm it with Touch ID")
                if let note { HomeLine(note, ink: Memnox.Ink.secondary) }
            }
        }
    }
}

/// What nothing covers, as counts, and the one press that puts the agents found here under Memnox.
private struct HomeNotCoveredBlock: View {
    let notCovered: HomeNotCovered
    @ObservedObject var model: HomeModel

    var body: some View {
        HomeBlock(title: "Not covered", accent: nil) {
            ForEach(HomeLines.notCovered(notCovered), id: \.self) { line in
                HomeLine(line, ink: notCovered == HomeNotCovered(unprotected: 0, dormant: 0) ? Memnox.Ink.secondary : Memnox.Ink.primary)
            }
            if notCovered.unprotected > 0 {
                if model.remote() {
                    // The button runs this Mac's own memnox, which cannot reach a server's agents.
                    HomeLine("Run memnox setup on that server to put them under Memnox.", ink: Memnox.Ink.secondary)
                } else {
                    HStack(spacing: Memnox.Spacing.medium) {
                        Button(model.protecting ? "Protecting your agents" : "Protect my agents", action: model.protect)
                            .buttonStyle(KitButton(kind: .primary))
                            .disabled(model.protecting)
                            .help("Hooks every agent found on this Mac into Memnox, the way setup does")
                        if let why = model.protectFailed { HomeLine(why, ink: Memnox.Ink.secondary) }
                    }
                }
            }
        }
    }
}
