import AppKit
import MemnoxVoiceCore
import SwiftUI

/// Shown while Control and Option are held, so the person knows this is a rule being taken down.
struct RuleModeChip: View {
    private static let symbol = "shield.lefthalf.filled"
    private static let fill = 0.22

    var body: some View {
        HStack(spacing: Memnox.Spacing.xSmall) {
            Image(systemName: Self.symbol)
            Text("Rule")
        }
        .font(Memnox.sans(Memnox.TextSize.footnote, .semibold))
        .foregroundStyle(IslandPalette.amber.liftedTowardWhite)
        .padding(.horizontal, Memnox.Spacing.regular)
        .padding(.vertical, Memnox.Spacing.xSmall)
        .background(Capsule().fill(IslandPalette.amber.opacity(Self.fill)))
    }
}

/// A rule the person said, as the brain wrote it: what it decides, what it matches and why, then
/// the places it could hold. The place picked is what Touch ID signs, so the reach is theirs alone,
/// and nothing is in force until they sign.
struct IslandRuleCard: View {
    @ObservedObject var model: IslandModel
    let card: RuleCard

    private enum Layout {
        static let padding: CGFloat = 14
        static let labelWidth: CGFloat = 70
        static let detailSize: CGFloat = 12.5
        /// Three places in view, the rest a scroll away, so the answers never leave the card.
        static let placesHeight: CGFloat = 138
    }

    private enum Shade {
        static let veil = 0.3
        static let chip = 0.2
        static let sending = 0.55
    }

    private enum Symbol {
        static let rule = "shield.lefthalf.filled"
        static let touchID = "touchid"
    }

    var body: some View {
        let draft = card.draft
        IslandCard(veil: tint.opacity(Shade.veil)) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.regular) {
                header
                Text(sentence(draft.summary))
                    .font(Memnox.sans(Memnox.TextSize.headline, .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(2)
                details(draft)
                Text("Where should it hold?")
                    .font(Memnox.sans(Memnox.TextSize.footnote, .semibold))
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.tertiary))
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: Memnox.Spacing.xSmall) {
                        ForEach(draft.scopes) { scope in
                            PlaceRow(scope: scope, picked: picked?.id == scope.id) { model.ruleScope = scope.id }
                        }
                    }
                }
                .frame(maxHeight: Layout.placesHeight)
                Spacer(minLength: 0)
                answers
            }
            .padding(Layout.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var header: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Image(systemName: Symbol.rule).foregroundStyle(tint)
            Text("New rule")
                .font(Memnox.sans(Memnox.TextSize.callout, .semibold))
                .foregroundStyle(Color.white)
            Spacer()
            Text(effectWord)
                .font(Memnox.sans(Memnox.TextSize.footnote, .semibold))
                .foregroundStyle(tint.liftedTowardWhite)
                .padding(.horizontal, Memnox.Spacing.regular)
                .padding(.vertical, Memnox.Spacing.xSmall)
                .background(Capsule().fill(tint.opacity(Shade.chip)))
        }
    }

    private func details(_ draft: RuleDraft) -> some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
            detail("Action", draft.action, code: true)
            if let branches = draft.branches, !branches.isEmpty { detail("Branches", branches.joined(separator: ", "), code: true) }
            if let targets = draft.targets, !targets.isEmpty { detail("Paths", targets.joined(separator: ", "), code: true) }
            detail("Why", draft.reason, code: false)
        }
    }

    private func detail(_ label: String, _ value: String, code: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Memnox.Spacing.medium) {
            Text(label)
                .font(Memnox.sans(Layout.detailSize))
                .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                .frame(width: Layout.labelWidth, alignment: .leading)
            Text(value)
                .font(code ? .system(size: Layout.detailSize, design: .monospaced) : Memnox.sans(Layout.detailSize))
                .foregroundStyle(IslandPalette.soft)
                .lineLimit(2)
        }
    }

    private var answers: some View {
        HStack(spacing: Memnox.Spacing.medium) {
            Button("Not now") { answer(nil) }.buttonStyle(IslandButton(primary: false))
            Spacer()
            Button { answer(picked) } label: {
                HStack(spacing: Memnox.Spacing.small) {
                    Image(systemName: Symbol.touchID)
                    Text(picked.map { "Enforce \(placeWords($0))" } ?? "Enforce")
                        .lineLimit(1)
                }
            }
            .buttonStyle(IslandButton(primary: true))
            .disabled(picked == nil)
        }
        .disabled(model.sending)
        .opacity(model.sending ? Shade.sending : 1)
    }

    /// The place the person picked, or the suggested one until they pick.
    private var picked: RuleScope? {
        card.draft.scopes.first { $0.id == model.ruleScope } ?? card.draft.suggestedScope
    }

    private func answer(_ scope: RuleScope?) {
        model.sending = scope != nil
        model.answerRule(card, scope)
    }

    private var tint: Color {
        switch card.draft.ruleEffect {
        case .deny: return IslandPalette.red
        case .ask: return IslandPalette.amber
        case .allow: return IslandPalette.green
        case nil: return IslandPalette.indigo
        }
    }

    private var effectWord: String {
        switch card.draft.ruleEffect {
        case .deny: return "Deny"
        case .ask: return "Ask first"
        case .allow: return "Allow"
        case nil: return card.draft.effect
        }
    }
}

