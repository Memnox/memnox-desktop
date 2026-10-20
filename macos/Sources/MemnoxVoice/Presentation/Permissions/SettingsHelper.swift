import AppKit
import SwiftUI

/// What the helper under System Settings shows: the pane, whether the app is being dragged, and whether the grant
/// has landed.
@MainActor
final class SettingsHelperModel: ObservableObject {
    @Published var pane: SettingsPane = .typing
    @Published var dragging = false
    @Published var granted = false
    var close: () -> Void = {}
    var dragged: (Bool) -> Void = { _ in }
}

/// Docks under System Settings while Memnox waits on a grant there, so the person never has to hold our steps in mind
/// while they look at Settings: what to switch, and the app itself to drag into the list when it is not there yet.
/// It watches for the grant and leaves on its own once it lands, or when Settings quits.
@MainActor
enum SettingsHelper {
    private static let model = SettingsHelperModel()
    private static var panel: SettingsHelperPanel?
    private static let tracker = SettingsWindowTracker()
    private static var watching: Task<Void, Never>?
    /// The pointer when the pane was asked for, which the panel flies in from.
    private static var launchedFrom: CGPoint = .zero

    /// How often the grant is looked for, the same pace as the setup rows.
    private static let checkEvery: TimeInterval = 1
    /// Long enough to read that it worked before the panel goes.
    private static let doneShown: TimeInterval = 1.4

    private static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Shows the helper for this pane once Settings has a window, flown in from where the pointer is now.
    static func present(for pane: SettingsPane) {
        guard !pane.isGranted else { return }
        let panel = panel ?? makePanel()
        model.pane = pane
        model.granted = false
        model.dragging = false
        launchedFrom = NSEvent.mouseLocation
        var arrived = false
        tracker.moved = { frame in
            if arrived {
                panel.follow(frame)
            } else {
                arrived = true
                panel.present(under: frame, from: launchedFrom, reduceMotion: reduceMotion)
            }
        }
        tracker.ended = { dismiss() }
        tracker.start()
        watch(pane)
    }

    static func dismiss() {
        watching?.cancel()
        watching = nil
        tracker.stop()
        panel?.leave(reduceMotion: reduceMotion)
    }

    private static func makePanel() -> SettingsHelperPanel {
        model.close = { dismiss() }
        let panel = SettingsHelperPanel(content: SettingsHelperView(model: model, app: Bundle.main.bundleURL))
        panel.touched = { SettingsWindowTracker.settings?.activate() }
        model.dragged = { [weak panel] on in
            model.dragging = on
            panel?.dragging(on)
        }
        self.panel = panel
        return panel
    }

    /// Looks for the grant until it lands, then says so and goes.
    private static func watch(_ pane: SettingsPane) {
        watching?.cancel()
        watching = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(checkEvery * Double(NSEC_PER_SEC)))
                guard !Task.isCancelled, pane.isGranted else { continue }
                withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.7)) { model.granted = true }
                try? await Task.sleep(nanoseconds: UInt64(doneShown * Double(NSEC_PER_SEC)))
                guard !Task.isCancelled else { return }
                dismiss()
                return
            }
        }
    }
}

