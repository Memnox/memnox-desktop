import AppKit
import MemnoxVoiceCore
import SwiftUI

/// The two grants macOS keeps behind System Settings, where the app can ask once and then only point the way.
enum SettingsPane: Hashable {
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

    /// The panes with an ask running, so a second press, the poll or a typed follow up never starts another over it.
    @MainActor private static var asking: Set<SettingsPane> = []

    /// Asks macOS for the grant, which puts Memnox in the pane's list, and only then opens the pane. One ask at a time
    /// for each pane, in that order, since a list drawn before macOS wrote the entry leaves Memnox out until it is
    /// drawn again, and a reset landing after the entry was written takes Memnox back out of a list already on screen.
    /// Forgetting earlier builds first is for a switch that shows on and does nothing, and only Start over wants it.
    @MainActor func ask(forgettingEarlierBuilds forget: Bool = false) async {
        guard !Self.asking.contains(self) else { return }
        Self.asking.insert(self)
        defer { Self.asking.remove(self) }
        if forget { await forgetEarlierBuilds() }
        if await request(fresh: forget) { return }
        try? await Task.sleep(nanoseconds: UInt64(Self.entryWritten * Double(NSEC_PER_SEC)))
        await show()
    }

    /// True when macOS already says yes. The ask is what adds the entry: for typing the prompt does it every time, while
    /// CoreGraphics asks for the screen once per launch, so after a reset ScreenCaptureKit is what asks again.
    @MainActor private func request(fresh: Bool) async -> Bool {
        switch self {
        case .typing:
            return AXIsProcessTrustedWithOptions([Self.trustedCheckPrompt: true] as CFDictionary)
        case .seeing:
            if CGRequestScreenCaptureAccess() { return true }
            guard fresh else { return false }
            return await ScreenSight.confirmGrant()
        }
    }

    /// Forgets every entry macOS keeps for Memnox in this pane, so a switch left on by an earlier build stops standing in
    /// for the real grant and the next ask adds this build fresh. Only Memnox's own entries, never another app's.
    func forgetEarlierBuilds() async {
        guard let bundle = Bundle.main.bundleIdentifier else { return }
        let ok = await Self.tccutil(["reset", service, bundle])
        diary.note(ok ? "forgot the \(service) entries of earlier builds" : "tccutil could not forget the \(service) entries")
    }

    /// tccutil run straight, with no shell between, so it ends at once and nothing anybody typed reaches it.
    private static func tccutil(_ arguments: [String]) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.tccutilPath)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus == 0) }
            do { try process.run() } catch { continuation.resume(returning: false) }
        }
    }

    /// Opens System Settings on the pane itself, for the button under the picture.
    func open() {
        Task { @MainActor in await show() }
    }

    /// Privacy and Security comes first, because a pane already open keeps the list it drew and so never shows the
    /// Memnox entry the ask just added; arriving anew redraws it.
    @MainActor private func show() async {
        let page: String
        switch self {
        case .typing: page = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .seeing: page = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        }
        guard let url = URL(string: page), let privacy = URL(string: Self.privacyPage) else { return }
        NSWorkspace.shared.open(privacy)
        try? await Task.sleep(nanoseconds: UInt64(Self.redrawDelay * Double(NSEC_PER_SEC)))
        NSWorkspace.shared.open(url)
    }

    private static let privacyPage = "x-apple.systempreferences:com.apple.preference.security"
    private static let tccutilPath = "/usr/bin/tccutil"
    /// The value of kAXTrustedCheckOptionPrompt, written out because Swift 6 refuses that global as shared mutable state.
    private static let trustedCheckPrompt = "AXTrustedCheckOptionPrompt"
    /// Long enough for System Settings to leave the pane before it is asked to come back to it.
    private static let redrawDelay: TimeInterval = 0.6
    /// Long enough for macOS to write the entry the ask made before the list is drawn.
    private static let entryWritten: TimeInterval = 1
}

/// What to do for a grant that waits on the person, under its row and as wide as it: the steps one a line, a small
/// picture of the System Settings list with a pointer that switches Memnox off and on, and the buttons last, so the
/// words never squeeze into a column beside them. Off and on, because a switch that already shows on belongs to an
/// earlier copy of the app, and only toggling it renews the grant.
struct PermissionGuide<Actions: View>: View {
    let pane: SettingsPane
    let steps: [String]
    @ViewBuilder let actions: () -> Actions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = true
    @State private var pointer = Layout.pointerRest
    @State private var pressing = false

    private typealias Layout = GuideLayout
    private typealias Beat = GuideBeat

    var body: some View {
        let panel = RoundedRectangle(cornerRadius: Layout.panelRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Memnox.Spacing.large) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in stepLine(index + 1, step) }
            }
            picture
                .frame(width: Layout.width, height: Layout.headerHeight + Layout.rowHeight * CGFloat(Layout.rows))
                .overlay(alignment: .topLeading) { arrow }
                .clipShape(RoundedRectangle(cornerRadius: Layout.radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Layout.radius, style: .continuous)
                    .strokeBorder(Memnox.ink(Memnox.Ink.edge), lineWidth: Memnox.Stroke.hairline))
                .accessibilityLabel("In System Settings, \(pane.title), switch Memnox off and on again.")
            // Side by side while they fit, stacked when the window is narrow, and never squeezed to an ellipsis.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Memnox.Spacing.medium) { buttons }
                VStack(alignment: .leading, spacing: Memnox.Spacing.medium) { buttons }
            }
        }
        .padding(Memnox.Spacing.xLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panel.fill(Memnox.ink(Memnox.Ink.faintFill)))
        .overlay(panel.strokeBorder(Memnox.ink(Memnox.Ink.edge), lineWidth: Memnox.Stroke.hairline))
        .task(id: reduceMotion) { await play() }
    }

    @ViewBuilder private var buttons: some View {
        Button("Open System Settings", systemImage: "gear") { pane.open() }
            .buttonStyle(KitButton(kind: .secondary))
            .fixedSize()
        actions().fixedSize()
    }

    private func stepLine(_ number: Int, _ step: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.medium) {
            Text("\(number)")
                .font(Memnox.sans(Memnox.TextSize.micro, .semibold))
                .foregroundStyle(Memnox.Palette.ink)
                .frame(width: Layout.numberSide, height: Layout.numberSide)
                .background(Circle().fill(Memnox.ink(Memnox.Ink.edge)))
                .accessibilityHidden(true)
            Text(step)
                .font(Memnox.sans(Memnox.TextSize.footnote))
                .foregroundStyle(Memnox.ink(Memnox.Ink.primary))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
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
            // The app's own icon, so the row looks like the one System Settings lists.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: Layout.tileSide, height: Layout.tileSide)
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

/// Sizes of the guide, apart from it because a generic view keeps no static stored properties.
private enum GuideLayout {
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
    static let numberSide: CGFloat = 18
    static let panelRadius: CGFloat = 12
}

private enum GuideBeat {
    /// A long rest before the pointer moves, so the picture reads first as a list.
    static let rest: UInt64 = 1_400_000_000
    static let travel: UInt64 = 700_000_000
    static let press: UInt64 = 120_000_000
    static let between: UInt64 = 900_000_000
}
