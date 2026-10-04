import AppKit
import SwiftUI

/// What the menu bar panel shows, and what each of its rows does, handed in by the app.
@MainActor
final class MenuModel: ObservableObject {
    @Published var wakeOn: Bool
    @Published var speakUpOn: Bool
    @Published var talkOverOn: Bool
    @Published var chimesOn: Bool
    @Published var liveWordsOn: Bool
    @Published var liveWordsOn: Bool
    @Published var voiceChoice: String
    /// Counted each time the panel opens, so its sections can settle in one after another.
    @Published var opened = 0
    let talk: () -> Void
    let setWake: (Bool) -> Void
    let setSpeakUp: (Bool) -> Void
    let setTalkOver: (Bool) -> Void
    let setLiveWords: (Bool) -> Void
    let setChimes: (Bool) -> Void
    let setLiveWords: (Bool) -> Void
    let chooseVoice: (String) -> Void
    let sayRule: () -> Void
    let setUp: () -> Void
    let saySomething: () -> Void
    let copyWhatHappened: () -> Void

    init(
        wakeOn: Bool,
        talk: @escaping () -> Void,
        setWake: @escaping (Bool) -> Void,
        speakUpOn: Bool,
        setSpeakUp: @escaping (Bool) -> Void,
        talkOverOn: Bool,
        setTalkOver: @escaping (Bool) -> Void,
        liveWordsOn: Bool,
        setLiveWords: @escaping (Bool) -> Void,
        chimesOn: Bool,
        setChimes: @escaping (Bool) -> Void,
        liveWordsOn: Bool,
        setLiveWords: @escaping (Bool) -> Void,
        sayRule: @escaping () -> Void,
        voiceChoice: String,
        chooseVoice: @escaping (String) -> Void,
        setUp: @escaping () -> Void,
        saySomething: @escaping () -> Void,
        copyWhatHappened: @escaping () -> Void
    ) {
        self.wakeOn = wakeOn
        self.talk = talk
        self.setWake = setWake
        self.speakUpOn = speakUpOn
        self.setSpeakUp = setSpeakUp
        self.liveWordsOn = liveWordsOn
        self.setLiveWords = setLiveWords
        self.talkOverOn = talkOverOn
        self.setTalkOver = setTalkOver
        self.chimesOn = chimesOn
        self.setChimes = setChimes
        self.sayRule = sayRule
        self.liveWordsOn = liveWordsOn
        self.setLiveWords = setLiveWords
        self.voiceChoice = voiceChoice
        self.chooseVoice = chooseVoice
        self.setUp = setUp
        self.saySomething = saySomething
        self.copyWhatHappened = copyWhatHappened
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
        host = FirstClickHosting(rootView: MenuView(model: model) { close() })
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
        panel.appearance = NSAppearance(named: .darkAqua)
        // Solid black like the island and its cards; the system shadow follows its rounded edge cleanly.
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

struct MenuView: View {
    @ObservedObject var model: MenuModel
    let close: () -> Void
    static let width: CGFloat = 300

    private enum Layout {
        static let cornerRadius: CGFloat = 22
        /// A faint blue rising from below the panel.
        static let glowOpacity = 0.16
        static let glowCenter = UnitPoint(x: 0.5, y: 1.15)
        static let edgeInk = 0.07
        static let logoSize: CGFloat = 24
        static let titleSize: CGFloat = 21
        static let dotSize: CGFloat = 6
        static let idleDotInk = 0.3
        static let badgeHorizontalPadding: CGFloat = 9
        static let badgeVerticalPadding: CGFloat = 5
        static let talkVeilOpacity = 0.45
        static let talkIconSize: CGFloat = 30
        static let talkIconFillOpacity = 0.22
        static let keycapSpacing: CGFloat = 3
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
            header
            talkCard
                .settling(model.opened, order: 0)
            IslandCard(veil: nil) {
                VStack(spacing: 0) {
                    wakeRow
                    Divide()
                    SwitchRow(symbol: Symbol.liveWords, title: "Live words", detail: "See what you say in the notch", isOn: Binding(get: { model.liveWordsOn }, set: { model.liveWordsOn = $0; model.setLiveWords($0) }))
                    Divide()
                    SwitchRow(symbol: Symbol.speakUp, title: "Speak up on its own", detail: "When work finishes or ships", isOn: Binding(get: { model.speakUpOn }, set: { model.speakUpOn = $0; model.setSpeakUp($0) }))
                    Divide()
                    SwitchRow(symbol: Symbol.talkOver, title: "Talk over it", detail: "Cut in just by speaking", isOn: Binding(get: { model.talkOverOn }, set: { model.talkOverOn = $0; model.setTalkOver($0) }))
                    Divide()
                    SwitchRow(symbol: Symbol.sounds, title: "Sounds", detail: "A chime when something happens", isOn: Binding(get: { model.chimesOn }, set: { model.chimesOn = $0; model.setChimes($0) }))
                    Divide()
                    SwitchRow(symbol: Symbol.liveWords, title: "Live words", detail: "See what you say in the notch", isOn: Binding(get: { model.liveWordsOn }, set: { model.liveWordsOn = $0; model.setLiveWords($0) }))
                }
                .padding(.vertical, Memnox.Spacing.xSmall)
            }
            .settling(model.opened, order: 1)
            IslandCard(veil: nil) {
                VoiceChoicePicker(choice: Binding(get: { model.voiceChoice }, set: { model.voiceChoice = $0; model.chooseVoice($0) }))
                MenuRow(symbol: Symbol.rule, title: "Say a rule") {
                    close()
                    model.sayRule()
                }
                    .padding(.vertical, Memnox.Spacing.small)
            }
            .settling(model.opened, order: 2)
            VStack(spacing: Memnox.Spacing.xxSmall) {
                MenuRow(symbol: Symbol.setUp, title: "Set up Memnox") {
                    close()
                    model.setUp()
                }
                MenuRow(symbol: Symbol.saySomething, title: "Say something") {
                    close()
                    model.saySomething()
                }
                MenuRow(symbol: Symbol.copy, title: "Copy what happened") {
                    close()
                    model.copyWhatHappened()
                }
                MenuRow(symbol: Symbol.quit, title: "Quit Memnox", quiet: true) {
                    NSApp.terminate(nil)
                }
            }
            .settling(model.opened, order: 3)
        }
        .padding(Memnox.Spacing.large)
        .frame(width: Self.width)
        .background(
            shape.fill(Color.black)
                .overlay(
                    RadialGradient(
                        colors: [Memnox.Palette.primary.opacity(Layout.glowOpacity), .clear],
                        center: Layout.glowCenter,
                        startRadius: 0,
                        endRadius: Self.width
                    )
                )
                .clipShape(shape)
        )
        .overlay(shape.strokeBorder(Color.white.opacity(Layout.edgeInk), lineWidth: Memnox.Stroke.hairline))
    }

    private var header: some View {
        HStack(spacing: MenuLayout.iconSpacing) {
            LogoMark(size: Layout.logoSize)
            Text("Memnox")
                .font(Memnox.display(Layout.titleSize))
                .foregroundStyle(Color.white)
            Spacer()
            HStack(spacing: Memnox.Spacing.small) {
                Circle()
                    .fill(model.wakeOn ? IslandPalette.green : Color.white.opacity(Layout.idleDotInk))
                    .frame(width: Layout.dotSize, height: Layout.dotSize)
                Text(model.wakeOn ? "Listening for its name" : "Here when you call")
                    .font(Memnox.sans(Memnox.TextSize.caption, .medium))
                    .foregroundStyle(Color.white.opacity(MenuLayout.mutedInk))
            }
            .padding(.horizontal, Layout.badgeHorizontalPadding)
            .padding(.vertical, Layout.badgeVerticalPadding)
            .background(Capsule().fill(Color.white.opacity(MenuLayout.softFill)))
            .animation(.easeOut(duration: Memnox.Motion.quick), value: model.wakeOn)
        }
        .padding(.horizontal, Memnox.Spacing.xSmall)
        .padding(.top, Memnox.Spacing.xSmall)
    }

    /// The one thing this panel is for, set apart as its own lit card.
    private var talkCard: some View {
        Button {
            close()
            model.talk()
        } label: {
            IslandCard(veil: Memnox.Palette.primary.opacity(Layout.talkVeilOpacity)) {
                HStack(spacing: MenuLayout.iconSpacing) {
                    Image(systemName: Symbol.talk)
                        .font(.system(size: Memnox.TextSize.headline, weight: .semibold))
                        .foregroundStyle(Memnox.Palette.sky)
                        .frame(width: Layout.talkIconSize, height: Layout.talkIconSize)
                        .background(Circle().fill(Memnox.Palette.primary.opacity(Layout.talkIconFillOpacity)))
                    VStack(alignment: .leading, spacing: MenuLayout.titleDetailSpacing) {
                        Text("Talk to Memnox")
                            .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                            .foregroundStyle(Color.white)
                        Text("Ask about your agents")
                            .font(Memnox.sans(Memnox.TextSize.caption))
                            .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                    }
                    Spacer()
                    HStack(spacing: Layout.keycapSpacing) {
                        Keycap(label: "\u{2325}")
                        Keycap(label: "Space")
                    }
                }
                .padding(Memnox.Spacing.large)
            }
        }
        .buttonStyle(MenuPress())
    }

    private var wakeRow: some View {
        SwitchRow(
            symbol: Symbol.wake,
            title: "Wake when I say \u{201C}Memnox\u{201D}",
            detail: "On this Mac only",
            isOn: Binding(get: { model.wakeOn }, set: { model.setWake($0) })
        )
    }
}

/// One action: an icon and a label, lit softly under the pointer.
struct MenuRow: View {
    let symbol: String
    let title: String
    var quiet = false
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
                    .foregroundStyle(Color.white.opacity(quiet ? MenuLayout.dimInk : MenuLayout.mutedInk))
                    .frame(width: MenuLayout.iconColumnWidth)
                Text(title)
                    .font(Memnox.sans(Memnox.TextSize.body, .medium))
                    .foregroundStyle(Color.white.opacity(quiet ? Memnox.Ink.secondary : Self.textInk))
                Spacer()
            }
            .padding(.horizontal, Memnox.Spacing.regular)
            .frame(height: Self.height)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: MenuLayout.rowCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(hovering ? MenuLayout.softFill : 0))
            )
            .animation(.easeOut(duration: Self.hoverFade), value: hovering)
        }
        .buttonStyle(MenuPress())
        .onHover { hovering = $0 }
    }
}

