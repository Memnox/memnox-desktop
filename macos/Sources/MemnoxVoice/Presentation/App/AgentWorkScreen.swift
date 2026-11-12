import MemnoxVoiceCore
import SwiftUI

/// Agent work for the views: redrawn whenever the core's work changes, with the line the last press ended in.
@MainActor
final class AgentWorkScreen: ObservableObject {
    let desk: AgentWorkDesk
    /// Bumped when the work changes, so every view reading it is drawn again.
    @Published private(set) var tick = 0
    /// What the last press came to, shown above the page until the next one.
    @Published var note: String?

    init(desk: AgentWorkDesk) {
        self.desk = desk
        desk.changed = { [weak self] in
            Task { @MainActor [weak self] in self?.tick += 1 }
        }
    }

    func said(_ outcome: WorkOutcome) {
        switch outcome {
        case .done(let line): note = line
        case .failed(let why): note = why
        }
    }
}
