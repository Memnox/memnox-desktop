import SwiftUI

/// Counts the dialogs open over the Memnox window, so the shell blurs and dims the page behind every one of them the
/// same way the console does, whichever page opened it.
@MainActor
final class ModalBackdrop: ObservableObject {
    @Published private(set) var open = 0

    var showing: Bool { open > 0 }

    func opened() { open += 1 }
    func closed() { open = max(0, open - 1) }
}

private struct ModalBackdropKey: EnvironmentKey {
    static let defaultValue: ModalBackdrop? = nil
}

extension EnvironmentValues {
    /// The window's backdrop, nil outside the Memnox window, where a dialog opens without the blur.
    var modalBackdrop: ModalBackdrop? {
        get { self[ModalBackdropKey.self] }
        set { self[ModalBackdropKey.self] = newValue }
    }
}

/// The measures of the blur behind a dialog, the console's own.
enum ModalMetrics {
    static let blur: CGFloat = 8
    static let scrim = 0.55
    static let confirmWidth: CGFloat = 440
    static let confirmPadding: CGFloat = 28
    static let iconTile: CGFloat = 48
    static let iconSize: CGFloat = 20
    static let iconTint = 0.16
}

extension View {
    /// A sheet that blurs and dims the window behind it while it is open, as every console dialog does.
    func consoleSheet<Sheet: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Sheet) -> some View {
        modifier(ConsoleSheet(isPresented: isPresented, sheet: content))
    }

    /// The same, opened for one item and closed when the item goes.
    func consoleSheet<Item: Identifiable, Sheet: View>(item: Binding<Item?>,
                                                       @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
        modifier(ConsoleItemSheet(item: item, sheet: content))
    }
}

private struct ConsoleSheet<Sheet: View>: ViewModifier {
    @Binding var isPresented: Bool
    let sheet: () -> Sheet
    @Environment(\.modalBackdrop) private var backdrop

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            sheet().modifier(BackdropTracker(backdrop: backdrop))
        }
    }
}

private struct ConsoleItemSheet<Item: Identifiable, Sheet: View>: ViewModifier {
    @Binding var item: Item?
    let sheet: (Item) -> Sheet
    @Environment(\.modalBackdrop) private var backdrop

    func body(content: Content) -> some View {
        content.sheet(item: $item) { each in
            sheet(each).modifier(BackdropTracker(backdrop: backdrop))
        }
    }
}

/// Tells the backdrop a dialog is up for as long as its content is on screen, and wears the console's card behind it.
private struct BackdropTracker: ViewModifier {
    let backdrop: ModalBackdrop?

    func body(content: Content) -> some View {
        content
            .consoleLook()
            .presentationBackground(Memnox.Console.card)
            .onAppear { backdrop?.opened() }
            .onDisappear { backdrop?.closed() }
    }
}

/// The console's confirm dialog: a tinted icon tile, the question, what follows from it, then Cancel and the act side by
/// side, the act in red when it takes something away. In place of the system's alert, which wears none of the console.
struct ConsoleConfirm: View {
    let symbol: String
    let title: String
    let message: String
    var detail: String?
    let confirm: String
    var destructive = true
    /// A quieter way out that goes somewhere instead of only closing, such as reading first; nil leaves Cancel alone.
    var aside: String?
    var asideAct: (() -> Void)?
    let cancel: () -> Void
    let act: () -> Void

    var body: some View {
        let tint = destructive ? Memnox.Console.destructive : Memnox.Console.primary
        VStack(alignment: .leading, spacing: Memnox.Spacing.xLarge) {
            Image(systemName: symbol)
                .font(.system(size: ModalMetrics.iconSize, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: ModalMetrics.iconTile, height: ModalMetrics.iconTile)
                .background(tint.opacity(ModalMetrics.iconTint),
                            in: RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
                Text(title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.large, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .foregroundStyle(Memnox.Console.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .foregroundStyle(Memnox.Console.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall))
            if let aside, let asideAct {
                Button(aside, action: asideAct)
                    .buttonStyle(.plain)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                    .foregroundStyle(Memnox.Console.primary)
                    .pointingHand()
            }
            HStack(spacing: Memnox.Spacing.medium) {
                Button("Cancel", action: cancel)
                    .buttonStyle(KitButton(kind: .secondary, wide: true))
                    .keyboardShortcut(.cancelAction)
                Button(action: act) {
                    Text(confirm)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: Memnox.Console.controlHeight)
                        .background(tint, in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous))
                }
                .buttonStyle(PressDip())
                .pointingHand()
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, Memnox.Spacing.small)
        }
        .padding(ModalMetrics.confirmPadding)
        .frame(width: ModalMetrics.confirmWidth, alignment: .leading)
    }
}