/// A setting that is on or off: an icon, a label with a line under it, and a switch.
struct SwitchRow: View {
    let symbol: String
    let title: String
    let detail: String
    @Binding var isOn: Bool

    private static let verticalPadding: CGFloat = 9

    var body: some View {
        HStack(spacing: MenuLayout.iconSpacing) {
            Image(systemName: symbol)
                .font(.system(size: Memnox.TextSize.body, weight: .medium))
                .foregroundStyle(Color.white.opacity(isOn ? MenuLayout.litInk : MenuLayout.dimInk))
                .frame(width: MenuLayout.iconColumnWidth)
            VStack(alignment: .leading, spacing: MenuLayout.titleDetailSpacing) {
                Text(title)
                    .font(Memnox.sans(Memnox.TextSize.body, .medium))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(Memnox.sans(Memnox.TextSize.caption))
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.tertiary))
            }
            Spacer(minLength: Memnox.Spacing.medium)
            Toggle("", isOn: $isOn)
                .toggleStyle(MemnoxSwitch())
                .labelsHidden()
        }
        .padding(.horizontal, MenuLayout.rowInset)
        .padding(.vertical, Self.verticalPadding)
        .contentShape(Rectangle())
        .onTapGesture { isOn.toggle() }
    }
}

/// Which voice speaks: Kokoro on this Mac and free, or the Mac's own.
enum VoiceChoice {
    static let kokoro = "kokoro"
    static let mac = "mac"
}

