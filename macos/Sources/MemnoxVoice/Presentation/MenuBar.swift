import AppKit
import MemnoxVoiceCore
import SwiftUI

/// What the menu bar panel shows, and what each of its rows does, handed in by the app.
@MainActor
final class MenuModel: ObservableObject {
    @Published var wakeOn: Bool
    @Published var speakUpOn: Bool
    @Published var talkOverOn: Bool
    @Published var chimesOn: Bool
    @Published var liveWordsOn: Bool
    @Published var stayPutOn: Bool
    @Published var voiceChoice: String
    /// Counted each time the panel opens, so its sections can settle in one after another.
    @Published var opened = 0
    /// The phones paired with this Mac and not revoked, fetched each time the panel opens.
    @Published var devices: [Device] = []
    /// The four numbers at the top, fetched each time the panel opens.
    @Published var overview = MenuOverview()
    /// The Kokoro voice saved, so the voice menu ticks the one speaking.
    @Published var kokoroVoice = KokoroVoice.chosen().voice
    /// The agents and connected apps, shared with the notch and Settings.
    let tools: ToolsModel
    let talk: () -> Void
    let setWake: (Bool) -> Void
    let setSpeakUp: (Bool) -> Void
    let setTalkOver: (Bool) -> Void
    let setChimes: (Bool) -> Void
    /// Plays one cue at the volume just chosen, so the slider is heard rather than guessed at.
    var previewChime: () -> Void = {}
    /// Asks, then takes Memnox and everything it put on this Mac away, the app last.
    var uninstall: () -> Void = {}
    let setLiveWords: (Bool) -> Void
    let setStayPut: (Bool) -> Void
    let chooseVoice: (String) -> Void
    let setUp: () -> Void
    let saySomething: () -> Void
    let sayRule: () -> Void
    let copyWhatHappened: () -> Void
    let pairPhone: () -> Void
    let revoke: (Device) -> Void
    /// Gives a phone the mac capability with Touch ID when on, and takes it back unsigned when off.
    let letDrive: (Device, Bool) -> Void
    let loadDevices: () -> Void
    let loadOverview: () -> Void

    init(
        wakeOn: Bool,
        talk: @escaping () -> Void,
        setWake: @escaping (Bool) -> Void,
        speakUpOn: Bool,
        setSpeakUp: @escaping (Bool) -> Void,
        talkOverOn: Bool,
        setTalkOver: @escaping (Bool) -> Void,
        chimesOn: Bool,
        setChimes: @escaping (Bool) -> Void,
        liveWordsOn: Bool,
        setLiveWords: @escaping (Bool) -> Void,
        stayPutOn: Bool,
        setStayPut: @escaping (Bool) -> Void,
        voiceChoice: String,
        chooseVoice: @escaping (String) -> Void,
        setUp: @escaping () -> Void,
        saySomething: @escaping () -> Void,
        sayRule: @escaping () -> Void,
        copyWhatHappened: @escaping () -> Void,
        pairPhone: @escaping () -> Void,
        revoke: @escaping (Device) -> Void,
        letDrive: @escaping (Device, Bool) -> Void,
        loadDevices: @escaping () -> Void,
        loadOverview: @escaping () -> Void = {},
        tools: ToolsModel? = nil
    ) {
        self.tools = tools ?? ToolsModel()
        self.wakeOn = wakeOn
        self.talk = talk
        self.setWake = setWake
        self.speakUpOn = speakUpOn
        self.setSpeakUp = setSpeakUp
        self.talkOverOn = talkOverOn
        self.setTalkOver = setTalkOver
        self.chimesOn = chimesOn
        self.setChimes = setChimes
        self.liveWordsOn = liveWordsOn
        self.setLiveWords = setLiveWords
        self.stayPutOn = stayPutOn
        self.setStayPut = setStayPut
        self.voiceChoice = voiceChoice
        self.chooseVoice = chooseVoice
        self.setUp = setUp
        self.saySomething = saySomething
        self.sayRule = sayRule
        self.copyWhatHappened = copyWhatHappened
        self.pairPhone = pairPhone
        self.revoke = revoke
        self.letDrive = letDrive
        self.loadDevices = loadDevices
        self.loadOverview = loadOverview
    }
}

