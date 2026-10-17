import MemnoxVoiceCore
import SwiftUI

extension SessionStatus {
    /// The badge colour: red when paused, amber when it waits on the person, green while it is busy.
    var tint: Color {
        switch self {
        case .paused: Memnox.Palette.destructive
        case .needsYou, .waitingOnYou: Memnox.Palette.warm
        case .thinking, .working: Memnox.Palette.success
        case .ended, .quiet: Memnox.Palette.muted
        }
    }

    /// The live window's glow, which stays a faint brand colour rather than grey when nothing happens.
    var glow: Color {
        switch self {
        case .ended, .quiet: Memnox.Palette.primary.opacity(Self.restingGlowOpacity)
        case .paused, .needsYou, .waitingOnYou, .thinking, .working: tint
        }
    }

    /// Faint enough that a resting window does not look like it wants attention.
    private static let restingGlowOpacity = 0.6
}