struct VoiceChoicePicker: View {
    @Binding var choice: String

    private enum Layout {
        static let spacing: CGFloat = 9
        /// The gap between the two segments, and around them inside their track.
        static let segmentGap: CGFloat = 3
        static let segmentTextSize: CGFloat = 12.5
        static let choiceSpring = Animation.spring(response: 0.3, dampingFraction: 0.8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            HStack(spacing: MenuLayout.iconSpacing) {
                Image(systemName: Symbol.voice)
                    .font(.system(size: Memnox.TextSize.body, weight: .medium))
                    .foregroundStyle(Color.white.opacity(MenuLayout.litInk))
                    .frame(width: MenuLayout.iconColumnWidth)
                Text("Voice")
                    .font(Memnox.sans(Memnox.TextSize.body, .medium))
                    .foregroundStyle(Color.white)
                Spacer()
                Text(detail)
                    .font(Memnox.sans(Memnox.TextSize.caption))
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.tertiary))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: Memnox.Motion.quick), value: choice)
            }
            HStack(spacing: Layout.segmentGap) {
                segment("Kokoro", VoiceChoice.kokoro)
                segment("Mac", VoiceChoice.mac)
            }
            .padding(Layout.segmentGap)
            .background(Capsule().fill(Color.white.opacity(Memnox.Ink.faintFill)))
        }
        .padding(.horizontal, MenuLayout.rowInset)
    }

    /// One choice: the island's white pill when it is the one speaking.
    private func segment(_ title: String, _ value: String) -> some View {
        let on = choice == value
        return Button {
            withAnimation(Layout.choiceSpring) { choice = value }
        } label: {
            Text(title)
                .font(Memnox.sans(Layout.segmentTextSize, .semibold))
                .foregroundStyle(on ? IslandPalette.primaryText : Color.white.opacity(MenuLayout.mutedInk))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Memnox.Spacing.small)
                .background(Capsule().fill(on ? IslandPalette.primaryFill : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(MenuPress())
    }

    private var detail: String {
        switch choice {
        case VoiceChoice.kokoro: return "Free, nothing leaves this Mac"
        default: return "The best voice installed"
        }
    }
}

/// A switch in the console blue, since the system one goes grey in a panel that is not key.
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
                    .fill(configuration.isOn ? Memnox.Palette.primary : Color.white.opacity(Layout.offTrackInk))
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
    }
}