/// What the agents add up to right now, counted only from what the daemon and the island report.
struct MenuOverview: Equatable {
    var needYou = 0
    var working = 0
    var agents = 0
    var repositories = 0

    init() {}

    /// Ended sessions are left out, so the counts describe work that is still alive.
    init(sessions: [SessionCard], waiting: Int) {
        let live = sessions.filter { $0.sessionState != .ended }
        needYou = waiting
        working = live.filter(\.status.isActive).count
        agents = Set(live.map { $0.agent ?? $0.agentName }).count
        repositories = Set(live.compactMap(\.repository)).count
    }
}

/// The waveform in the menu bar and the pane of glass under it, in place of a system menu,
/// because a system menu cannot wear the Memnox look and this is the one surface always on screen.
@MainActor
final class MenuBarPanel: NSObject {
    private let item: NSStatusItem
    private let panel: NSPanel
    private let host: FirstClickHosting<MenuView>
    private var outside: EventMonitor?
    private var escape: EventMonitor?
    /// The gap between the menu bar icon and the top of the panel, as a menu leaves.
    private static let gap: CGFloat = 6
    /// A first size only, since the panel is sized to its content each time it opens.
    private static let initialSize = NSSize(width: 292, height: 400)
    /// How close the panel may come to the edges of the visible screen.
    private static let screenMargin: CGFloat = 8
    private static let fadeIn: TimeInterval = 0.16
    /// Drawn when the bundled logo is missing.
    private static let fallbackSymbol = "waveform.circle"

