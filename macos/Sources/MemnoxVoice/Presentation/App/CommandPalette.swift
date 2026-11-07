import MemnoxVoiceCore
import SwiftUI

/// Go to any destination or tab by typing a word of it, then Return; the arrows move, Escape closes.
struct CommandPalette: View {
    let supports: Supports
    let go: (WindowRoute) -> Void
    let close: () -> Void

    @State private var query = ""
    @State private var at = 0
    @FocusState private var typing: Bool

    private enum Layout {
        static let width: CGFloat = 560
        static let listHeight: CGFloat = 340
        static let fieldHeight: CGFloat = 48
        static let topShare: CGFloat = 0.12
        static let scrim = 0.4
    }

    var body: some View {
        let found = Destinations.matchCommands(query, supports: supports)
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.black.opacity(Layout.scrim)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
                    .accessibilityHidden(true)
                panel(found)
                    .padding(.top, geometry.size.height * Layout.topShare)
                    .padding(.horizontal, Memnox.Spacing.xLarge)
            }
        }
        .onAppear { typing = true }
        .onChange(of: query) { _, _ in at = 0 }
    }

    private func panel(_ found: [PaletteCommand]) -> some View {
        // The console's palette: a bordered card at radius 12, lifted off the page by a long soft shadow.
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
        return VStack(spacing: 0) {
            HStack(spacing: Memnox.Spacing.regular) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Memnox.Console.muted)
                    .accessibilityHidden(true)
                TextField("Go to a page, such as servers or approvals", text: $query)
                    .textFieldStyle(.plain)
                    .font(Memnox.Console.sans(Memnox.TextSize.callout))
                    .focused($typing)
                    .accessibilityLabel("Go to")
                    .onSubmit { choose(found) }
                    .onKeyPress(.downArrow) {
                        at = min(found.count - 1, at + 1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        at = max(0, at - 1)
                        return .handled
                    }
                    .onExitCommand(perform: close)
            }
            .padding(.horizontal, Memnox.Spacing.xLarge)
            .frame(height: Layout.fieldHeight)
            ShellDivider()
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(spacing: Memnox.Spacing.xxSmall) {
                        if found.isEmpty {
                            Text("Nothing here by that name.")
                                .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                                .foregroundStyle(Memnox.Console.muted)
                                .padding(.vertical, Memnox.Spacing.xxLarge)
                        }
                        ForEach(Array(found.enumerated()), id: \.element.id) { index, each in
                            row(each, chosen: index == at)
                                .id(index)
                                .onHover { if $0 { at = index } }
                        }
                    }
                    .padding(Memnox.Spacing.small)
                }
                .frame(maxHeight: Layout.listHeight)
                .onChange(of: at) { _, now in scroller.scrollTo(now) }
            }
        }
        .frame(maxWidth: Layout.width)
        .background(Memnox.Console.card, in: shape)
        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
        .clipShape(shape)
        .shadow(color: .black.opacity(Memnox.Console.liftShadow), radius: Memnox.Console.liftRadius, y: Memnox.Console.liftDrop)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Go to")
        .accessibilityAddTraits(.isModal)
    }

    private func row(_ each: PaletteCommand, chosen: Bool) -> some View {
        Button { go(each.route) } label: {
            HStack(spacing: Memnox.Spacing.large) {
                Text(each.title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, chosen ? .medium : .regular))
                    .foregroundStyle(Memnox.Console.foreground)
                    .lineLimit(1)
                Spacer(minLength: Memnox.Spacing.medium)
                if !each.under.isEmpty {
                    Text(each.under)
                        .font(Memnox.Console.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.Console.muted)
                }
                if let key = each.key {
                    Keycap(label: ShellLines.shortcutWords(key, mac: true))
                }
                Image(systemName: "return")
                    .font(.system(size: Memnox.TextSize.caption))
                    .foregroundStyle(Memnox.Console.muted)
                    .opacity(chosen ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Memnox.Spacing.large)
            .padding(.vertical, Memnox.Spacing.medium)
            .background(chosen ? Memnox.Console.active : Color.clear,
                        in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(each.under.isEmpty ? each.title : "\(each.title), in \(each.under)")
        .accessibilityHint(each.key.map { "Command \($0)" } ?? "")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func choose(_ found: [PaletteCommand]) {
        guard found.indices.contains(at) else { return }
        go(found[at].route)
    }
}
