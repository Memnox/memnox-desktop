import MemnoxVoiceCore
import SwiftUI

/// The first run's window, in the Memnox window's own look: a stepper across the top naming every step, the step on
/// the left with the one button that moves on, the real notch playing in a bordered panel to its right, and Back with
/// the sound controls at the foot. No rule divides the parts; space and the panel's edge do.
struct OnboardingCard: View {
    @ObservedObject var flow: OnboardingFlow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let side: CGFloat = 40
        static let top: CGFloat = 28
        static let columnWidth: CGFloat = 440
        static let gap: CGFloat = 40
        static let footerHeight: CGFloat = 56
        /// The panel the notch plays in stands this far inside the window's edge.
        static let artInset: CGFloat = 8
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingStepper(flow: flow)
                .padding(.horizontal, Layout.side)
                .padding(.top, Layout.top)
            if let setup = flow.setup {
                HStack(alignment: .center, spacing: Layout.gap) {
                    CuedScroll {
                        OnboardingStepView(flow: flow, setup: setup)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Layout.top)
                    }
                    .frame(width: Layout.columnWidth)
                    .id(flow.page)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                    // Outside the step's identity, so the notch plays on rather than starting over at every step.
                    OnboardingArt(highlighted: { flow.highlight = $0 }, jump: flow.jump)
                        .padding(Layout.artInset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Memnox.Console.card, in: RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
                            .strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
                        .padding(.vertical, Layout.top)
                        // The landscape overflows its clip and SwiftUI hit tests the overflow, so without this the
                        // picture lies over the step's buttons and takes their clicks.
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, Layout.side)
                .modifier(OnboardingNarration(flow: flow, setup: setup))
            }
            footer
        }
        .background(Memnox.Console.background)
        .consoleLook()
        .animation(reduceMotion ? .easeInOut(duration: Memnox.Motion.standard) : .spring(response: 0.5, dampingFraction: 0.88), value: flow.page)
        .task(id: flow.setup.map(ObjectIdentifier.init)) { await flow.setup?.check() }
    }

    /// Back on the left; on the right where all of this can be changed later, and the music and the voice.
    private var footer: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            if flow.step != .connect || flow.ready {
                Button("Back", systemImage: "chevron.left") { flow.back() }
                    .buttonStyle(KitButton(kind: .secondary))
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            Text("You can change all of this later in Settings.")
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                .foregroundStyle(Memnox.Console.faint)
            AmbienceButton()
            MuteButton()
        }
        .frame(height: Layout.footerHeight)
        .padding(.horizontal, Layout.side)
        .padding(.bottom, Memnox.Spacing.medium)
    }
}

/// The three steps as numbered marks joined by a line, as a stepper reads: a done step is a blue mark with a tick, the
/// step on screen a blue ring around its number with its name in full ink, and what is left an outline. Step N of 3
/// stands at the end, so a new person always sees where they are and how much is left.
private struct OnboardingStepper: View {
    @ObservedObject var flow: OnboardingFlow

    private enum Layout {
        static let mark: CGFloat = 22
        static let ring: CGFloat = 1.5
        static let line: CGFloat = 1.5
        static let lineMin: CGFloat = 16
        static let tick: CGFloat = 9
    }

    private enum State {
        case done
        case here
        case ahead
    }

    var body: some View {
        // Every name where the window has room, and only the one on screen where it does not.
        ViewThatFits(in: .horizontal) {
            row(everyName: true)
            row(everyName: false)
        }
    }

    private func row(everyName: Bool) -> some View {
        HStack(spacing: Memnox.Spacing.medium) {
            ForEach(OnboardingStep.allCases) { step in
                let state = state(of: step)
                mark(String(step.rawValue + 1), state)
                if everyName || state == .here { name(step.title, state) }
                if step != OnboardingStep.allCases.last { line(lit: state == .done) }
            }
            Spacer(minLength: Memnox.Spacing.large)
            Text(flow.ready ? "Done" : FirstRunLines.progressLabel(step: flow.step.rawValue))
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium))
                .foregroundStyle(Memnox.Console.muted)
                .fixedSize()
        }
        .animation(.easeOut(duration: Memnox.Motion.quick), value: flow.page)
        .accessibilityElement()
        .accessibilityLabel(flow.ready ? "Three steps done, the rest is optional"
            : "\(FirstRunLines.progressLabel(step: flow.step.rawValue)), \(flow.step.title)")
    }

    private func state(of step: OnboardingStep) -> State {
        if flow.ready || step.rawValue < flow.step.rawValue { return .done }
        return step == flow.step ? .here : .ahead
    }

    private func mark(_ number: String, _ state: State) -> some View {
        ZStack {
            switch state {
            case .done:
                Circle().fill(Memnox.Console.primary)
                Image(systemName: "checkmark").font(.system(size: Layout.tick, weight: .bold)).foregroundStyle(Color.white)
            case .here:
                Circle().fill(Memnox.Console.primary.opacity(Memnox.Ink.faintFill))
                Circle().strokeBorder(Memnox.Console.primary, lineWidth: Layout.ring)
                Text(number).font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .semibold)).foregroundStyle(Memnox.Console.foreground)
            case .ahead:
                Circle().strokeBorder(Memnox.Console.panelEdge, lineWidth: Layout.ring)
                Text(number).font(Memnox.Console.sans(Memnox.Console.TextSize.meta, .medium)).foregroundStyle(Memnox.Console.faint)
            }
        }
        .frame(width: Layout.mark, height: Layout.mark)
    }

    private func name(_ title: String, _ state: State) -> some View {
        Text(title)
            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, state == .here ? .medium : .regular))
            .foregroundStyle(state == .ahead ? Memnox.Console.faint : state == .here ? Memnox.Console.foreground : Memnox.Console.muted)
            .lineLimit(1)
            .fixedSize()
    }

    private func line(lit: Bool) -> some View {
        Capsule()
            .fill(lit ? Memnox.Console.primary : Memnox.Console.panelEdge)
            .frame(minWidth: Layout.lineMin, maxWidth: .infinity)
            .frame(height: Layout.line)
    }
}