    init(model: MenuModel) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        var close: () -> Void = {}
        SettingsWindow.shared.menu = model
        // Settings and setup are one window, opened through setup so its checks are always fresh.
        host = FirstClickHosting(rootView: MenuView(model: model, close: { close() }, openSettings: { model.setUp() }))
        super.init()
        close = { [weak self] in self?.dismiss() }
        item.button?.image = MemnoxLogo.menuBar
            ?? NSImage(systemSymbolName: Self.fallbackSymbol, accessibilityDescription: "Memnox")
        item.button?.toolTip = "Memnox"
        item.button?.target = self
        item.button?.action = #selector(toggle)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        // Glass over whatever is behind it, light or dark as the Mac is set; the system shadow follows its rounded edge.
        panel.contentView = host
    }

    @objc private func toggle() {
        if panel.isVisible {
            dismiss()
            return
        }
        guard let button = item.button, let window = button.window else { return }
        let icon = window.convertToScreen(button.convert(button.bounds, to: nil))
        let size = host.fittingSize
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? icon
        // Under the icon, and always inside the visible screen, so nothing is cut off at the top or sides.
        let x = min(max(icon.midX - size.width / 2, screen.minX + Self.screenMargin), screen.maxX - size.width - Self.screenMargin)
        let y = max(min(icon.minY - Self.gap, screen.maxY) - size.height, screen.minY + Self.screenMargin)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = Self.fadeIn; panel.animator().alphaValue = 1 }
        host.rootView.model.opened += 1
        host.rootView.model.kokoroVoice = KokoroVoice.chosen().voice
        host.rootView.model.loadDevices()
        host.rootView.model.loadOverview()
        host.rootView.model.tools.refresh()
        watchForDismissal()
    }

    /// A click anywhere else, or Escape, closes it the way a menu closes.
    private func watchForDismissal() {
        outside = EventMonitor.global([.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        escape = EventMonitor.local(.keyDown) { [weak self] event in
            guard event.keyCode == KeyCode.escape else { return event }
            self?.dismiss()
            return nil
        }
    }

    private func dismiss() {
        outside?.stop()
        escape?.stop()
        outside = nil
        escape = nil
        panel.orderOut(nil)
    }
}

/// The menu bar panel, kept to what is needed in passing: how Memnox is listening, then one plain list of rows: talk,
/// say a rule, copy what happened, Settings and Quit. What is waiting and working lives on the island and in Settings.
struct MenuView: View {
    @ObservedObject var model: MenuModel
    @ObservedObject private var mute = VoiceMute.shared
    let close: () -> Void
    let openSettings: () -> Void
    static let width: CGFloat = 300

    private enum Layout {
        static let cornerRadius: CGFloat = 22
        static let logoSize: CGFloat = 24
        static let titleSize: CGFloat = 21
        static let dotSize: CGFloat = 6
        static let idleDotInk = 0.3
        static let badgeHorizontalPadding: CGFloat = 9
        static let badgeVerticalPadding: CGFloat = 5
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
            header
            MenuTools(tools: model.tools) {
                close()
                SettingsWindow.shared.show(.apps)
            }
            .settling(model.opened, order: 0)
            VStack(spacing: Memnox.Spacing.xxSmall) {
                MenuRow(symbol: MenuSymbol.talk, title: "Talk to Memnox", keys: ["\u{2325}", "Space"]) {
                    close()
                    model.talk()
                }
                .help("Talk to Memnox with Option Space")
                MenuRow(symbol: MenuSymbol.rule, title: "Say a rule") {
                    close()
                    model.sayRule()
                }
                MenuRow(symbol: MenuSymbol.copy, title: "Copy what happened") {
                    close()
                    model.copyWhatHappened()
                }
                // Muting keeps the panel open, so the row is seen to change.
                MenuRow(symbol: mute.on ? MenuSymbol.unmute : MenuSymbol.mute, title: mute.on ? "Unmute voice" : "Mute voice") {
                    mute.toggle()
                }
                // What Memnox does above the line, the app itself below it, as a Mac menu groups them.
                MenuDivider()
                    .padding(.vertical, Memnox.Spacing.xxSmall)
                MenuRow(symbol: MenuSymbol.settings, title: "Settings", action: showSettings)
                MenuRow(symbol: MenuSymbol.quit, title: "Quit Memnox", quiet: true) {
                    NSApp.terminate(nil)
                }
            }
            .padding(Memnox.Spacing.xSmall)
            .menuCard()
            .settling(model.opened, order: 1)
        }
        .padding(Memnox.Spacing.large)
        .frame(width: Self.width)
        // Vorssaint's panel: the system material with a steady wash, so text never depends on the wallpaper behind.
        .background(MenuPanelStyle.wash)
        .background(.regularMaterial)
        .clipShape(shape)
        .overlay(shape.strokeBorder(SurfaceStyle.border, lineWidth: SurfaceStyle.borderWidth))
    }

    private func showSettings() {
        close()
        openSettings()
    }

    private var header: some View {
        HStack(spacing: MenuLayout.iconSpacing) {
            LogoMark(size: Layout.logoSize)
            Text("Memnox")
                .font(Memnox.display(Layout.titleSize))
                .foregroundStyle(Memnox.Palette.ink)
            Spacer()
            HStack(spacing: Memnox.Spacing.small) {
                Circle()
                    .fill(model.wakeOn ? IslandPalette.green : Memnox.ink(Layout.idleDotInk))
                    .frame(width: Layout.dotSize, height: Layout.dotSize)
                // Says how to start a talk, since "Listening" read as if the microphone were recording all along.
                Text(model.wakeOn ? "Say \u{201C}Memnox\u{201D}" : "\u{2325} Space to talk")
                    .font(Memnox.sans(Memnox.TextSize.caption, .medium))
                    .foregroundStyle(Memnox.ink(MenuLayout.mutedInk))
                    .lineLimit(1)
            }
            .padding(.horizontal, Layout.badgeHorizontalPadding)
            .padding(.vertical, Layout.badgeVerticalPadding)
            .background(Capsule().fill(Memnox.ink(MenuLayout.softFill)))
            .animation(.easeOut(duration: Memnox.Motion.quick), value: model.wakeOn)
            .help(model.wakeOn ? "Memnox wakes when you say its name" : "Press Option Space to talk")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.wakeOn ? "Memnox wakes when you say its name" : "Press Option Space to talk")
        }
        .padding(.horizontal, Memnox.Spacing.xSmall)
        .padding(.top, Memnox.Spacing.xSmall)
    }
}

/// A section's name in small capitals, as Vorssaint names its panel's sections.
struct MenuHeading: View {
    let title: String

    private static let tracking: CGFloat = 0.5

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: Memnox.TextSize.micro, weight: .semibold))
            .kerning(Self.tracking)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Memnox.Spacing.xSmall)
            .accessibilityAddTraits(.isHeader)
    }
}

