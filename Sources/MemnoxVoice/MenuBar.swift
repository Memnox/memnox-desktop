import AppKit
import SwiftUI

/// What the menu bar panel shows, and what each of its rows does, handed in by the app.
@MainActor
final class MenuModel: ObservableObject {
    @Published var wakeOn: Bool
    @Published var speakUpOn: Bool
    @Published var talkOverOn: Bool
    @Published var chimesOn: Bool
    @Published var voiceChoice: String
    /// Counted each time the panel opens, so its sections can settle in one after another.
    @Published var opened = 0
    let talk: () -> Void
    let setWake: (Bool) -> Void
    let setSpeakUp: (Bool) -> Void
    let setTalkOver: (Bool) -> Void
    let setChimes: (Bool) -> Void
    let chooseVoice: (String) -> Void
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
        chimesOn: Bool,
        setChimes: @escaping (Bool) -> Void,
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
        self.talkOverOn = talkOverOn
        self.setTalkOver = setTalkOver
        self.chimesOn = chimesOn
        self.setChimes = setChimes
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
    private var outside: Any?
    private var escape: Any?
    /// The gap between the menu bar icon and the top of the panel, as a menu leaves.
    private static let gap: CGFloat = 6

    init(model: MenuModel) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 292, height: 400),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        var close: () -> Void = {}
        host = FirstClickHosting(rootView: MenuView(model: model) { close() })
        super.init()
        close = { [weak self] in self?.dismiss() }
        item.button?.image = MemnoxLogo.menuBar
            ?? NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Memnox")
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
        let x = min(max(icon.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        let y = max(min(icon.minY - Self.gap, screen.maxY) - size.height, screen.minY + 8)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.16; panel.animator().alphaValue = 1 }
        host.rootView.model.opened += 1
        watchForDismissal()
    }

    /// A click anywhere else, or Escape, closes it the way a menu closes.
    private func watchForDismissal() {
        outside = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.dismiss()
            return nil
        }
    }

    private func dismiss() {
        if let outside { NSEvent.removeMonitor(outside) }
        if let escape { NSEvent.removeMonitor(escape) }
        outside = nil
        escape = nil
        panel.orderOut(nil)
    }
}

