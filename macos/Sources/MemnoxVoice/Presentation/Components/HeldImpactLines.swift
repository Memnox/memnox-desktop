import MemnoxVoiceCore
import SwiftUI

/// What a held action could affect, whether it can be undone and what was verified, in the machine's own sentences.
/// How each is known sits behind "More about this", never on the face of the card. Drawn by whichever card holds it.
struct HeldImpactLines: View {
    let impact: HeldImpact
    var ink: Color = Memnox.Console.ink
    var muted: Color = Memnox.ink(Memnox.Ink.secondary)
    var font: (CGFloat, Font.Weight) -> Font = { Memnox.sans($0, $1) }

    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            ForEach(impact.lines, id: \.label) { line in
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(line.label)
                        .font(font(Memnox.TextSize.caption, .regular))
                        .foregroundStyle(muted)
                    Text(line.text)
                        .font(font(Memnox.TextSize.footnote, .regular))
                        .foregroundStyle(ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            DisclosureGroup(isExpanded: $open) {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                    ForEach(Array(impact.evidence.enumerated()), id: \.offset) { _, each in
                        HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.small) {
                            Text(each.label)
                                .font(font(Memnox.TextSize.caption, .medium))
                                .foregroundStyle(ink)
                            Text(each.value)
                                .font(font(Memnox.TextSize.caption, .regular))
                                .foregroundStyle(muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.top, Memnox.Spacing.xSmall)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Text(HeldImpact.moreLabel)
                    .font(font(Memnox.TextSize.caption, .regular))
                    .foregroundStyle(muted)
            }
        }
    }
}