/// One action: an icon and a label, lit softly under the pointer.
struct MenuRow: View {
    let symbol: String
    let title: String
    var quiet = false
    /// The shortcut that does the same, printed as keycaps at the end of the row.
    var keys: [String] = []
    let action: () -> Void
    @State private var hovering = false

    private static let height: CGFloat = 32
    private static let textInk = 0.9
    private static let hoverFade: TimeInterval = 0.12

    var body: some View {
        Button(action: action) {
            HStack(spacing: MenuLayout.iconSpacing) {
                Image(systemName: symbol)
                    .font(.system(size: Memnox.TextSize.body, weight: .medium))
                    .foregroundStyle(Memnox.ink(quiet ? MenuLayout.dimInk : MenuLayout.mutedInk))
                    .frame(width: MenuLayout.iconColumnWidth)
                Text(title)
                    .font(Memnox.sans(Memnox.TextSize.body, .medium))
                    .foregroundStyle(Memnox.ink(quiet ? Memnox.Ink.secondary : Self.textInk))
                Spacer()
                if !keys.isEmpty {
                    HStack(spacing: Memnox.Spacing.xxSmall) { ForEach(keys, id: \.self) { Keycap(label: $0) } }
                }
            }
            .padding(.horizontal, Memnox.Spacing.regular)
            .frame(height: Self.height)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: MenuLayout.rowCornerRadius, style: .continuous)
                    .fill(Memnox.ink(hovering ? MenuLayout.softFill : 0))
            )
            .animation(.easeOut(duration: Self.hoverFade), value: hovering)
        }
        .buttonStyle(MenuPress())
        // Clicked only: a row holding the keyboard ran "Say a rule" on every space typed into a window behind it.
        .focusable(false)
        .onHover { hovering = $0 }
    }
}

/// A setting that is on or off, as a Vorssaint row: a tinted tile, a label with a line under it, and the Mac's own switch.
struct SwitchRow: View {
    let symbol: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    @Environment(\.isEnabled) private var enabled

    var body: some View {
        SettingsRow(symbol: symbol, title: title, caption: detail) {
            Toggle(title, isOn: $isOn)
                .toggleStyle(MemnoxSwitch())
                .labelsHidden()
                .accessibilityHint(detail)
        }
        // The whole row flips the switch, lit under the pointer with the hand showing, as it always has.
        .contentShape(Rectangle())
        .onTapGesture { if enabled { isOn.toggle() } }
        .hoverLight()
    }
}

/// A paired phone: its name, what it may do, Revoke, and whether it may drive this Mac.
struct DeviceRow: View {
    let device: Device
    let revoke: () -> Void
    let letDrive: (Bool) -> Void

    var body: some View {
        VStack(spacing: SettingsMetrics.cardSpacing) {
            SettingsRow(symbol: MenuSymbol.phone, title: device.name, caption: detail) {
                Button("Revoke", action: revoke)
            }
            // On asks for Touch ID since it widens what the phone can do; off goes straight through and ends any drive.
            SwitchRow(
                symbol: MenuSymbol.drive,
                title: "Let it drive this Mac",
                detail: drives ? "Turn off to stop it" : "Touch ID to turn on",
                isOn: Binding(get: { drives }, set: { on in if on != drives { letDrive(on) } })
            )
        }
    }

    private var drives: Bool { device.granted.contains(.mac) }

    /// What it may do, in the capabilities' own words.
    private var detail: String {
        let granted = device.granted.map(\.rawValue)
        return granted.isEmpty ? "Paired" : "Can " + granted.joined(separator: ", ")
    }
}

/// Which voice speaks: Kokoro on this Mac and free, or the Mac's own.
enum VoiceChoice {
    static let kokoro = "kokoro"
    static let mac = "mac"
}

