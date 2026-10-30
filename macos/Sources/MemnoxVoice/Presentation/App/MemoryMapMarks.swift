import MemnoxVoiceCore
import SwiftUI

/// One node of the memory map as it is drawn: a fact as a card with its status down a rail, a document as a small card,
/// a rule as a card in its effect's colour, and a source as a disc with its name hung below.
struct MapMark: View {
    let node: MemoryMapNode
    let selected: Bool
    /// Walked to from the keyboard, ringed so the person can see where the arrows are.
    let keyed: Bool
    let showName: Bool

    private enum Layout {
        static let radius: CGFloat = Memnox.Console.cardRadius
        static let rail: CGFloat = 4
        static let small: CGFloat = 10
        static let smallTracking: CGFloat = 1.2
        static let icon: CGFloat = 11
        static let sourceIcon: CGFloat = 18
        /// A card's border in its status or effect colour, mixed down toward the plain border.
        static let tintedEdge = 0.45
        /// Facts no agent is told any more stay on the map, faintly, because the history is the point.
        static let quiet = 0.6
        static let pickedRing: CGFloat = 2
        static let ringShare = 0.4
        static let nameWidth: CGFloat = 112
        static let nameGap: CGFloat = 4
        static let padLeading: CGFloat = 14
        static let padTrailing: CGFloat = 10
        static let padCard: CGFloat = 12
        static let lineSpacing: CGFloat = 1
    }

    private static let quietStatuses: Set<String> = [MemoryStatus.outdated.rawValue, MemoryStatus.rejected.rawValue,
                                                      MemoryStatus.superseded.rawValue]

    var body: some View {
        switch node.kind {
        case .memory: memory
        case .document: document
        case .rule: rule
        case .source: source
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Layout.radius, style: .continuous)
    }

    private var memory: some View {
        let status = node.status.map(MemoryLines.statusWord)
        let ink = (status.map { Tone($0.tone) } ?? .quiet).dot
        let quiet = node.status.map(Self.quietStatuses.contains) ?? false
        return VStack(alignment: .leading, spacing: Layout.lineSpacing) {
            HStack(spacing: Memnox.Spacing.small) {
                small(node.memoryKind.map(MemoryLines.kindWord) ?? "Memory", ink: ink)
                if node.tainted { small("Untrusted", ink: Memnox.Console.warm, upper: false) }
            }
            words(lines: 2)
        }
        .padding(.leading, Layout.padLeading)
        .padding(.trailing, Layout.padTrailing)
        .frame(width: MemoryMaps.Size.memory.width, height: MemoryMaps.Size.memory.height, alignment: .leading)
        .background(Memnox.Console.card)
        .overlay(alignment: .leading) { Rectangle().fill(ink).frame(width: Layout.rail) }
        .clipShape(shape)
        .modifier(MarkEdge(shape: shape, tint: ink, selected: selected, keyed: keyed))
        .opacity(quiet ? Layout.quiet : 1)
    }

    private var document: some View {
        VStack(alignment: .leading, spacing: Layout.lineSpacing) {
            HStack(spacing: Memnox.Spacing.xSmall) {
                Image(systemName: "doc.text").font(.system(size: Layout.icon))
                Text(node.detail ?? "Document").lineLimit(1)
            }
            .font(Memnox.Console.sans(Layout.small))
            .foregroundStyle(Memnox.Console.warm)
            words(lines: 1)
        }
        .padding(.horizontal, Layout.padCard)
        .frame(width: MemoryMaps.Size.document.width, height: MemoryMaps.Size.document.height, alignment: .leading)
        .background(Memnox.Console.card, in: shape)
        .modifier(MarkEdge(shape: shape, tint: nil, selected: selected, keyed: keyed))
    }

    private var rule: some View {
        let effect = node.detail ?? ""
        let known = RuleEffect(rawValue: effect) != nil
        let ink = known ? Tone(effect: effect).dot : Memnox.Console.faint
        return VStack(alignment: .leading, spacing: Layout.lineSpacing) {
            HStack(spacing: Memnox.Spacing.xSmall) {
                Image(systemName: "hammer").font(.system(size: Layout.icon))
                small(known ? "Rule, \(StudioLines.title(effect))" : "Rule", ink: ink)
            }
            .foregroundStyle(ink)
            words(lines: 2)
        }
        .padding(.horizontal, Layout.padCard)
        .frame(width: MemoryMaps.Size.rule.width, height: MemoryMaps.Size.rule.height, alignment: .leading)
        .background(Memnox.Console.card, in: shape)
        .modifier(MarkEdge(shape: shape, tint: ink, selected: selected, keyed: keyed))
    }

    /// A source is a disc with its name hung below, since it is a place rather than a sentence.
    private var source: some View {
        let disc = Circle()
        return Image(systemName: "book")
            .font(.system(size: Layout.sourceIcon))
            .foregroundStyle(Memnox.Console.primary)
            .frame(width: MemoryMaps.Size.source, height: MemoryMaps.Size.source)
            .background(Memnox.Console.background, in: disc)
            .modifier(MarkEdge(shape: disc, tint: nil, selected: selected, keyed: keyed))
            .overlay(alignment: .top) {
                if showName {
                    Text(node.label)
                        .font(Memnox.Console.sans(Layout.small, .medium))
                        .foregroundStyle(selected ? Memnox.Console.foreground : Memnox.Console.muted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(width: Layout.nameWidth)
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(y: MemoryMaps.Size.source + Layout.nameGap)
                        .allowsHitTesting(false)
                }
            }
    }

    private func small(_ text: String, ink: Color, upper: Bool = true) -> some View {
        Text(upper ? text.uppercased() : text)
            .font(Memnox.Console.sans(Layout.small))
            .tracking(upper ? Layout.smallTracking : 0)
            .foregroundStyle(ink)
            .lineLimit(1)
    }

    private func words(lines: Int) -> some View {
        Text(node.label)
            .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .medium))
            .foregroundStyle(Memnox.Console.foreground)
            .lineLimit(lines)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A mark's border, tinted toward its colour, the foreground and a soft blue ring once picked, and a shadow that
    /// lifts it off the ground.
    private struct MarkEdge<S: InsettableShape>: ViewModifier {
        let shape: S
        let tint: Color?
        let selected: Bool
        let keyed: Bool

        func body(content: Content) -> some View {
            content
                .overlay(shape.strokeBorder(edge, lineWidth: Memnox.Stroke.hairline))
                .background(shape.stroke(selected || keyed ? Memnox.Console.primary.opacity(Layout.ringShare) : Color.clear,
                                         lineWidth: Layout.pickedRing * 2))
                .shadow(color: .black.opacity(MapMetrics.shadow), radius: MapMetrics.shadowRadius, y: MapMetrics.shadowDrop)
        }

        private var edge: Color {
            if selected { return Memnox.Console.foreground }
            guard let tint else { return Memnox.Console.panelEdge }
            return tint.opacity(Layout.tintedEdge)
        }
    }
}
