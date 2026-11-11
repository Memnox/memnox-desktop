import MemnoxVoiceCore
import SwiftUI

/// A radio mark, the same on both questions and the rule packs.
private struct RadioMark: View {
    let on: Bool

    private static let side: CGFloat = 16
    private static let ring: CGFloat = 2

    var body: some View {
        Circle()
            .strokeBorder(on ? Memnox.Console.primary : Memnox.ink(Memnox.Ink.tertiary), lineWidth: Self.ring)
            .background(Circle().fill(on ? Memnox.Console.primary : Color.clear))
            .frame(width: Self.side, height: Self.side)
            .accessibilityHidden(true)
    }
}

/// One answer of a question as a row that is pressed whole.
private struct AnswerRow: View {
    let symbol: String
    let title: String
    let detail: String
    let on: Bool
    var disabled = false
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            KitRow(symbol: symbol, title: title, detail: detail) { RadioMark(on: on) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHand()
        .disabled(disabled)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }
}

/// A line of what a press came to, in the quiet ink under the step.
private struct StepNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Memnox.sans(Memnox.TextSize.footnote))
            .foregroundStyle(Memnox.ink(Memnox.Ink.secondary))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The first question: who Memnox is for, which only picks where Where should Memnox ask you suggests first.
struct WhoStep: View {
    @ObservedObject var flow: OnboardingFlow

    var body: some View {
        StepTitle(title: FirstRunStepID.who.title, detail: "It only picks what is suggested next. You can change it later.")
        KitCard(symbol: "person.2", title: "Pick one") {
            ForEach(Array(FirstRunAudience.allCases.enumerated()), id: \.element.id) { index, audience in
                if index > 0 { KitDivider() }
                AnswerRow(symbol: Self.symbol(audience), title: audience.title, detail: audience.detail, on: flow.audience == audience) {
                    flow.audience = audience
                }
            }
        }
        .onAppear { if flow.audience == nil { flow.audience = .me } }
        Next(title: "Continue", flow: flow)
    }

    private static func symbol(_ audience: FirstRunAudience) -> String {
        switch audience {
        case .me: "person"
        case .away: "iphone"
        case .team: "person.3"
        }
    }
}

/// The second question: which agents the person runs and where. On this Mac the agents found are put under Memnox once
/// the service runs; anywhere else the agent reaches Memnox through Memnox Cloud, offered and never required.
struct AgentsStep: View {
    @ObservedObject var flow: OnboardingFlow

    var body: some View {
        StepTitle(title: FirstRunStepID.agents.title, detail: FirstRunQuestions.placeDetail)
        PlaceChoices(flow: flow, agents: AppWindow.shared.shell.agents)
    }
}

private struct PlaceChoices: View {
    @ObservedObject var flow: OnboardingFlow
    let agents: AgentsScreen?

    var body: some View {
        let found = agents?.agents.agents ?? []
        KitCard(symbol: "point.3.connected.trianglepath.dotted", title: FirstRunQuestions.placeTitle) {
            ForEach(Array(AgentPlace.allCases.enumerated()), id: \.element.id) { index, place in
                if index > 0 { KitDivider() }
                AnswerRow(symbol: Self.symbol(place), title: place.title, detail: place.detail, on: flow.place == place) {
                    flow.place = place
                }
            }
        }
        .onAppear { if flow.place == nil { flow.place = AgentPlace.suggested(foundHere: found.count) } }
        if let place = flow.place { answer(place, found: found) }
        Next(title: "Continue", flow: flow)
    }

    /// What the answer means: the agents found here, or how a remote agent connects.
    @ViewBuilder private func answer(_ place: AgentPlace, found: [AgentStanding]) -> some View {
        KitCard(symbol: place.isLocal ? "desktopcomputer" : "cloud", title: "How it reaches Memnox", detail: place.connects) {
            if place.isLocal {
                StepNote(text: found.isEmpty ? FirstRunQuestions.nothingFound : FirstRunLines.agentsFound(found))
            } else if place.throughCloud {
                StepNote(text: FirstRunQuestions.cloudOptional)
                if let account = flow.account { CloudOffer(account: account) }
            }
        }
    }

    private static func symbol(_ place: AgentPlace) -> String {
        switch place {
        case .thisMacCoding: "chevron.left.forwardslash.chevron.right"
        case .thisMacApp: "macwindow"
        case .hosted: "server.rack"
        case .insideApp: "app.connected.to.app.below.fill"
        case .noCode: "square.grid.3x3"
        case .ownCode: "curlybraces"
        case .noneYet: "sparkles"
        }
    }
}

/// The fourth step: where Memnox asks. Touch ID here is always on; the phone and Memnox Cloud are each one press, the
/// one suggested by who Memnox is for listed first, and both can wait.
struct AskWhereStep: View {
    @ObservedObject var flow: OnboardingFlow
    @ObservedObject var setup: SetupModel

    var body: some View {
        let first = flow.audience?.suggested ?? .here
        let routes = [first] + FirstRunAskRoute.allCases.filter { $0 != first }
        StepTitle(title: FirstRunStepID.askWhere.title, detail: "When an agent needs a yes, Memnox asks you there first. You can add the rest later.")
        KitCard(symbol: "bell.badge", title: "Ask me") {
            ForEach(Array(routes.enumerated()), id: \.element.rawValue) { index, route in
                if index > 0 { KitDivider() }
                KitRow(symbol: Self.symbol(route), title: route.title, detail: route.detail) { trailing(route) }
            }
        }
        Next(title: "Continue", flow: flow)
    }

    @ViewBuilder private func trailing(_ route: FirstRunAskRoute) -> some View {
        switch route {
        case .here:
            CheckBox(state: setup.key == .done ? .done : .waiting)
        case .phone:
            if case .paired = setup.phone {
                CheckBox(state: .done)
            } else {
                Button("Pair", systemImage: "qrcode") {
                    SettingsWindow.shared.show()
                    AppWindow.shared.shell.go(WindowRoute(.settings, tab: "phones"))
                }
                .buttonStyle(KitButton(kind: .secondary))
            }
        case .cloud:
            if let account = flow.account { CloudOffer(account: account) }
        }
    }

    private static func symbol(_ route: FirstRunAskRoute) -> String {
        switch route {
        case .here: "touchid"
        case .phone: "iphone"
        case .cloud: "building.2"
        }
    }
}

/// Signing in to Memnox Cloud, offered where it is the way an agent connects and never needed to go on.
struct CloudOffer: View {
    @ObservedObject var account: AccountModel

    var body: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            switch account.step {
            case .signedIn(let name, _):
                CheckBox(state: .done)
                StepNote(text: "Signed in as \(name).")
            case .showingCode(let code):
                StepNote(text: "Approve \(code) on the page that opened, or press Cancel and go on.")
                Button("Cancel") { account.cancel() }.buttonStyle(KitButton(kind: .secondary))
            case .starting:
                ProgressView().controlSize(.small)
                Button("Cancel") { account.cancel() }.buttonStyle(KitButton(kind: .secondary))
            case .failed(let why):
                StepNote(text: why)
                Button("Try again") { account.start() }.buttonStyle(KitButton(kind: .secondary))
            case .signedOut:
                Button("Sign in to Memnox Cloud", systemImage: "person.crop.circle") { account.start() }
                    .buttonStyle(KitButton(kind: .secondary))
                StepNote(text: "Optional")
            }
        }
        .padding(.top, Memnox.Spacing.regular)
    }
}
