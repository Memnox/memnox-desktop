import SwiftUI

/// The opening over the whole screen: the wordmark glowing on a dark veil with one button, then the name asked in the
/// middle of the screen, with Skip intro in the corner for somebody who has seen it before.
struct OnboardingIntro: View {
    @ObservedObject var flow: OnboardingFlow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let veilInk = 0.58
        static let wordmarkHeight: CGFloat = 92
        static let glowRadius: CGFloat = 28
        static let glowOpacity = 0.55
        static let sheenRadius: CGFloat = 6
        static let sheenOpacity = 0.6
        static let gap: CGFloat = 44
        static let cornerPadding: CGFloat = 28
    }

    var body: some View {
        ZStack {
            Glass(material: .fullScreenUI)
            Color.black.opacity(Layout.veilInk)
            switch flow.stage {
            case .intro: opening.transition(.opacity.combined(with: .scale(scale: 0.96)))
            case .name, .steps: NameQuestion(flow: flow).transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            Button("Skip intro", systemImage: "forward.end") { flow.openSteps() }
                .buttonStyle(.plain)
                .pointingHand()
                .font(Memnox.sans(Memnox.TextSize.callout, .medium))
                .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                .padding(Layout.cornerPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85), value: flow.stage)
    }

    private var opening: some View {
        VStack(spacing: Layout.gap) {
            Wordmark(height: Layout.wordmarkHeight)
                .shadow(color: Color.white.opacity(Layout.sheenOpacity), radius: Layout.sheenRadius)
                .shadow(color: Color.white.opacity(Layout.glowOpacity), radius: Layout.glowRadius)
            Button { flow.stage = .name } label: {
                HStack(spacing: Memnox.Spacing.small) {
                    Text("Get Started")
                    Image(systemName: "arrow.right")
                }
            }
                .buttonStyle(KitButton(kind: .glass))
                .keyboardShortcut(.defaultAction)
        }
    }
}

/// What the person would like to be called, asked the way a person would ask it, kept the moment it is sent.
private struct NameQuestion: View {
    @ObservedObject var flow: OnboardingFlow
    @State private var name = ""
    @FocusState private var focused: Bool

    private enum Layout {
        static let lineSize: CGFloat = 30
        static let fieldWidth: CGFloat = 420
        static let fieldHeight: CGFloat = 52
        static let fieldFill = 0.14
        static let sendSide: CGFloat = 34
        static let gap: CGFloat = 40
    }

    var body: some View {
        VStack(spacing: Layout.gap) {
            VStack(spacing: Memnox.Spacing.large) {
                Text("Welcome to Memnox. I'm the voice over your agents.")
                Text("So, what should I call you?")
            }
            .font(Memnox.display(Layout.lineSize, .medium))
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            HStack(spacing: Memnox.Spacing.medium) {
                TextField("", text: $name, prompt: Text("Your name").foregroundStyle(Color.white.opacity(Memnox.Ink.secondary)))
                    .textFieldStyle(.plain)
                    .font(Memnox.sans(Memnox.TextSize.title))
                    .foregroundStyle(Color.white)
                    .focused($focused)
                    .accessibilityLabel("Your name")
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: Memnox.TextSize.callout, weight: .bold))
                        .frame(width: Layout.sendSide, height: Layout.sendSide)
                        .foregroundStyle(trimmed.isEmpty ? Color.white : Color.black)
                        .background(Circle().fill(trimmed.isEmpty ? Color.white.opacity(Memnox.Ink.fill) : Color.white))
                }
                .buttonStyle(.plain)
                .pointingHand()
                .disabled(trimmed.isEmpty)
                .accessibilityLabel("Continue")
            }
            .padding(.leading, Memnox.Spacing.xxLarge)
            .padding(.trailing, Memnox.Spacing.medium)
            .frame(width: Layout.fieldWidth, height: Layout.fieldHeight)
            .background(Capsule().fill(Color.white.opacity(Layout.fieldFill)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(Memnox.Ink.edge), lineWidth: Memnox.Stroke.hairline))
        }
        .onAppear {
            name = flow.setup?.name ?? ""
            focused = true
            // The first thing heard, so the voice is there from the start rather than from the second screen.
            flow.setup?.guide(GuideLines.askName)
        }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    private func send() {
        guard !trimmed.isEmpty, let setup = flow.setup else { return }
        setup.name = trimmed
        setup.saveName()
        flow.openSteps()
    }
}