struct MenuView: View {
    @ObservedObject var model: MenuModel
    let close: () -> Void
    static let width: CGFloat = 300

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            header
            talkCard
                .settling(model.opened, order: 0)
            IslandCard(veil: nil) {
                VStack(spacing: 0) {
                    wakeRow
                    Divide()
                    SwitchRow(symbol: "bell", title: "Speak up on its own", detail: "When work finishes or ships", isOn: Binding(get: { model.speakUpOn }, set: { model.speakUpOn = $0; model.setSpeakUp($0) }))
                    Divide()
                    SwitchRow(symbol: "waveform.badge.mic", title: "Talk over it", detail: "Cut in just by speaking", isOn: Binding(get: { model.talkOverOn }, set: { model.talkOverOn = $0; model.setTalkOver($0) }))
                    Divide()
                    SwitchRow(symbol: "speaker.wave.1", title: "Sounds", detail: "A chime when something happens", isOn: Binding(get: { model.chimesOn }, set: { model.chimesOn = $0; model.setChimes($0) }))
                }
                .padding(.vertical, 4)
            }
            .settling(model.opened, order: 1)
            IslandCard(veil: nil) {
                VoiceChoicePicker(choice: Binding(get: { model.voiceChoice }, set: { model.voiceChoice = $0; model.chooseVoice($0) }))
                    .padding(.vertical, 6)
            }
            .settling(model.opened, order: 2)
            VStack(spacing: 2) {
                MenuRow(symbol: "slider.horizontal.3", title: "Set up Memnox") {
                    close()
                    model.setUp()
                }
                MenuRow(symbol: "speaker.wave.2", title: "Say something") {
                    close()
                    model.saySomething()
                }
                MenuRow(symbol: "doc.on.clipboard", title: "Copy what happened") {
                    close()
                    model.copyWhatHappened()
                }
                MenuRow(symbol: "power", title: "Quit Memnox", quiet: true) {
                    NSApp.terminate(nil)
                }
            }
            .settling(model.opened, order: 3)
        }
        .padding(12)
        .frame(width: Self.width)
        .background(
            shape.fill(Color.black)
                .overlay(
                    RadialGradient(
                        colors: [Memnox.Palette.primary.opacity(0.16), .clear],
                        center: UnitPoint(x: 0.5, y: 1.15),
                        startRadius: 0,
                        endRadius: Self.width
                    )
                )
                .clipShape(shape)
        )
        .overlay(shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: 11) {
            LogoMark(size: 24)
            Text("Memnox")
                .font(Memnox.display(21))
                .foregroundStyle(Color.white)
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(model.wakeOn ? IslandPalette.green : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)
                Text(model.wakeOn ? "Listening for its name" : "Here when you call")
                    .font(Memnox.sans(11, .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.07)))
            .animation(.easeOut(duration: 0.2), value: model.wakeOn)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    /// The one thing this panel is for, set apart as its own lit card.
    private var talkCard: some View {
        Button {
            close()
            model.talk()
        } label: {
            IslandCard(veil: Memnox.Palette.primary.opacity(0.45)) {
                HStack(spacing: 11) {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Memnox.Palette.sky)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Memnox.Palette.primary.opacity(0.22)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Talk to Memnox")
                            .font(Memnox.sans(14, .semibold))
                            .foregroundStyle(Color.white)
                        Text("Ask about your agents")
                            .font(Memnox.sans(11))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    Spacer()
                    HStack(spacing: 3) {
                        Keycap(label: "\u{2325}")
                        Keycap(label: "Space")
                    }
                }
                .padding(12)
            }
        }
        .buttonStyle(MenuPress())
    }

    private var wakeRow: some View {
        SwitchRow(
            symbol: "ear",
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(quiet ? 0.4 : 0.6))
                    .frame(width: 18)
                Text(title)
                    .font(Memnox.sans(13, .medium))
                    .foregroundStyle(Color.white.opacity(quiet ? 0.5 : 0.9))
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(hovering ? 0.07 : 0))
            )
            .animation(.easeOut(duration: 0.12), value: hovering)
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

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(isOn ? 0.75 : 0.4))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Memnox.sans(13, .medium))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(Memnox.sans(11))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .toggleStyle(MemnoxSwitch())
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                Image(systemName: "person.wave.2")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .frame(width: 18)
                Text("Voice")
                    .font(Memnox.sans(13, .medium))
                    .foregroundStyle(Color.white)
                Spacer()
                Text(detail)
                    .font(Memnox.sans(11))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: choice)
            }
            HStack(spacing: 3) {
                segment("Kokoro", VoiceChoice.kokoro)
                segment("Mac", VoiceChoice.mac)
            }
            .padding(3)
            .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .padding(.horizontal, 12)
    }

    /// One choice: the island's white pill when it is the one speaking.
    private func segment(_ title: String, _ value: String) -> some View {
        let on = choice == value
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { choice = value }
        } label: {
            Text(title)
                .font(Memnox.sans(12.5, .semibold))
                .foregroundStyle(on ? IslandPalette.primaryText : Color.white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
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
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? Memnox.Palette.primary : Color.white.opacity(0.14))
                    .frame(width: 34, height: 20)
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .padding(2)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }
}

/// A faint rule between the rows of one card.
private struct Divide: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.05))
            .frame(height: 1)
            .padding(.leading, 41)
    }
}

/// Gives a little when pressed, the same press as the island's buttons.
private struct MenuPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
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

    func body(content: Content) -> some View {
        content
            .keyframeAnimator(initialValue: 1.0, trigger: opened) { view, value in
                view.opacity(value).offset(y: (1 - value) * 6)
            } keyframes: { _ in
                LinearKeyframe(0.0, duration: 0.001)
                LinearKeyframe(0.0, duration: 0.001 + 0.04 * Double(order))
                SpringKeyframe(1.0, duration: 0.32, spring: .smooth)
            }
    }
}