/// The panel's face, drawn like the island: black, white words, the pane named in small capitals above one plain
/// instruction, and the app as a tile to drag.
struct SettingsHelperView: View {
    @ObservedObject var model: SettingsHelperModel
    let app: URL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let corner: CGFloat = 18
        static let padding: CGFloat = 16
        static let markColumn: CGFloat = 22
        static let tileCorner: CGFloat = 12
        static let tileHeight: CGFloat = 56
        static let iconSide: CGFloat = 32
        static let closeSide: CGFloat = 20
        static let labelTracking: CGFloat = 2
        static let dash: [CGFloat] = [4, 3]
    }

    private enum Symbol {
        static let arrow = "arrowshape.up.fill"
        static let done = "checkmark.circle.fill"
        static let close = "xmark"
        static let hand = "hand.draw"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            HStack(alignment: .top, spacing: Memnox.Spacing.medium) {
                mark.frame(width: Layout.markColumn)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    Text(model.pane.title.uppercased())
                        .font(Memnox.mono(Memnox.TextSize.micro, .medium))
                        .tracking(Layout.labelTracking)
                        .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                    Text(instruction)
                        .font(Memnox.sans(Memnox.TextSize.headline, .regular))
                        .foregroundStyle(Color.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                closeButton
            }
            if !model.granted { tile.transition(.opacity.combined(with: .move(edge: .bottom))) }
        }
        .padding(Layout.padding)
        .background(RoundedRectangle(cornerRadius: Layout.corner, style: .continuous).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: Layout.corner, style: .continuous).strokeBorder(Color.white.opacity(Memnox.Ink.edge)))
        .animation(reduceMotion ? nil : .snappy, value: model.granted)
    }

    /// The arrow pointing up at the list, which drifts while it waits and beats while the app is being dragged; a check
    /// once the grant has landed.
    @ViewBuilder private var mark: some View {
        if model.granted {
            Image(systemName: Symbol.done)
                .font(.system(size: Memnox.TextSize.headline + 3, weight: .semibold))
                .foregroundStyle(IslandPalette.green)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("Allowed")
        } else {
            DriftingArrow(beating: model.dragging, still: reduceMotion)
                .accessibilityHidden(true)
        }
    }

    private var closeButton: some View {
        Button(action: model.close) {
            Image(systemName: Symbol.close)
                .font(.system(size: Memnox.TextSize.micro, weight: .bold))
                .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                .frame(width: Layout.closeSide, height: Layout.closeSide)
                .background(Circle().fill(Color.white.opacity(Memnox.Ink.fill)))
        }
        .buttonStyle(.plain)
        .pointingHand()
        .help("Close")
    }

    private var tile: some View {
        HStack(spacing: Memnox.Spacing.regular) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: Layout.iconSide, height: Layout.iconSide)
            Text(app.deletingPathExtension().lastPathComponent + ".app")
                .font(Memnox.sans(Memnox.TextSize.headline, .semibold))
                .foregroundStyle(Color.white)
            Spacer()
            VStack(spacing: Memnox.Spacing.xxSmall) {
                Image(systemName: Symbol.hand).font(.system(size: Memnox.TextSize.callout))
                Text("DRAG").font(Memnox.mono(Memnox.TextSize.micro - 2, .medium)).tracking(Layout.labelTracking)
            }
            .foregroundStyle(Color.white.opacity(Memnox.Ink.tertiary))
        }
        .padding(.horizontal, Memnox.Spacing.large)
        .frame(height: Layout.tileHeight)
        .background(RoundedRectangle(cornerRadius: Layout.tileCorner, style: .continuous).fill(Color.white.opacity(Memnox.Ink.faintFill)))
        .overlay(
            RoundedRectangle(cornerRadius: Layout.tileCorner, style: .continuous)
                .strokeBorder(Color.white.opacity(Memnox.Ink.tertiary), style: StrokeStyle(lineWidth: Memnox.Stroke.hairline, dash: Layout.dash))
        )
        // The drag itself is AppKit's, laid over the tile, since only a real dragging session reaches System Settings.
        .overlay(AppDragTile(app: app, dragging: model.dragged))
        .help("Drag Memnox into the list above")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Memnox app, drag it into the list in System Settings")
    }

    private var instruction: AttributedString {
        if model.granted { return AttributedString("Done. Memnox is allowed.") }
        let words: String
        switch model.pane {
        case .typing:
            words = "Switch **Memnox** on in the list. Already on? Switch it off and on. Not there? Drag it in."
        case .seeing:
            words = "Switch **Memnox** on in the list, then reopen it when asked. Not there? Drag it in."
        }
        return (try? AttributedString(markdown: words)) ?? AttributedString(words)
    }
}

/// The arrow over the tile: a slow drift up and down at rest, a quicker beat while the app is in the air.
private struct DriftingArrow: View {
    let beating: Bool
    let still: Bool
    @State private var up = false

    private enum Motion {
        static let drift: CGFloat = 2
        static let driftSeconds = 1.6
        static let beatSmall: CGFloat = 0.88
        static let beatLarge: CGFloat = 1.18
        static let beatSeconds = 0.68
    }

    var body: some View {
        Image(systemName: "arrowshape.up.fill")
            .font(.system(size: Memnox.TextSize.headline + 3, weight: .semibold))
            .foregroundStyle(IslandPalette.green)
            .offset(y: still || beating ? 0 : (up ? -Motion.drift : Motion.drift))
            .scaleEffect(still || !beating ? 1 : (up ? Motion.beatLarge : Motion.beatSmall))
            .animation(still ? nil : .easeInOut(duration: beating ? Motion.beatSeconds : Motion.driftSeconds).repeatForever(autoreverses: true), value: up)
            .onAppear { if !still { up = true } }
            .onChange(of: beating) { _, _ in
                // Restarted so the new pace takes over at once rather than after the old cycle ends.
                up = false
                DispatchQueue.main.async { if !still { up = true } }
            }
    }
}