/// A switch, Memnox blue when on with a white knob as a settings switch is, drawn here since the system one goes grey in a
/// panel that is not key.
struct MemnoxSwitch: ToggleStyle {
    private enum Layout {
        static let trackWidth: CGFloat = 34
        static let trackHeight: CGFloat = 20
        static let offTrackInk = 0.14
        /// The knob fills the track's height less its inset on each side.
        static let knobSize: CGFloat = 16
        static let knobShadowOpacity = 0.25
        static let knobShadowRadius: CGFloat = 1
        static let knobShadowDrop: CGFloat = 1
        static let flip = Animation.spring(response: 0.25, dampingFraction: 0.75)
    }

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Memnox.Palette.primary : Memnox.ink(Layout.offTrackInk))
                    .frame(width: Layout.trackWidth, height: Layout.trackHeight)
                Circle()
                    .fill(Color.white)
                    .frame(width: Layout.knobSize, height: Layout.knobSize)
                    .padding(Memnox.Spacing.xxSmall)
                    .shadow(color: .black.opacity(Layout.knobShadowOpacity), radius: Layout.knobShadowRadius, y: Layout.knobShadowDrop)
            }
            .animation(Layout.flip, value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .pointingHand()
    }
}

/// A faint rule between the rows of one card.
struct MenuDivider: View {
    private static let ink = 0.05
    /// Starts under the row titles: the row's inset, its icon column and the gap after it.
    private static let indent = MenuLayout.rowInset + MenuLayout.iconColumnWidth + MenuLayout.iconSpacing

    var body: some View {
        Rectangle()
            .fill(Memnox.ink(Self.ink))
            .frame(height: Memnox.Stroke.hairline)
            .padding(.leading, Self.indent)
    }
}

/// Gives a little when pressed, the same press as the island's buttons.
struct MenuPress: ButtonStyle {
    private static let pressedScale: CGFloat = 0.97
    private static let press = Animation.spring(response: 0.2, dampingFraction: 0.6)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Self.pressedScale : 1)
            .animation(Self.press, value: configuration.isPressed)
            .pointingHand()
    }
}

private extension View {
    /// Each section rises into place a moment after the one above it, every time the panel opens.
    func settling(_ opened: Int, order: Int) -> some View {
        modifier(Settle(opened: opened, order: order))
    }
}

private struct Settle: ViewModifier {
    let opened: Int
    let order: Int

    private enum Timing {
        /// How far below its place a section starts.
        static let rise = 6.0
        /// A keyframe cannot last no time at all, so hiding at once takes a thousandth of a second.
        static let instant: TimeInterval = 0.001
        /// How long each section waits after the one above it.
        static let stagger: TimeInterval = 0.04
        static let settle: TimeInterval = 0.32
    }

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 1.0, trigger: opened) { view, value in
                view.opacity(value).offset(y: (1 - value) * Timing.rise)
            } keyframes: { _ in
                LinearKeyframe(0.0, duration: Timing.instant)
                LinearKeyframe(0.0, duration: Timing.instant + Timing.stagger * Double(order))
                SpringKeyframe(1.0, duration: Timing.settle, spring: .smooth)
            }
    }
}

/// Vorssaint's menu panel surfaces: the wash over the material, and the card each group of rows sits on.
enum MenuPanelStyle {
    static let wash = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0, alpha: 0.42) : NSColor(white: 1, alpha: 0.68)
    })
    static let cardFill = Color(nsColor: NSColor(name: nil) { appearance in
        NSColor(white: 1, alpha: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.075 : 0.38)
    })
    static let cardRadius: CGFloat = 10
}

extension View {
    /// A group of the menu's rows on Vorssaint's panel card: a faint fill and the shared outline.
    func menuCard() -> some View {
        let shape = RoundedRectangle(cornerRadius: MenuPanelStyle.cardRadius, style: .continuous)
        return background(MenuPanelStyle.cardFill, in: shape)
            .overlay(shape.strokeBorder(SurfaceStyle.border, lineWidth: SurfaceStyle.borderWidth))
    }
}

/// The agents and apps Memnox can act through, as a strip of small tiles, the way Vorssaint's panel shows its tools.
/// One row tall whatever it holds, since the panel takes its size once as it opens.
struct MenuTools: View {
    @ObservedObject var tools: ToolsModel
    let open: () -> Void

