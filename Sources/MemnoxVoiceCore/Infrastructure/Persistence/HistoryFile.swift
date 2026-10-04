import Foundation

/// The exchanges lately, kept in the app's own Application Support folder so the notch still has them after a restart.
/// It holds what the person asked and was told on this Mac, and never leaves it.
public final class HistoryFile {
    private let file: URL

    /// The folder and file name under Application Support, so the history sits with the app's other state.
    private static let folder = "Memnox"
    private static let name = "history.json"

    public init(folder: URL? = nil) {
        let base = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first.map { $0.appendingPathComponent(Self.folder) }
            ?? FileManager.default.temporaryDirectory
        file = base.appendingPathComponent(Self.name)
    }

    /// What was kept, or an empty history when nothing was or it no longer reads.
    public func load() -> History {
        guard let data = try? Data(contentsOf: file), let history = try? JSONDecoder().decode(History.self, from: data) else {
            return History()
        }
        return history
    }

    /// Kept whole each time, since it is small; a failed write only loses the newest exchange.
    public func save(_ history: History) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            diary.note("could not keep the history: \(error.localizedDescription)")
        }
    }
}
