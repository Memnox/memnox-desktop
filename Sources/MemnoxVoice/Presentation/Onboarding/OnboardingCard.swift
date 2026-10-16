import SwiftUI

/// The first run's window: a progress bar across the top, the step on the left with the one button that moves on,
/// the real notch playing what Memnox does to its right through every step, and Back at the foot.
struct OnboardingCard: View {
    @ObservedObject var flow: OnboardingFlow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let side: CGFloat = 56
        static let top: CGFloat = 36
        static let barHeight: CGFloat = 4
        static let columnWidth: CGFloat = 440
        static let gap: CGFloat = 48
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                progress
                stepNames
            }
            .padding(.horizontal, Layout.side / 2)
            .padding(.top, Layout.top / 2)
            if let setup = flow.setup {
                HStack(alignment: .center, spacing: Layout.gap) {
                    CuedScroll {
                        OnboardingStepView(flow: flow, setup: setup)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, Layout.top)
                    }
                    .frame(width: Layout.columnWidth)
                    .id(flow.step)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                    // Outside the step's identity, so the notch plays on rather than starting over at every step.
                    OnboardingArt(highlighted: { flow.highlight = $0 }, jump: flow.jump)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .background(Memnox.Palette.background)
        .animation(reduceMotion ? .easeInOut(duration: Memnox.Motion.standard) : .spring(response: 0.5, dampingFraction: 0.88), value: flow.step)
        .task(id: flow.setup.map(ObjectIdentifier.init)) { await flow.setup?.check() }
    }

    /// How far through the steps, in ink, so the one colour on the page is the picture.
    private var progress: some View {
        GeometryReader { space in
            let share = CGFloat(flow.step.rawValue + 1) / CGFloat(OnboardingStep.allCases.count)
            ZStack(alignment: .leading) {
                Capsule().fill(Memnox.ink(Memnox.Ink.fill))
                Capsule()
                    .fill(Memnox.ink(Memnox.Ink.primary))
                    .frame(width: space.size.width * share)
            }
        }
        .frame(height: Layout.barHeight)
        .accessibilityElement()
        .accessibilityLabel("Step \(flow.step.rawValue + 1) of \(OnboardingStep.allCases.count), \(flow.step.title)")
    }

    /// Every step by name, the current one in full ink and the ones done ticked, under the bar.
    private var stepNames: some View {
        HStack(spacing: Memnox.Spacing.xLarge) {
            ForEach(OnboardingStep.allCases) { step in
                HStack(spacing: Memnox.Spacing.xSmall) {
                    if step.rawValue < flow.step.rawValue {
                        Image(systemName: "checkmark").font(.system(size: Memnox.TextSize.micro, weight: .bold))
                    }
                    Text(step.title)
                }
                .font(Memnox.sans(Memnox.TextSize.footnote, step == flow.step ? .semibold : .regular))
                .foregroundStyle(Memnox.ink(step == flow.step ? Memnox.Ink.primary : Memnox.Ink.tertiary))
            }
        }
        .accessibilityHidden(true)
    }

    private var footer: some View {
        HStack {
            if flow.step != .welcome {
                Button("Back", systemImage: "chevron.left") { flow.back() }
                    .buttonStyle(KitButton(kind: .secondary))
                    .keyboardShortcut(.cancelAction)
            }
            Spacer()
            MuteButton()
            Text("You can change all of this later in Settings.")
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.ink(Memnox.Ink.tertiary))
        }
        .frame(height: Card.footerHeight)
        .padding(.horizontal, Layout.side / 2)
        .padding(.bottom, Memnox.Spacing.large)
    }

    private enum Card {
        static let footerHeight: CGFloat = 44
    }
}

/// The left column of each step: its title, what it means, and the controls that turn it on.
private struct OnboardingStepView: View {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var setup: SetupModel

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xxLarge) {
            switch flow.step {
            case .welcome: WelcomeStep(flow: flow)
            case .setup: ThisMacStep(flow: flow, setup: setup)
            case .ready: ReadyStep(flow: flow, setup: setup)
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
                .foregroundStyle(Memnox.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(detail)
                .font(Memnox.sans(Memnox.TextSize.headline))
                .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
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
