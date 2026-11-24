import MemnoxVoiceCore
import SwiftUI

/// An agent's logo on a tile of its own colour, the agent's tile wherever tools are listed.
struct AgentMark: View {
    let kind: String
    let name: String
    let side: CGFloat

    /// The logo fills a little over half the tile, as a Settings tile's symbol does.
    private static let logoShare: CGFloat = 0.58
    private static let cornerShare: CGFloat = 0.26

    var body: some View {
        AgentLogo(kind: kind, name: name)
            .frame(width: side * Self.logoShare, height: side * Self.logoShare)
            .frame(width: side, height: side)
            .background(IslandPalette.color(kind), in: RoundedRectangle(cornerRadius: side * Self.cornerShare, style: .continuous))
            .accessibilityHidden(true)
    }
}
