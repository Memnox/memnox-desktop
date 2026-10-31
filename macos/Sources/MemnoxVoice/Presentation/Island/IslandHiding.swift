import Foundation
import MemnoxVoiceCore

/// The switch that keeps the notch closed, shared by the menu bar and the eye beside the island so both agree.
/// Closed, the orb still rests in the notch and news is said from there rather than opened up; calling Memnox
/// still opens it, and a call an agent is stopped on still shows, since otherwise that agent waits unseen.
@MainActor
final class IslandHiding: ObservableObject {
    static let shared = IslandHiding()
    /// Off unless the person closes it, so a first run shows what Memnox does in the notch.
    static let key = "islandHidden"

    @Published private(set) var on = UserDefaults.standard.bool(forKey: key)

    private init() {}

    func set(_ hidden: Bool) {
        on = hidden
        UserDefaults.standard.set(hidden, forKey: Self.key)
        diary.note(hidden ? "notch kept closed" : "notch opens on its own again")
    }

    func toggle() { set(!on) }
}
