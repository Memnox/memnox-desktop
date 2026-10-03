import AppKit
import MemnoxVoiceCore
import SwiftUI

/// What the switcher shows: the sessions as cards, which one is in front, and how far along it is.
@MainActor
final class SwitcherModel: ObservableObject {
    @Published var cards: [SessionCard] = []
    /// Fractional while it turns, so the cards swing smoothly between places.
    @Published var selected: Double = 0
    @Published var shown = false
    /// The chosen card coming forward before it becomes the window it opens into.
    @Published var chosen = false
    var picked: ((SessionCard) -> Void)?
}

/// The sessions as cards standing in a row in 3D, turned at an angle like records on a shelf,
/// which turn past until the one asked for faces the person, then comes forward and opens.
@MainActor
final class SwitcherPanel {
    private let panel: KeyablePanel
    private let model = SwitcherModel()
    /// A beat per card, quick enough that several pass in about a second.
    private static let stepSeconds = 0.16
    private static let holdSeconds = 0.45

    init() {
        panel = KeyablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
    }

    /// Turns through the cards to the session asked for, and returns once it has come forward.
    func turn(to sessionId: String, among cards: [SessionCard]) async {
        guard let target = cards.firstIndex(where: { $0.sessionId == sessionId }), cards.count > 1,
              let screen = NSScreen.main
        else { return }
        model.cards = cards
        model.chosen = false
        // Starts across the row from the one asked for, so the turn has somewhere to travel.
        let start = target < cards.count / 2 ? cards.count - 1 : 0
        model.selected = Double(start)
        panel.setFrame(screen.frame, display: false)
        panel.contentView = NSHostingView(rootView: SwitcherView(model: model))
        panel.orderFrontRegardless()
        withAnimation(.easeOut(duration: 0.3)) { model.shown = true }
        try? await Task.sleep(nanoseconds: 280_000_000)
        let steps = abs(target - start)
        withAnimation(.spring(response: Self.stepSeconds * Double(steps) + 0.35, dampingFraction: 0.82)) {
            model.selected = Double(target)
        }
        try? await Task.sleep(nanoseconds: UInt64((Self.stepSeconds * Double(steps) + Self.holdSeconds) * 1_000_000_000))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { model.chosen = true }
        try? await Task.sleep(nanoseconds: 380_000_000)
        withAnimation(.easeIn(duration: 0.25)) { model.shown = false }
        Task { [panel] in
            try? await Task.sleep(nanoseconds: 260_000_000)
            panel.orderOut(nil)
            panel.contentView = nil
        }
    }
}

private struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel

    var body: some View {
        ZStack {
            // The rest of the screen falls back, so the row is the only thing to look at.
            Color.black.opacity(model.shown ? 0.38 : 0).ignoresSafeArea()
            ZStack {
                ForEach(Array(model.cards.enumerated()), id: \.element.id) { index, card in
                    let offset = Double(index) - model.selected
                    SessionTile(card: card, front: abs(offset) < 0.5)
                        .modifier(Shelf(offset: offset, chosen: model.chosen && abs(offset) < 0.5))
                }
            }
            .offset(y: model.shown ? -30 : 40)
            .opacity(model.shown ? 1 : 0)
        }
    }
}

/// Where a card stands on the shelf: the one in front faces the person, the rest turn away
/// at an angle and step back, and the chosen one comes forward out of the row.
private struct Shelf: ViewModifier {
    let offset: Double
    let chosen: Bool

    func body(content: Content) -> some View {
        let side = max(-1, min(1, offset))
        let distance = abs(offset)
        content
            .rotation3DEffect(.degrees(-side * 52), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            .scaleEffect(chosen ? 1.18 : 1 - min(distance, 3) * 0.1)
            .offset(x: offset * 150 + side * 70, y: chosen ? -20 : 0)
            .opacity(distance > 3.4 ? 0 : 1)
            .brightness(chosen ? 0.06 : -min(distance, 3) * 0.08)
            .zIndex(-distance)
    }
}

/// One session as a card: where it runs, who it is, what it is on and how it stands.
private struct SessionTile: View {
    let card: SessionCard
    let front: Bool

    var body: some View {
        VStack(spacing: 0) {
            face
            // The card reflected in the glass it stands on.
            face
                .scaleEffect(x: 1, y: -1, anchor: .center)
                .opacity(0.16)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .center))
                .frame(height: 90, alignment: .top)
                .clipped()
                .offset(y: 4)
        }
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppIcon(path: card.host?.appPath)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.agentName)
                        .font(Memnox.display(20))
                        .foregroundStyle(Memnox.Palette.foreground)
                    Text(card.runningIn ?? "Somewhere unknown")
                        .font(Memnox.sans(11))
                        .foregroundStyle(Memnox.Palette.muted)
                }
            }
            Text(card.task ?? "No task recorded")
                .font(Memnox.sans(13))
                .foregroundStyle(Memnox.Palette.foreground.opacity(0.9))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack {
                Circle().fill(colour).frame(width: 7, height: 7)
                Text(label).font(Memnox.sans(11, .medium)).foregroundStyle(colour)
                Spacer()
                if let repository = card.repository {
                    Text(repository).font(Memnox.sans(11)).foregroundStyle(Memnox.Palette.muted).lineLimit(1)
                }
            }
        }
        .padding(18)
        .frame(width: 240, height: 300)
        .background(
            ZStack {
                Glass(material: .hudWindow, cornerRadius: 16)
                Memnox.Palette.background.opacity(0.4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(front ? colour.opacity(0.8) : Color.white.opacity(0.12), lineWidth: front ? 1.5 : 1)
        )
        .shadow(color: front ? colour.opacity(0.45) : .black.opacity(0.4), radius: front ? 22 : 14, y: 10)
    }

    private var label: String {
        if card.thinking { return "Thinking" }
        switch card.state {
        case "working": return "Working"
        case "open": return "Waiting on you"
        case "paused": return "Paused"
        case "ended": return "Ended"
        default: return "Quiet"
        }
    }

    private var colour: Color {
        switch card.state {
        case "working": return Memnox.Palette.success
        case "open": return Memnox.Palette.warm
        case "paused": return Memnox.Palette.destructive
        default: return card.thinking ? Memnox.Palette.success : Memnox.Palette.muted
        }
    }
}

/// The app the session runs in, by its own icon, which is how a person tells iTerm from VS Code at a glance.
private struct AppIcon: View {
    let path: String?

    var body: some View {
        if let path {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 36, height: 36)
        } else {
            Image(systemName: "terminal")
                .font(.system(size: 22))
                .foregroundStyle(Memnox.Palette.muted)
                .frame(width: 36, height: 36)
        }
    }
}
