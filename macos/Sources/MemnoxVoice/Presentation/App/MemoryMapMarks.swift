import MemnoxVoiceCore
import SwiftUI

/// One node of the memory map as the console draws it in depth: a round dark mark with its kind's icon and its name
/// hung below. A fact's icon wears its status, a rule's its effect, an app wears its own logo, and the rest stay plain.
/// Drawn large, as the console's are, so the graph reads from across the room.
struct MapMark: View {
    let node: MemoryMapNode
    let selected: Bool
    /// Walked to from the keyboard, ringed so the person can see where the arrows are.
    let keyed: Bool
    let showName: Bool

    private enum Layout {
        /// A source and a project hold the most, so they are the largest; then an app and a document, a fact, and a
        /// conversation the smallest since there are many.
        static let source: Double = 64
        static let workspace: Double = 60
        static let document: Double = 54
        static let fact: Double = 50
        static let conversation: Double = 46
        static let icon: CGFloat = 19
        static let sourceIcon: CGFloat = 24
        /// A logo fills this much of its disc, so the disc's dark rim still reads as the map's mark.
        static let logoShare: CGFloat = 0.58
        /// A mark's border in its status or effect colour, mixed down toward the plain border.
        static let tintedEdge = 0.55
        /// Facts no agent is told any more stay on the map, faintly, because the history is the point.
        static let quiet = 0.6
        static let pickedRing: CGFloat = 2
        static let ringShare = 0.4
        static let nameWidth: CGFloat = 168
        static let nameGap: CGFloat = 6
        static let nameLines = 2
        static let badge: CGFloat = 10
        /// The workspace's cloud worn on a mark it holds, big enough to read beside the trust dot.
        static let home: CGFloat = 18
        static let homeIcon: CGFloat = 9
        /// A person's initials, a little smaller than an icon so two letters fit the disc.
        static let initials: CGFloat = 15
        /// The count badge: its height, the padding beside its digits, and how far it hangs off the disc's corner.
        static let countHeight: CGFloat = 16
        static let countPadding: CGFloat = 5
        static let countDrop: CGFloat = 4
    }

    private static let quietStatuses: Set<String> = [MemoryStatus.outdated.rawValue, MemoryStatus.rejected.rawValue,
                                                      MemoryStatus.superseded.rawValue]

    /// How wide a kind's mark is in world points, before depth and the size setting scale it, so the lines stop at it.
    static func side(_ kind: MemoryMapNodeKind) -> Double {
        switch kind {
        case .source: Layout.source
        case .workspace, .app: Layout.workspace
        case .document: Layout.document
        case .memory, .rule, .decision: Layout.fact
        case .conversation, .person: Layout.conversation
        case .skill, .standing: Layout.fact
        }
    }

    /// The icon a kind is drawn with, shared with the Show panel so its rows match the drawing.
    static func symbol(_ kind: MemoryMapNodeKind) -> String {
        switch kind {
        case .memory: "lightbulb"
        case .document: "doc.text"
        case .rule: "hammer"
        case .source: "book"
        case .conversation: "bubble.left.and.bubble.right"
        case .app: "square.grid.2x2"
        case .workspace: "folder"
        case .decision: "checkmark.seal"
        case .person: "person"
        case .skill: "sparkle"
        case .standing: "shield"
        }
    }

    /// The icon a live workspace node wears where its kind says more than the map's kind does, nil where it does not.
    static func liveSymbol(_ kind: WorkspaceNodeKind) -> String? {
        switch kind {
        case .bot: "cpu"
        case .group: "person.3"
        case .policy: "hammer"
        case .candidate: "questionmark.bubble"
        case .passage: "text.quote"
        case .conversation: "bubble.left.and.bubble.right"
        case .source, .document, .person, .decision: nil
        }
    }

    /// The mark of the workspace, on a node it holds and on the Workspace chip, so both read alike.
    static let homeSymbol = "cloud.fill"

