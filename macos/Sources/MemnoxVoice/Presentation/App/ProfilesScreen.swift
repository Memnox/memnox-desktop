
import MemnoxVoiceCore
import SwiftUI

/// Profiles for the views: redrawn whenever the core's profiles change, with the line the last press ended in.
@MainActor
final class ProfilesScreen: ObservableObject {
    let profiles: Profiles
    /// Bumped when the profiles change, so every view reading them is drawn again.
    @Published private(set) var tick = 0
    /// What the last press came to, shown above the page until the next one.
    @Published var note: String?

    init(profiles: Profiles) {
        self.profiles = profiles
        profiles.changed = { [weak self] in
            Task { @MainActor [weak self] in self?.tick += 1 }
        }
    }

    func said(_ outcome: ProfileOutcome) {
        switch outcome {
        case .done(let line): note = line
        case .failed(let why): note = why
        }
    }
}
