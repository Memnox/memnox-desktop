import Foundation
import MemnoxVoiceCore
import SwiftUI

/// The words every rule dialog shares, the console's own except where this Mac signs in place of an admin approving.
enum RuleWords {
    /// Said under every propose dialog, since the signature on the island is the whole control here.
    static let proposeDescription = "It is proposed on this Mac and holds once you sign it with Touch ID on the island."
    static let propose = "Propose"
    static let proposing = "Proposing"
    static let cancel = "Cancel"
    static let whenTried = "When an agent tries it"
    static let recommended = "Suggested"
    static let preview = "The rule"
    static let optional = "(optional)"
}

/// A rule dialog's size, outside the generic dialog since a generic type cannot hold stored statics.
private enum RuleDialogLayout {
    static let width: CGFloat = 560
    static let maxHeight: CGFloat = 720
}

/// A rule dialog's frame: its title and the line under it, a scrolling body, and Cancel and Propose at the foot.
struct RuleDialog<Content: View>: View {
    let title: String
    /// The line under the title; Review and save says its own, since it saves several changes at once.
    var description = RuleWords.proposeDescription
    /// The press at the foot, idle and busy, Propose unless the dialog saves.
    var confirm = (idle: RuleWords.propose, busy: RuleWords.proposing)
    let proposing: Bool
    let canPropose: Bool
    let close: () -> Void
    let propose: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                Text(title)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.large, .semibold))
                    .foregroundStyle(Memnox.Console.foreground)
                    .accessibilityAddTraits(.isHeader)
                QuietLine(description)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Memnox.Spacing.xxLarge)
            .padding(.vertical, Memnox.Spacing.xLarge)
            ShellDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: Memnox.Spacing.xxLarge) { content }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Memnox.Spacing.xxLarge)
            }
            ShellDivider()
            HStack(spacing: Memnox.Spacing.medium) {
                Button(RuleWords.cancel, action: close)
                    .buttonStyle(KitButton(kind: .secondary, wide: true))
                    .keyboardShortcut(.cancelAction)
                Button(proposing ? confirm.busy : confirm.idle, action: propose)
                    .buttonStyle(KitButton(kind: .primary, wide: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canPropose || proposing)
            }
            .padding(.horizontal, Memnox.Spacing.xxLarge)
            .padding(.vertical, Memnox.Spacing.large)
        }
        .frame(width: RuleDialogLayout.width)
        .frame(maxHeight: RuleDialogLayout.maxHeight)
        .background(Memnox.Console.card)
    }
}

/// One effect as a described card, because a bare ask tells a newcomer nothing; the chosen one outlined in blue.
struct RuleEffectCard: View {
    let effect: RuleEffect
    let chosen: Bool
    var recommended = false
    let choose: () -> Void

    private enum Layout {
        /// The chosen card's wash, the console's blue at 5 percent under its outline.
        static let chosenWash = 0.05
        static let iconSize: CGFloat = 13
    }

