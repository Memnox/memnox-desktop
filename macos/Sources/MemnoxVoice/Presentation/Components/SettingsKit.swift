import SwiftUI

/// The measures every Settings page is laid out with, taken from Vorssaint's own pages so the window reads as theirs
/// does: one centred column, cards with soft corners and no rim, and a tinted tile at the start of every row.
enum SettingsMetrics {
    /// The column a page never grows past, centred in a wider window.
    static let pageWidth: CGFloat = 760
    static let pagePadding: CGFloat = 22
    /// A little room above the page's title, so it does not sit hard under the header.
    static let pageTopPadding: CGFloat = 8
    /// Between the page's title and its cards, and between one card and the next.
    static let pageSpacing: CGFloat = 20
    static let cardRadius: CGFloat = 16
    static let cardPadding: CGFloat = 16
    /// Between a card's heading and its rows.
    static let cardSpacing: CGFloat = 13
    static let tileSide: CGFloat = 26
    static let tileRadius: CGFloat = 7
    static let tileSymbol: CGFloat = 12
    /// The tile's tint behind its symbol, faint enough that the symbol carries the colour.
    static let tileTint = 0.12
    static let rowSpacing: CGFloat = 12
    static let captionSpacing: CGFloat = 2
    /// Vorssaint's type: rows and buttons at 13, the line under a row at 12, and a group's title over its card at 15.
    static let rowTextSize: CGFloat = 13
    static let captionSize: CGFloat = 12
    static let pageTitleSize: CGFloat = 19
    /// Between a group's title and its card.
    static let sectionSpacing: CGFloat = 10
    /// How far a row reaches past its words when it lights under the pointer, so the light is not tight on the text.
    static let hoverInset: CGFloat = 8
    static let hoverRadius: CGFloat = 8
    /// Where a row's words start, so a line under a row lines up with its title rather than its tile.
    static let rowTextInset: CGFloat = tileSide + rowSpacing
    /// The console's setting card: padding 20, 16 between its heading and its rows.
    static let consoleCardPadding: CGFloat = 20
    static let consoleCardSpacing: CGFloat = 16
}

/// A symbol on a small rounded tile of its own tint, the mark at the start of every Settings row.
struct IconTile: View {
    let symbol: String
    var tint: Color?

    /// The console's stat icon: radius 6, the tint at 14 percent, its symbol half the tile at the stroke of its words.
    private static let consoleTint = 0.14
    private static let consoleSymbolShare: CGFloat = 0.5

    var body: some View {
        let ink = tint ?? LookTokens.console.primary
        Image(systemName: symbol)
            .font(.system(size: SettingsMetrics.tileSide * Self.consoleSymbolShare,
                          weight: .regular))
            .foregroundStyle(ink)
            .frame(width: SettingsMetrics.tileSide, height: SettingsMetrics.tileSide)
            .background(ink.opacity(Self.consoleTint),
                        in: RoundedRectangle(cornerRadius: Memnox.Console.controlRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// One rounded group of related rows on a Settings page, with an optional heading.
struct SettingsCard<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: SettingsMetrics.consoleCardSpacing) {
            if let title {
                Text(title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.base, .medium))
                    .foregroundStyle(LookTokens.console.foreground)
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SettingsMetrics.consoleCardPadding)
        .background(LookTokens.console.card, in: shape)
        // The console reads a card by its border rather than its fill.
        .overlay(shape.strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
    }
}

/// A tile, a title with one line under it, and the control at the end of the row.
struct SettingsRow<Accessory: View>: View {
    let symbol: String
    let title: String
    var caption: String?
    var tint: Color?
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: SettingsMetrics.rowSpacing) {
            IconTile(symbol: symbol, tint: tint)
            VStack(alignment: .leading, spacing: SettingsMetrics.captionSpacing) {
                Text(title)
                    .font(Memnox.Console.sans(SettingsMetrics.rowTextSize, .medium))
                    .foregroundStyle(LookTokens.console.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption {
                    // Wraps, since a caption cut off mid sentence hides what the row does.
                    Text(caption)
                        .font(Memnox.Console.sans(SettingsMetrics.captionSize))
                        .foregroundStyle(LookTokens.console.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: SettingsMetrics.rowSpacing)
            accessory
        }
        .accessibilityElement(children: .contain)
    }
}

extension SettingsRow where Accessory == EmptyView {
    init(symbol: String, title: String, caption: String? = nil, tint: Color? = nil) {
        self.init(symbol: symbol, title: title, caption: caption, tint: tint) { EmptyView() }
    }
}

/// The rule between two rows of one card, starting under the titles as Vorssaint draws it, or across the card for
/// rows with no tile.
struct SettingsDivider: View {
    var full = false

    var body: some View {
        Rectangle()
            .fill(LookTokens.console.border)
            .frame(height: Memnox.Stroke.hairline)
            .padding(.leading, full ? 0 : SettingsMetrics.rowTextInset)
    }
}

/// A group's title over its card, as Vorssaint heads "Quick panel" or "Mute microphone", with anything that belongs
/// beside the title, such as a count, at its end.
struct SettingsSection<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.sectionSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.base, .medium))
                    .foregroundStyle(LookTokens.console.foreground)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: SettingsMetrics.rowSpacing)
                trailing
            }
            .padding(.horizontal, Memnox.Spacing.xxSmall)
            content
        }
    }
}