/// The left column of each step: its title, what it means, and the controls that turn it on.
private struct OnboardingStepView: View {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xxLarge) {
            if flow.ready {
                ReadyStep(flow: flow, setup: setup)
            } else {
                switch flow.step {
                case .connect: ConnectStep(flow: flow, setup: setup)
                case .workspace: WorkspaceStep(flow: flow)
                case .boundaries: BoundariesStep(flow: flow)
                }
            }
        }
    }
}

/// A step's title and the line under it, large, as the first thing read.
struct StepTitle: View {
    let title: String
    let detail: String

    private static let titleSize: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            Text(title)
                .font(Memnox.display(Self.titleSize, .semibold))
                .foregroundStyle(Memnox.Console.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(Memnox.sans(Memnox.TextSize.headline))
                .foregroundStyle(Memnox.Console.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A column that scrolls and says so: the scroller stays visible, the edges fade where there is more, and a pill at
/// the foot reads More below and takes the person there, so nothing past the fold goes unseen.
private struct CuedScroll<Content: View>: View {
    @ViewBuilder let content: () -> Content
    /// Only the two edges are kept, not the offset, so a scroll tick changes nothing and redraws nothing until an
    /// edge is reached; keeping the offset rebuilt the mask on every tick and made the column stutter.
    @State private var moreAbove = false
    @State private var moreBelow = false
    @State private var viewport: CGFloat = 0
    /// The last frame scrolled, held outside state so remembering it costs no redraw.
    @State private var scrolled = Scrolled()

    private static var space: String { "cued" }
    private static var end: String { "end" }
    private static var fade: CGFloat { 36 }
    private static var gutter: CGFloat { 18 }
    /// Within this much of an edge counts as at it, so a pixel of rounding never leaves a cue showing.
    private static var slack: CGFloat { 6 }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(spacing: 0) {
                    content()
                    Color.clear.frame(height: 1).id(Self.end)
                }
                // Room on the right for the scroller, so it never runs over a card's edge.
                .padding(.trailing, Self.gutter)
                .background(GeometryReader { inside in
                    Color.clear.preference(key: CuedFrame.self, value: inside.frame(in: .named(Self.space)))
                })
            }
            .coordinateSpace(name: Self.space)
            .scrollIndicators(.visible)
            .background(GeometryReader { outside in
                Color.clear
                    .onAppear { viewport = outside.size.height; cue() }
                    .onChange(of: outside.size.height) { _, height in viewport = height; cue() }
            })
            .onPreferenceChange(CuedFrame.self) { frame in
                scrolled.frame = frame
                cue()
            }
            .mask(edges)
            .overlay(alignment: .bottom) {
                if moreBelow {
                    Button("More below", systemImage: "chevron.down") {
                        withAnimation(.easeInOut(duration: Memnox.Motion.standard)) { reader.scrollTo(Self.end, anchor: .bottom) }
                    }
                    .buttonStyle(KitButton(kind: .secondary))
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                    .padding(.bottom, Memnox.Spacing.medium)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeOut(duration: Memnox.Motion.quick), value: moreBelow)
        }
    }

    /// Reads the two edges from the last frame and writes only what changed, so a scroll tick redraws nothing.
    private func cue() {
        let frame = scrolled.frame
        let above = -frame.minY > Self.slack
        let below = frame.height + frame.minY - viewport > Self.slack
        if above != moreAbove { moreAbove = above }
        if below != moreBelow { moreBelow = below }
    }

    /// Solid where the column ends, faded where more of it waits past the edge.
    private var edges: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [moreAbove ? .clear : .black, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.fade)
            Color.black
            LinearGradient(colors: [.black, moreBelow ? .clear : .black], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.fade)
        }
    }
}

/// The last scrolled frame, a reference so writing it never asks SwiftUI to redraw.
private final class Scrolled {
    var frame: CGRect = .zero
}

/// The scrolled content's frame, read in the column's own space so its top says how far it has scrolled.
private struct CuedFrame: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
