import AppKit
import SwiftUI

/// What the menu bar panel shows, and what each of its rows does, handed in by the app.
@MainActor
final class MenuModel: ObservableObject {
    @Published var wakeOn: Bool
    let talk: () -> Void
    let setWake: (Bool) -> Void
    let setUp: () -> Void
    let saySomething: () -> Void
    let copyWhatHappened: () -> Void

    init(
        wakeOn: Bool,
        talk: @escaping () -> Void,
        setWake: @escaping (Bool) -> Void,
        setUp: @escaping () -> Void,
        saySomething: @escaping () -> Void,
        copyWhatHappened: @escaping () -> Void
    ) {
        self.wakeOn = wakeOn
        self.talk = talk
        self.setWake = setWake
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
    private let popover = NSPopover()

    init(model: MenuModel) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "Memnox")
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(
            rootView: MenuView(model: model) { [weak self] in self?.popover.performClose(nil) }
        )
    }

    @objc private func toggle() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        // Active, so a click anywhere else closes the panel the way a menu closes.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
}

struct MenuView: View {
    @ObservedObject var model: MenuModel
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Hairline()
            MenuRow(symbol: "waveform", title: "Talk to Memnox", prominent: true, trailing: AnyView(shortcut)) {
                close()
                model.talk()
            }
            wakeRow
            Hairline()
            MenuRow(symbol: "slider.horizontal.3", title: "Set Up Memnox") {
                close()
                model.setUp()
            }
            MenuRow(symbol: "speaker.wave.2", title: "Say Something") {
                close()
                model.saySomething()
            }
            MenuRow(symbol: "doc.on.clipboard", title: "Copy What Happened") {
                close()
                model.copyWhatHappened()
            }
            Hairline()
            MenuRow(symbol: "power", title: "Quit Memnox", quiet: true) {
                NSApp.terminate(nil)
            }
        }
        .padding(10)
        .frame(width: 292)
        .background(
            ZStack {
                Glass(material: .hudWindow)
                Memnox.Palette.background.opacity(0.2)
            }
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Memnox.Palette.sky, Memnox.Palette.deep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 26, height: 26)
                    .blur(radius: 8)
                    .opacity(0.8)
                Circle()
                    .fill(LinearGradient(colors: [Memnox.Palette.sky, Memnox.Palette.deep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 18, height: 18)
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Memnox")
                    .font(Memnox.display(22))
                    .foregroundStyle(Memnox.Palette.foreground)
                Text(model.wakeOn ? "Listening for its name" : "Here when you call")
                    .font(Memnox.sans(11))
                    .foregroundStyle(Memnox.Palette.muted)
            }
            Spacer()
            Circle()
                .fill(model.wakeOn ? Memnox.Palette.success : Memnox.Palette.border)
                .frame(width: 7, height: 7)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var shortcut: some View {
        HStack(spacing: 3) {
            Keycap(label: "⌥")
            Keycap(label: "Space")
        }
    }

    private var wakeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "ear")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Memnox.Palette.muted)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text("Wake when I say \u{201C}Memnox\u{201D}")
                    .font(Memnox.sans(13, .medium))
                    .foregroundStyle(Memnox.Palette.foreground)
                Text("On this Mac only")
                    .font(Memnox.sans(11))
                    .foregroundStyle(Memnox.Palette.muted)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { model.wakeOn }, set: { model.setWake($0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Memnox.Palette.primary)
                .labelsHidden()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
    }
}

/// One row: an icon, a label, and a quiet highlight under the pointer, as the console's lists do.
struct MenuRow: View {
    let symbol: String
    let title: String
    var prominent = false
    var quiet = false
    var trailing: AnyView?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(prominent ? Memnox.Palette.primary : Memnox.Palette.muted)
                    .frame(width: 18)
                Text(title)
                    .font(Memnox.sans(13, prominent ? .semibold : .medium))
                    .foregroundStyle(quiet ? Memnox.Palette.muted : Memnox.Palette.foreground)
                Spacer()
                if let trailing { trailing }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Memnox.radius)
                    .fill(Memnox.Palette.secondary.opacity(hovering ? 0.7 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Memnox.radius)
                    .strokeBorder(Memnox.Palette.border.opacity(hovering ? 0.8 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The console's border colour as a one point rule between groups.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Memnox.Palette.border.opacity(0.6))
            .frame(height: 1)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
    }
}
