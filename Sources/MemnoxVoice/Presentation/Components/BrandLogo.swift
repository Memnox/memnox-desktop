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