/// "on this Mac" or "in shop", the way the button and the voice say where a rule holds.
func placeWords(_ scope: RuleScope) -> String {
    scope.scopeKind == .repository ? "in \(scope.label)" : "on this Mac"
}

/// The runtime's summary as a sentence, its first letter raised.
private func sentence(_ text: String) -> String {
    text.prefix(1).uppercased() + text.dropFirst()
}

/// One place a rule can hold: the whole Mac, or a repository with where it is.
private struct PlaceRow: View {
    let scope: RuleScope
    let picked: Bool
    let pick: () -> Void
    @State private var hovering = false

    private enum Layout {
        static let radius: CGFloat = 12
        static let horizontal: CGFloat = 10
        static let vertical: CGFloat = 7
        static let iconWidth: CGFloat = 18
    }

    private enum Shade {
        static let picked = 0.14
        static let hover = 0.06
        static let ring = 0.55
    }

    private enum Symbol {
        static let machine = "desktopcomputer"
        static let repository = "folder"
        static let picked = "checkmark.circle.fill"
        static let unpicked = "circle"
    }

    var body: some View {
        Button(action: pick) {
            HStack(spacing: Memnox.Spacing.regular) {
                Image(systemName: scope.scopeKind == .repository ? Symbol.repository : Symbol.machine)
                    .foregroundStyle(Color.white.opacity(Memnox.Ink.secondary))
                    .frame(width: Layout.iconWidth)
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxSmall) {
                    Text(scope.label)
                        .font(Memnox.sans(Memnox.TextSize.body, .semibold))
                        .foregroundStyle(Color.white)
                    Text(detail)
                        .font(Memnox.sans(Memnox.TextSize.caption))
                        .foregroundStyle(IslandPalette.quiet)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                Image(systemName: picked ? Symbol.picked : Symbol.unpicked)
                    .foregroundStyle(picked ? Memnox.Palette.primary : Color.white.opacity(Memnox.Ink.tertiary))
            }
            .padding(.horizontal, Layout.horizontal)
            .padding(.vertical, Layout.vertical)
            .background(
                RoundedRectangle(cornerRadius: Layout.radius)
                    .fill(Color.white.opacity(picked ? Shade.picked : hovering ? Shade.hover : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.radius)
                    .strokeBorder(Memnox.Palette.primary.opacity(picked ? Shade.ring : 0), lineWidth: Memnox.Stroke.hairline)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hovering = $0 }
    }

    /// What holding there means, in a few words: every agent everywhere, or only those working in that folder.
    private var detail: String {
        guard scope.scopeKind == .repository, let folder = scope.folder else { return "Every agent, in every folder" }
        return "Only agents in \((folder as NSString).abbreviatingWithTildeInPath)"
    }
}
