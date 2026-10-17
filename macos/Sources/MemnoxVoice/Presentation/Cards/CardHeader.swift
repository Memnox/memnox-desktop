import SwiftUI

/// The measurements every floating card shares, so a summary, a walk, a trace and a session read as one family.
enum FloatingCard {
    /// The mark and the agent's logo stand at one size, so a card's identity sits in the same place on each.
    static let markSize: CGFloat = 28
    static let titleSize: CGFloat = 22
    static let titleLineLimit = 2
    static let subtitleLineLimit = 1
    /// Room enough inside a card that is read at arm's length while the voice speaks.
    static let padding: CGFloat = Memnox.Spacing.xxLarge
}

/// The one header every card carries: who it is from, what it is, a quiet line of context, anything
/// the card needs beside the title, and the close cross, which also answers to Escape.
struct CardHeader<Mark: View, Accessory: View>: View {
    let title: String
    var subtitle: String?
    let close: () -> Void
    @ViewBuilder let mark: () -> Mark
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: Memnox.Spacing.regular) {
            mark()
                .frame(width: FloatingCard.markSize, height: FloatingCard.markSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                Text(title)
                    .font(Memnox.display(FloatingCard.titleSize))
                    .foregroundStyle(Memnox.Palette.foreground)
                    .lineLimit(FloatingCard.titleLineLimit)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(Memnox.sans(Memnox.TextSize.footnote))
                        .foregroundStyle(Memnox.Palette.muted)
                        .lineLimit(FloatingCard.subtitleLineLimit)
                }
            }
            Spacer(minLength: Memnox.Spacing.medium)
            accessory()
            CloseButton(action: close)
        }
    }
}

extension CardHeader where Accessory == EmptyView {
    init(title: String, subtitle: String? = nil, close: @escaping () -> Void, @ViewBuilder mark: @escaping () -> Mark) {
        self.init(title: title, subtitle: subtitle, close: close, mark: mark, accessory: { EmptyView() })
    }
}