/// A faint rule between the rows of one card.
private struct Divide: View {
    private static let ink = 0.05
    /// Starts under the row titles: the row's inset, its icon column and the gap after it.
    private static let indent = MenuLayout.rowInset + MenuLayout.iconColumnWidth + MenuLayout.iconSpacing

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(Self.ink))
            .frame(height: Memnox.Stroke.hairline)
            .padding(.leading, Self.indent)
    }
}

/// Gives a little when pressed, the same press as the island's buttons.
private struct MenuPress: ButtonStyle {
    private static let pressedScale: CGFloat = 0.97
    private static let press = Animation.spring(response: 0.2, dampingFraction: 0.6)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Self.pressedScale : 1)
            .animation(Self.press, value: configuration.isPressed)
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

/// Measures every row of the menu shares, so icons, labels and rules line up from row to row.
private enum MenuLayout {
    static let iconSpacing: CGFloat = 11
    static let iconColumnWidth: CGFloat = 18
    static let rowInset: CGFloat = 12
    static let rowCornerRadius: CGFloat = 11
    static let titleDetailSpacing: CGFloat = 1
    /// White for secondary icons and labels, between the shared secondary ink and full white.
    static let mutedInk = 0.6
    static let litInk = 0.75
    static let dimInk = 0.4
    /// The faint white behind a hovered row and the listening badge.
    static let softFill = 0.07
}
    static let liveWords = "text.bubble"
    static let rule = "shield.lefthalf.filled"

/// The SF Symbols the menu draws, one per row.
private enum Symbol {
    static let talk = "waveform"
    static let wake = "ear"
    static let speakUp = "bell"
    static let talkOver = "waveform.badge.mic"
    static let sounds = "speaker.wave.1"
    static let liveWords = "text.bubble"
    static let voice = "person.wave.2"
    static let setUp = "slider.horizontal.3"
    static let saySomething = "speaker.wave.2"
    static let copy = "doc.on.clipboard"
    static let quit = "power"
}