    var body: some View {
        let words = StudioLines.words(effect)
        let shape = RoundedRectangle(cornerRadius: Memnox.Console.cardRadius, style: .continuous)
        Button(action: choose) {
            VStack(alignment: .leading, spacing: Memnox.Spacing.xSmall) {
                HStack(spacing: Memnox.Spacing.small) {
                    Image(systemName: RuleSymbols.effect(effect))
                        .font(.system(size: Layout.iconSize, weight: .medium))
                    Text(words.title)
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                    if recommended {
                        Spacer(minLength: Memnox.Spacing.small)
                        Text(RuleWords.recommended)
                            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                            .foregroundStyle(Memnox.Console.muted)
                    }
                }
                .foregroundStyle(Memnox.Console.foreground)
                Text(words.says)
                    .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                    .foregroundStyle(Memnox.Console.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 0, alignment: .topLeading)
            .padding(Memnox.Spacing.large)
            .background(chosen ? Memnox.Console.primary.opacity(Layout.chosenWash) : Color.clear, in: shape)
            .overlay(shape.strokeBorder(chosen ? Memnox.Console.primary : Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .pointingHand()
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}

/// The effects as a row of cards under their legend, one chosen.
struct RuleEffectChoice: View {
    let effects: [RuleEffect]
    @Binding var chosen: RuleEffect
    var recommended: RuleEffect?

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.medium) {
            RuleLegend(text: RuleWords.whenTried)
            HStack(alignment: .top, spacing: Memnox.Spacing.medium) {
                ForEach(effects, id: \.self) { each in
                    RuleEffectCard(effect: each, chosen: chosen == each, recommended: each == recommended) { chosen = each }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(RuleWords.whenTried)
        }
    }
}

/// A field's label in the console's weight, with the muted "(optional)" where it may stay empty.
struct RuleLegend: View {
    let text: String
    var optional = false

    var body: some View {
        HStack(spacing: Memnox.Spacing.xSmall) {
            Text(text).foregroundStyle(Memnox.Console.foreground)
            if optional { Text(RuleWords.optional).foregroundStyle(Memnox.Console.muted) }
        }
        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One labelled field: its legend, the control, and the line saying what it means.
struct RuleField<Control: View>: View {
    let label: String
    var optional = false
    var hint: String?
    @ViewBuilder let control: Control

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            RuleLegend(text: label, optional: optional)
            control
            if let hint { RuleHint(text: hint) }
        }
    }
}

/// The line under a field saying what it means, in the console's muted meta size.
struct RuleHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
            .foregroundStyle(Memnox.Console.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The rule in the runtime's own file format under its legend, so what is proposed is never a guess.
struct RulePreview: View {
    let code: String
    var title = RuleWords.preview

    private enum Layout {
        static let maxHeight: CGFloat = 320
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Memnox.Spacing.small) {
            RuleLegend(text: title)
            CodeBlock(code: code, label: RuleToml.file, maxHeight: Layout.maxHeight)
        }
    }
}

/// The runtime's data words as chips over the same comma separated text, so a press and a typed name are one field and
/// a team's own name still fits.
struct DataClassChips: View {
    @Binding var text: String

    var body: some View {
        let chosen = RuleToml.words(text) ?? []
        WordFlow(alignment: .leading, spacing: Memnox.Spacing.small, lineSpacing: Memnox.Spacing.small) {
            ForEach(RuleToml.dataClassifications, id: \.self) { word in
                DataClassChip(word: word, chosen: chosen.contains(word)) { text = RuleToml.toggled(word, in: text) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Data it carries")
    }
}

/// One data word as the console's round chip, outlined in its blue once chosen.
private struct DataClassChip: View {
    let word: String
    let chosen: Bool
    let toggle: () -> Void
    @State private var hovering = false

    private enum Layout {
        static let height: CGFloat = 30
        /// The chosen chip's wash, the console's blue at 10 percent.
        static let chosenWash = 0.1
    }

    var body: some View {
        Button(action: toggle) {
            Text(word)
                .font(Memnox.Console.sans(Memnox.Console.TextSize.meta))
                .foregroundStyle(chosen || hovering ? Memnox.Console.foreground : Memnox.Console.muted)
                .padding(.horizontal, Memnox.Spacing.large)
                .frame(height: Layout.height)
                .background(Capsule().fill(chosen ? Memnox.Console.primary.opacity(Layout.chosenWash)
                                                  : hovering ? Memnox.Console.hover : Color.clear))
                .overlay(Capsule().strokeBorder(chosen ? Memnox.Console.primary : Memnox.Console.border,
                                                lineWidth: Memnox.Stroke.hairline))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointingHand()
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}

/// The marks a rule is about, overlapped the way a stack of logos is drawn: a product's own Composio logo, a glyph for
/// a kind of act, and for a pack's rule, which names no marks, glyphs read from its actions.
struct RuleMarks: View {
    var marks: [RuleMark] = []
    var actions: [String] = []
    var size: CGFloat = Layout.size

    enum Layout {
        static let size: CGFloat = 36
        static let radius: CGFloat = 8
        /// The glyph's share of its square.
        static let glyphShare: CGFloat = 0.42
        /// The logo's share of its square, inside the white tile Composio's colours sit on.
        static let logoShare: CGFloat = 0.78
        /// How far each square tucks under the one before it, as a share of its side.
        static let overlapShare: CGFloat = 0.22
        /// The card's colour ringed round each square, so an overlapped one reads apart from the next.
        static let ring: CGFloat = 2
        static let mostMarks = 4
    }

    var body: some View {
        HStack(spacing: -size * Layout.overlapShare) {
            if marks.isEmpty {
                ForEach(RuleSymbols.actions(actions), id: \.self) { glyph($0) }
            } else {
                ForEach(Array(marks.prefix(Layout.mostMarks)), id: \.self) { mark in
                    if let toolkit = mark.toolkit {
                        logo(toolkit)
                    } else {
                        glyph(RuleSymbols.mark(mark))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Layout.radius * size / Layout.size, style: .continuous)
    }

    private func logo(_ toolkit: String) -> some View {
        ToolMark(toolkit: toolkit, side: size * Layout.logoShare)
            .frame(width: size, height: size)
            .background(Color.white, in: shape)
            .overlay(shape.strokeBorder(Memnox.Console.border, lineWidth: Memnox.Stroke.hairline))
            .background(shape.stroke(Memnox.Console.card, lineWidth: Layout.ring * 2))
    }

    private func glyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * Layout.glyphShare))
            .foregroundStyle(Memnox.Console.muted)
            .frame(width: size, height: size)
            .background(Memnox.Console.background, in: shape)
            .overlay(shape.strokeBorder(Memnox.Console.border, lineWidth: Memnox.Stroke.hairline))
            .background(shape.stroke(Memnox.Console.card, lineWidth: Layout.ring * 2))
    }
}

/// The symbols a rule wears: an effect's, and a glyph for a kind of act or the kind of tool an action names.
enum RuleSymbols {
    static func effect(_ effect: RuleEffect) -> String {
        switch effect {
        case .allow: "checkmark"
        case .ask: "questionmark.circle"
        case .deny: "nosign"
        }
    }

    /// The tick a card wears once its rule is in force.
    static let inForce = "checkmark"
    static let add = "plus"
    static let starter = "sparkles"

    /// The glyph for the first word of an action, by the kind of tool it names; anything unknown is a terminal.
    static func action(_ action: String) -> String {
        let tool = action.split(separator: ".").first.map(String.init) ?? action
        return glyphs[tool] ?? terminal
    }

    /// The glyphs for an action list, distinct and at most two, the way a stack of marks is drawn.
    static func actions(_ actions: [String]) -> [String] {
        var seen: [String] = []
        for each in actions.map(action) where !seen.contains(each) { seen.append(each) }
        return Array(seen.prefix(mostMarks))
    }

    /// The glyph for a kind of act, as the console's library draws one where no product's logo fits.
    static func mark(_ mark: RuleMark) -> String {
        switch mark {
        case .git: "arrow.triangle.branch"
        case .files: "doc.badge.ellipsis"
        case .key: "key"
        case .terraform: "square.stack.3d.up"
        case .kubernetes: "shippingbox"
        case .cloud: "cloud"
        case .production: "exclamationmark.shield"
        case .access: "person.badge.key"
        case .message: "bubble.left"
        case .network: "globe"
        case .package: "shippingbox"
        case .rocket: "paperplane"
        case .terminal: "terminal"
        case .workflow: "point.3.connected.trianglepath.dotted"
        case .storage: "externaldrive"
        case .settings: "gearshape"
        case .signin: "person.crop.circle.badge.checkmark"
        case .mcp: "puzzlepiece.extension"
        case .github, .vercel, .netlify, .railway, .fly, .docker, .postgresql, .mongodb, .stripe, .heroku: "app"
        }
    }

    private static let mostMarks = 2
    private static let terminal = "terminal"
    private static let cloud = "cloud"
    private static let glyphs: [String: String] = [
        "*": "asterisk", "git": "arrow.triangle.branch", "gh": "arrow.triangle.pull", "filesystem": "doc",
        "mcp": "puzzlepiece.extension", "http": "globe", "aws": cloud, "gcloud": cloud, "az": cloud,
        "kubectl": "shippingbox", "docker": "shippingbox", "npm": "shippingbox", "terraform": "square.stack.3d.up",
        "vercel": "paperplane", "fly": "paperplane", "heroku": "paperplane", "netlify": "paperplane",
        "psql": "cylinder", "mysql": "cylinder",
    ]
}
