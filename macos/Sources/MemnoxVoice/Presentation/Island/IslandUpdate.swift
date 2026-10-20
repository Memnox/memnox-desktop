import MemnoxVoiceCore
import SwiftUI

/// Under the notch while a newer Memnox is published: its version, Update and Later. While it installs the buttons
/// give way to a spinner, and a try that stopped short says why and offers Update again.
struct IslandUpdatePill: View {
    @ObservedObject var model: IslandModel
    let card: UpdateCard
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 6
        /// Wide enough for a reason in two short lines, so a failure never pushes the pill past the island.
        static let failedWidth: CGFloat = 300
    }

    private enum Symbol {
        static let ready = "arrow.down.circle.fill"
        static let failed = "exclamationmark.circle.fill"
    }

    var body: some View {
        HStack(spacing: Memnox.Spacing.small) {
            Image(systemName: card.failed == nil ? Symbol.ready : Symbol.failed)
                .font(.system(size: Memnox.TextSize.caption))
                .foregroundStyle(card.failed == nil ? IslandPalette.green : IslandPalette.amber)
                .accessibilityHidden(true)
            Text(words)
                .font(Memnox.sans(Memnox.TextSize.caption, .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(card.failed == nil ? 1 : 2)
                .frame(maxWidth: card.failed == nil ? nil : Layout.failedWidth, alignment: .leading)
                .fixedSize(horizontal: card.failed == nil, vertical: true)
            if card.installing {
                ProgressView().controlSize(.mini)
            } else {
                Button("Later") { model.laterUpdate(card) }
                    .buttonStyle(IslandButton(primary: false))
                    .help("Not this version")
                Button(card.failed == nil ? "Update" : "Try again") { model.installUpdate(card) }
                    .buttonStyle(IslandButton(primary: true))
                    .help("Download Memnox \(card.release.version) and open it")
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().strokeBorder(Color.white.opacity(Memnox.Ink.edge)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(words)
        .animation(reduceMotion ? nil : .snappy, value: card)
    }

    private var words: String {
        if let failed = card.failed { return failed }
        return card.installing ? "Updating to Memnox \(card.release.version)" : "Memnox \(card.release.version) is ready"
    }
}
