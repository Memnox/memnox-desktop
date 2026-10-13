import AppKit
import MemnoxVoiceCore
import SwiftUI

/// The two grants macOS keeps behind System Settings, where the app can ask once and then only point the way.
enum SettingsPane {
    /// Accessibility, which lets Memnox type into the agent's own app and read back that it landed.
    case typing
    /// Screen Recording, which lets Memnox read the window the person asks about.
    case seeing

    /// The pane's name as this macOS prints it, so the picture matches what the person opens.
    var title: String {
        switch self {
        case .typing: return Conversation.typingPane(macOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
        case .seeing:
            // Renamed when macOS 15 put system audio beside it.
            return ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= Self.audioJoinedScreen
                ? "Screen & System Audio Recording" : "Screen Recording"
        }
    }

    /// The first macOS whose pane for screen recording also names system audio.
    private static let audioJoinedScreen = 15

    /// The privacy service macOS files the grant under, which tccutil takes by this name.
    var service: String {
        switch self {
        case .typing: return "Accessibility"
        case .seeing: return "ScreenCapture"
        }
    }

    /// Forgets every entry macOS keeps for Memnox in this pane, so a switch left on by an earlier build stops standing in
    /// for the real grant and the next ask adds this build fresh. Only Memnox's own entries, never another app's.
    func forgetEarlierBuilds() async {
        guard let bundle = Bundle.main.bundleIdentifier else { return }
        await RuntimeInstaller.forgetGrant(service, of: bundle)
        diary.note("forgot the \(service) entries of earlier builds")
    }

    /// Opens System Settings on the pane itself, so nobody hunts for it.
    func open() {
        let page: String
        switch self {
        case .typing: page = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .seeing: page = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
        if let url = URL(string: page) { NSWorkspace.shared.open(url) }
    }
}

/// A small picture of the System Settings list a grant lives in, with a pointer that switches Memnox off and on, so
/// the person sees what to do rather than reads it. Off and on, because a switch that already shows on belongs to an
/// earlier copy of the app, and only toggling it renews the grant. Under the picture, the one button that opens the pane.
struct PermissionGuide: View {
    let pane: SettingsPane
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = true
    @State private var pointer = Layout.pointerRest
    @State private var pressing = false

    private enum Layout {
        static let width: CGFloat = 300
        static let rowHeight: CGFloat = 30
        static let rows = 3
        static let headerHeight: CGFloat = 26
        static let radius: CGFloat = 10
        static let tileSide: CGFloat = 18
        static let tileRadius: CGFloat = 5
        static let switchWidth: CGFloat = 30
        static let switchHeight: CGFloat = 17
        static let knobInset: CGFloat = 2
        static let padding: CGFloat = 12
        static let barHeight: CGFloat = 8
        static let barWidths: [CGFloat] = [84, 110]
        static let pointerSize: CGFloat = 16
        /// Where the pointer rests between runs, and where it lands on the switch, as offsets from the picture's corner.
        static let pointerRest = CGPoint(x: 200, y: 92)
        static let switchCentre = CGPoint(x: width - padding - switchWidth / 2, y: headerHeight + rowHeight * 2.5)
        static let pressScale: CGFloat = 0.85
        static let dimmed = 0.35
    }

    private enum Beat {
        /// A long rest before the pointer moves, so the picture reads first as a list.
        static let rest: UInt64 = 1_400_000_000
        static let travel: UInt64 = 700_000_000
        static let press: UInt64 = 120_000_000
        static let between: UInt64 = 900_000_000
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            picture
                .frame(width: Layout.width, height: Layout.headerHeight + Layout.rowHeight * CGFloat(Layout.rows))
                .overlay(alignment: .topLeading) { arrow }
                .clipShape(RoundedRectangle(cornerRadius: Layout.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Layout.radius, style: .continuous)
                    .strokeBorder(Memnox.ink(Memnox.Ink.edge), lineWidth: Memnox.Stroke.hairline))
                .accessibilityLabel("In System Settings, \(pane.title), switch Memnox off and on again.")
            Button("Open System Settings", systemImage: "gear") { pane.open() }
                .buttonStyle(KitButton(kind: .secondary))
        }
        .task(id: reduceMotion) { await play() }
    }

    /// The pane's title over two quiet rows for other apps, then the Memnox row with its switch.
    private var picture: some View {
        VStack(spacing: 0) {
            Text(pane.title)
                .font(Memnox.sans(Memnox.TextSize.caption, .semibold))
                .foregroundStyle(Memnox.ink(Memnox.Ink.primary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Layout.headerHeight)
                .padding(.horizontal, Layout.padding)
            ForEach(Layout.barWidths, id: \.self) { width in otherApp(barWidth: width) }
            memnoxRow
        }
        .background(Memnox.Palette.raised)
    }

    private func otherApp(barWidth: CGFloat) -> some View {
        HStack(spacing: Memnox.Spacing.small) {
            RoundedRectangle(cornerRadius: Layout.tileRadius, style: .continuous)
                .fill(Memnox.ink(Memnox.Ink.fill))
                .frame(width: Layout.tileSide, height: Layout.tileSide)
            Capsule().fill(Memnox.ink(Memnox.Ink.fill)).frame(width: barWidth, height: Layout.barHeight)
            Spacer(minLength: 0)
            toggle(on: true).opacity(Layout.dimmed)
        }
        .padding(.horizontal, Layout.padding)
        .frame(height: Layout.rowHeight)
    }

    private var memnoxRow: some View {
        HStack(spacing: Memnox.Spacing.small) {
            LogoMark(size: Layout.tileSide * 0.5)
                .frame(width: Layout.tileSide, height: Layout.tileSide)
                .background(RoundedRectangle(cornerRadius: Layout.tileRadius, style: .continuous).fill(Memnox.Palette.surface))
            Text("Memnox.app")
                .font(Memnox.sans(Memnox.TextSize.footnote, .medium))
                .foregroundStyle(Memnox.Palette.ink)
            Spacer(minLength: 0)
            toggle(on: on)
        }
        .padding(.horizontal, Layout.padding)
        .frame(height: Layout.rowHeight)
        .background(Memnox.Palette.primary.opacity(Memnox.Ink.fill))
    }

    private func toggle(on: Bool) -> some View {
        Capsule()
            .fill(on ? Memnox.Palette.primary : Memnox.ink(Memnox.Ink.edge))
            .frame(width: Layout.switchWidth, height: Layout.switchHeight)
            .overlay(alignment: on ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .padding(Layout.knobInset)
            }
    }

    /// The pointer, white with a dark edge so it shows on either look, pressed smaller at each click.
    private var arrow: some View {
        Image(systemName: "cursorarrow")
            .font(.system(size: Layout.pointerSize, weight: .bold))
            .foregroundStyle(Color.white)
            .shadow(color: .black.opacity(0.9), radius: 0.8)
            .scaleEffect(pressing ? Layout.pressScale : 1)
            .offset(x: pointer.x, y: pointer.y)
            .accessibilityHidden(true)
    }

    /// Rest, travel to the switch, click it off, click it on, and again; with motion reduced it only shows the switch on.
    private func play() async {
        guard !reduceMotion else {
            pointer = Layout.switchCentre
            on = true
            return
        }
        while !Task.isCancelled {
            withAnimation(.easeInOut(duration: Memnox.Motion.standard)) { pointer = Layout.pointerRest; on = true }
            guard (try? await Task.sleep(nanoseconds: Beat.rest)) != nil else { return }
            withAnimation(.easeInOut(duration: Double(Beat.travel) / 1_000_000_000)) { pointer = Layout.switchCentre }
            guard (try? await Task.sleep(nanoseconds: Beat.travel + Beat.press)) != nil else { return }
            await click { on = false }
            guard (try? await Task.sleep(nanoseconds: Beat.between)) != nil else { return }
            await click { on = true }
            guard (try? await Task.sleep(nanoseconds: Beat.between + Beat.rest)) != nil else { return }
        }
    }

    private func click(_ flip: @escaping () -> Void) async {
        withAnimation(.easeOut(duration: Memnox.Motion.quick)) { pressing = true }
        _ = try? await Task.sleep(nanoseconds: Beat.press)
        withAnimation(.spring(response: Memnox.Motion.standard, dampingFraction: 0.8)) {
            pressing = false
            flip()
        }
    }
}
