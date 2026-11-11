import MemnoxVoiceCore
import SwiftUI

extension SessionStatus {
    /// The badge colour: red when paused, amber when it waits on the person, green while it is busy.
    var tint: Color {
        switch self {
        case .stopped: Memnox.Console.destructive
        case .needsYou, .finished: Memnox.Console.warm
        case .working: Memnox.Console.success
        case .idle: Memnox.Console.muted
        }
    }

    /// The live window's glow, which stays a faint brand colour rather than grey when nothing happens.
    var glow: Color {
        switch self {
        case .idle: Memnox.Console.primary.opacity(Self.restingGlowOpacity)
        case .stopped, .needsYou, .finished, .working: tint
        }
    }

    /// Faint enough that a resting window does not look like it wants attention.
    private static let restingGlowOpacity = 0.6
}
