import SwiftUI

/// An agent's logo exactly as its brand ships it, filling a rounded tile like an app icon: Claude's spark on its dark
/// square, OpenAI's knot on white, Cursor's cube in its own greys. Each file carries its own ground, so none is
/// recoloured; recolouring flattened them into squares of one colour. The notch keeps its coloured discs.
struct BrandLogo: View {
    /// The agent's id or kind, such as claude-code.
    let agent: String?
    let name: String
    var size: CGFloat = 28

    private static let initialScale: CGFloat = 0.46
    /// The tile rounds like an app icon, about a quarter of its side.
    private static let cornerShare: CGFloat = 0.26

    var body: some View {
        let kind = IslandPalette.kind(agent ?? name)
        let shape = RoundedRectangle(cornerRadius: size * Self.cornerShare, style: .continuous)
        Group {
            if let image = AgentLogo.image(for: kind) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * Self.initialScale, weight: .semibold, design: .rounded))
                    .foregroundStyle(IslandPalette.color(agent ?? name))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Memnox.Palette.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Memnox.ink(Memnox.Ink.edge), lineWidth: Memnox.Stroke.hairline))
        .accessibilityLabel(Text(name))
    }
}

/// An agent's logo in a disc of its own colour, the island's way of naming an agent beside its name on the dark glass.
struct AgentDisc: View {
    /// The agent's id or kind, such as claude-code.
    let agent: String?
    let name: String
    let size: CGFloat

    /// The logo fills a little over half the disc, leaving a ring of colour around it.
    private static let logoScale: CGFloat = 0.56

    var body: some View {
        AgentLogo(kind: IslandPalette.kind(agent ?? name), name: name)
            .frame(width: size * Self.logoScale, height: size * Self.logoScale)
            .frame(width: size, height: size)
            .background(Circle().fill(IslandPalette.color(agent ?? name)))
            .accessibilityHidden(true)
    }
}

/// The logos of the agents a line names, only those Memnox ships a logo for, so a pattern or an unknown agent draws
/// nothing rather than a made up mark.
struct NamedAgentLogos: View {
    /// The agents' ids or kinds, such as claude-code.
    let agents: [String]
    var size: CGFloat = NamedAgentLogos.size

    /// A line of small text's height, so the logos sit level with the words that name them.
    static let size: CGFloat = 16

    var body: some View {
        let known = Self.known(agents)
        if !known.isEmpty {
            HStack(spacing: Memnox.Spacing.xxSmall) {
                ForEach(known, id: \.self) { kind in
                    BrandLogo(agent: kind, name: kind, size: size)
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// Each agent once, in the order named, kept only where a logo file exists for its kind.
    @MainActor
    static func known(_ agents: [String]) -> [String] {
        var seen = Set<String>()
        return agents.filter { AgentLogo.image(for: IslandPalette.kind($0)) != nil && seen.insert(IslandPalette.kind($0)).inserted }
    }
}