    private enum Layout {
        static let markSide: CGFloat = 26
        static let chipWidth: CGFloat = 58
        static let stripHeight: CGFloat = 52
        static let labelSize: CGFloat = 10
        static let dotSide: CGFloat = 6
        /// A dark ring keeps the status dot apart from a logo of the same colour.
        static let dotRingInk = 0.4
        static let dotRingWidth: CGFloat = 0.5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            HStack {
                MenuHeading(title: "Connected")
                Spacer()
                Button("Manage", action: open)
                    .buttonStyle(.plain)
                    .font(.system(size: Memnox.TextSize.micro, weight: .semibold))
                    .foregroundStyle(Memnox.Palette.primary)
                    .pointingHand()
            }
            .padding(.horizontal, Memnox.Spacing.xSmall)
            Group {
                if tools.agents.isEmpty && tools.connections.isEmpty {
                    Text(tools.loading ? "Reading your tools" : tools.connectionsNote ?? "No tools connected yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, Memnox.Spacing.regular)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            ForEach(tools.agents) { agent in
                                chip(agent.label, ok: agent.works != false) {
                                    AgentMark(kind: agent.kind, name: agent.label, side: Layout.markSide)
                                }
                            }
                            ForEach(tools.connections) { connection in
                                chip(ToolkitName.of(connection.toolkit), ok: connection.connected) {
                                    ToolMark(toolkit: connection.toolkit, side: Layout.markSide)
                                }
                            }
                        }
                        .padding(.horizontal, Memnox.Spacing.xSmall)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .frame(height: Layout.stripHeight)
            .menuCard()
        }
    }

    private func chip<Mark: View>(_ name: String, ok: Bool, @ViewBuilder mark: () -> Mark) -> some View {
        Button(action: open) {
            VStack(spacing: Memnox.Spacing.xSmall) {
                mark()
                    .overlay(alignment: .bottomTrailing) {
                        Circle()
                            .fill(ok ? Memnox.Palette.success : Memnox.Palette.warm)
                            .frame(width: Layout.dotSide, height: Layout.dotSide)
                            .overlay(Circle().strokeBorder(Color.black.opacity(Layout.dotRingInk), lineWidth: Layout.dotRingWidth))
                    }
                Text(name)
                    .font(.system(size: Layout.labelSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: Layout.chipWidth)
        }
        .buttonStyle(MenuPress())
        .help(ok ? name : "\(name) needs you")
        .accessibilityLabel(ok ? name : "\(name), needs you")
    }
}

/// Measures every row of the menu shares, so icons, labels and rules line up from row to row.
enum MenuLayout {
    static let iconSpacing: CGFloat = 11
    static let iconColumnWidth: CGFloat = 18
    static let rowInset: CGFloat = 12
    static let rowCornerRadius: CGFloat = 11
    static let titleDetailSpacing: CGFloat = 1
    /// Every setting row is at least this tall, so a one line row and a two line row sit on the same rhythm.
    static let settingRowHeight: CGFloat = 46
    /// White for secondary icons and labels, between the shared secondary ink and full white.
    static let mutedInk = 0.6
    static let litInk = 0.75
    static let dimInk = 0.4
    /// The faint white behind a hovered row and the listening badge.
    static let softFill = 0.07
}

/// The SF Symbols the menu draws, one per row.
enum MenuSymbol {
    static let talk = "waveform"
    static let wake = "ear"
    static let speakUp = "bell"
    static let talkOver = "waveform.badge.mic"
    static let sounds = "speaker.wave.1"
    static let volume = "speaker.wave.3"
    static let liveWords = "text.bubble"
    static let dictation = "keyboard"
    static let stayPut = "macwindow.on.rectangle"
    static let rule = "shield.lefthalf.filled"
    static let pairPhone = "qrcode"
    static let phone = "iphone"
    static let drive = "cursorarrow.motionlines"
    static let voice = "person.wave.2"
    static let setUp = "slider.horizontal.3"
    static let saySomething = "speaker.wave.2"
    static let copy = "doc.on.clipboard"
    static let mute = "speaker.slash"
    static let unmute = "speaker.wave.2"
    static let quit = "power"
    static let settings = "gearshape"
    static let more = "chevron.right"
    static let needYou = "hand.raised"
    static let working = "bolt"
    static let agents = "person.2"
    static let repositories = "folder"
}