extension SettingsSection where Trailing == EmptyView {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

/// Lights a clickable row under the pointer with Vorssaint's soft fill and shows the pointing hand, so anything that
/// can be clicked says so before it is.
struct HoverLight: ViewModifier {
    var radius: CGFloat = SettingsMetrics.hoverRadius
    var inset: CGFloat = SettingsMetrics.hoverInset
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    func body(content: Content) -> some View {
        content
            .background(
                // The console folds every control's corner to 6, so a lit row matches the buttons beside it.
                RoundedRectangle(cornerRadius: min(radius, Memnox.Console.controlRadius), style: .continuous)
                    .fill(LookTokens.console.hover.opacity(hovering && enabled ? 1 : 0))
                    .padding(.horizontal, -inset)
            )
            .animation(.easeOut(duration: Memnox.Motion.quick), value: hovering)
            .onHover { hovering = $0 }
            .pointingHand()
    }
}

extension View {
    func hoverLight(radius: CGFloat = SettingsMetrics.hoverRadius, inset: CGFloat = SettingsMetrics.hoverInset) -> some View {
        modifier(HoverLight(radius: radius, inset: inset))
    }
}

/// A page's column: its title in the title font, then its cards, centred and never wider than a comfortable read. In
/// the Memnox window the shell's heading takes the title's place, the sub navigation beside it, and the cards keep
/// their comfortable width inside the pane.
struct SettingsColumn<Content: View>: View {
    /// Nil for a page that opens on its own greeting, such as the overview.
    var title: String?
    var subtitle: String?
    /// True for a page laid out as a grid, which takes the window's full page width rather than a reading column.
    var wide = false
    @ViewBuilder let content: Content
    @Environment(\.paneHeading) private var heading

    var body: some View {
        if let heading {
            headed(heading)
        } else {
            plain
        }
    }

    private func headed(_ heading: PaneHeading) -> some View {
        GeometryReader { geometry in
            ScrollView {
                PaneFrame(heading: heading, width: min(geometry.size.width - ShellMetrics.pagePadding * 2, ShellMetrics.pageWidth)) {
                    VStack(alignment: .leading, spacing: SettingsMetrics.pageSpacing) { content }
                        .frame(maxWidth: wide ? ShellMetrics.pageWidth : SettingsMetrics.pageWidth, alignment: .leading)
                }
                .frame(maxWidth: ShellMetrics.pageWidth, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, ShellMetrics.pagePadding)
                .padding(.top, ShellMetrics.pageTop)
                .padding(.bottom, ShellMetrics.pageBottom)
            }
            .scrollIndicators(.automatic)
        }
        .clipped()
    }

    private var plain: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsMetrics.pageSpacing) {
                if let title {
                    PageTitle(title: title, subtitle: subtitle)
                }
                content
            }
            .frame(maxWidth: SettingsMetrics.pageWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, SettingsMetrics.pagePadding)
            .padding(.top, SettingsMetrics.pageTopPadding)
            .padding(.bottom, SettingsMetrics.pagePadding)
        }
        .scrollIndicators(.never)
        // Kept below the header, so a long page never scrolls up under Back and Forward.
        .clipped()
    }
}

/// A page's heading, as the console's page header: an optional line above, a 24 semibold title, and its line 13 muted.
struct PageTitle: View {
    var eyebrow: String?
    let title: String
    var subtitle: String?

    private static let subtitleWidth: CGFloat = 672

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            if let eyebrow {
                Text(eyebrow)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(LookTokens.console.muted)
            }
            Text(title)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.title, .semibold))
                .tracking(Memnox.Console.titleTracking)
                .foregroundStyle(LookTokens.console.foreground)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(Memnox.Console.sans(SettingsMetrics.rowTextSize))
                    .foregroundStyle(LookTokens.console.muted)
                    .lineSpacing(Memnox.Spacing.xxSmall)
                    .frame(maxWidth: Self.subtitleWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
