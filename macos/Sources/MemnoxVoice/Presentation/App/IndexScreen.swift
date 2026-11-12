import MemnoxVoiceCore
import SwiftUI

/// The community index for the rule packs under Rules: redrawn whenever the core's index changes, with the line the
/// last press ended in.
@MainActor
final class IndexScreen: ObservableObject {
    let index: CommunityIndex
    /// Bumped when the index changes, so every view reading it is drawn again.
    @Published private(set) var tick = 0
    /// What the last press came to, shown above the packs until the next one.
    @Published var note: String?

    init(index: CommunityIndex) {
        self.index = index
        index.changed = { [weak self] in
            Task { @MainActor [weak self] in self?.tick += 1 }
        }
    }

    /// Installs and says how it ended; a pack's rules each wait for Touch ID on the island before they hold.
    func install(_ name: String, version: String?) {
        Task {
            switch await index.install(name, version: version) {
            case .done(let line): note = line
            case .failed(let why): note = why
            }
        }
    }
}