    var body: some View {
        let disc = Circle()
        let side = CGFloat(Self.side(node.kind))
        face(side)
            .frame(width: side, height: side)
            .background(Memnox.Console.background, in: disc)
            .modifier(MarkEdge(shape: disc, tint: tint, selected: selected, keyed: keyed))
            .overlay(alignment: .topTrailing) {
                // Read from a source outside the person's trust, said as the console's warm dot.
                if node.tainted {
                    Circle().fill(Memnox.Console.warm).frame(width: Layout.badge, height: Layout.badge)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // Pulled from the workspace rather than learned here, said by the console's cloud.
                if node.home != .thisMac {
                    Image(systemName: Self.homeSymbol)
                        .font(.system(size: Layout.homeIcon, weight: .semibold))
                        .foregroundStyle(Memnox.Console.background)
                        .frame(width: Layout.home, height: Layout.home)
                        .background(Memnox.Console.primary, in: Circle())
                        .accessibilityLabel(node.home == .both ? "On this Mac and in your workspace" : "From your workspace")
                }
            }
            .overlay(alignment: .topLeading) {
                // Said again or posted many times, the console's count bubble.
                if let count = node.count {
                    Text(WorkspaceLiveLines.badge(count))
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.label, .semibold).monospacedDigit())
                        .foregroundStyle(Memnox.Console.foreground)
                        .padding(.horizontal, Layout.countPadding)
                        .frame(minHeight: Layout.countHeight)
                        .background(Memnox.Console.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Memnox.Console.panelEdge, lineWidth: Memnox.Stroke.hairline))
                        .fixedSize()
                        .offset(x: -Layout.countDrop, y: -Layout.countDrop)
                        .accessibilityLabel(WorkspaceLiveLines.countLine(count, kind: node.live?.nodeKind))
                }
            }
            .overlay(alignment: .top) {
                if showName {
                    Text(MapNames.short(node.label))
                        .font(Memnox.Console.sans(Memnox.Console.TextSize.bodySmall, .medium))
                        .foregroundStyle(selected ? Memnox.Console.foreground : Memnox.Console.muted)
                        .multilineTextAlignment(.center)
                        .lineLimit(Layout.nameLines)
                        .truncationMode(.tail)
                        .frame(width: Layout.nameWidth)
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(y: side + Layout.nameGap)
                        .allowsHitTesting(false)
                }
            }
            .opacity(quiet ? Layout.quiet : 1)
            .help(node.label)
    }

    /// Facts no agent is told any more, and conversations that are over, stay on the map faintly.
    private var quiet: Bool {
        switch node.kind {
        case .memory: node.status.map(Self.quietStatuses.contains) ?? false
        case .conversation: node.detail == SessionState.ended.rawValue
        case .document, .source, .rule, .app, .workspace, .decision, .person, .skill, .standing: false
        }
    }

    /// An app's logo from its catalogue, and every other kind's icon.
    @ViewBuilder private func face(_ side: CGFloat) -> some View {
        if node.kind == .app || node.kind == .document, let slug = node.mark {
            ToolMark(toolkit: slug, side: side * Layout.logoShare)
        } else if let live = node.live, live.nodeKind == .person {
            // No picture comes down to this Mac, so a person wears their initials, never a silhouette.
            Text(WorkspaceLiveLines.initials(node.label))
                .font(Memnox.Console.sans(Layout.initials, .semibold))
                .foregroundStyle(Memnox.Console.foreground)
                .accessibilityHidden(true)
        } else if let symbol = node.live?.nodeKind.flatMap(Self.liveSymbol) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(tint ?? plainInk)
        } else {
            Image(systemName: Self.symbol(node.kind))
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(tint ?? plainInk)
        }
    }

    private var iconSize: CGFloat {
        switch node.kind {
        case .source, .workspace: Layout.sourceIcon
        case .memory, .document, .rule, .conversation, .app, .decision, .person, .skill, .standing: Layout.icon
        }
    }

    /// A fact is coloured by where it stands and a rule by what it does; the rest carry no colour of their own.
    private var tint: Color? {
        switch node.kind {
        case .memory, .decision:
            let status = node.status.map(MemoryLines.statusWord)
            return (status.map { Tone($0.tone) } ?? .quiet).dot
        case .rule, .standing:
            let effect = node.detail ?? ""
            return RuleEffect(rawValue: effect) != nil ? Tone(effect: effect).dot : Memnox.Console.faint
        case .conversation:
            // A conversation that is working right now is lit in the console's blue.
            return node.detail == SessionState.working.rawValue ? Memnox.Console.primary : nil
        case .document, .source, .app, .workspace, .person, .skill:
            return nil
        }
    }

    private var plainInk: Color {
        node.kind == .source || node.kind == .workspace ? Memnox.Console.primary : Memnox.Console.muted
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
