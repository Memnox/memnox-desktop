import Foundation

/// Asks the daemon to have dictation polished by the person's own Claude Code, which it keeps warm for it, and stops
/// waiting once it has taken longer than a person waits for a paste. Nil means the Mac's own cleanup is typed instead,
/// so nothing is ever lost to a slow or absent answer. No model is called from here, and none in any cloud.
public final class DictationPolish: @unchecked Sendable {
    private let link: DaemonLink
    private let ids: RequestIds
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    /// Long enough for a warm Claude Code on its quick model, short enough that the cursor never seems stuck.
    public static let patience: TimeInterval = 3.5
    /// Task.sleep counts in nanoseconds.
    public static let nanosecondsPerSecond: TimeInterval = 1_000_000_000
    /// Editing a selection has nothing to fall back on, so it waits a little longer for its one answer.
    public static let editPatience: TimeInterval = 12

    public init(link: DaemonLink, ids: RequestIds = RequestIds(),
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
                    try await Task.sleep(nanoseconds: UInt64(seconds * DictationPolish.nanosecondsPerSecond))
                }) {
        self.link = link
        self.ids = ids
        self.sleep = sleep
    }

    /// Starts the process ahead of the words, as the key goes down; nothing waits on it.
    public func warm() async {
        _ = try? await link.request(DaemonRequest(id: ids.next(), method: .polishWarm))
    }

    /// The polished text, or nil when the daemon said no or did not answer within `patience`.
    public func polish(
        _ said: String, family: DictationFamily, vocabulary: [String], selection: String? = nil,
        patience: TimeInterval = DictationPolish.patience
    ) async -> String? {
        var request = DaemonRequest(id: ids.next(), method: .polish)
        request.said = said
        request.family = family.rawValue
        request.vocabulary = vocabulary
        request.selection = selection
        let link = self.link
        let sleep = self.sleep
        let answer: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                guard let response = try? await link.request(request), response.ok else { return nil }
                return response.polished?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            }
            group.addTask {
                try? await sleep(patience)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        diary.note(answer == nil ? "dictation was not polished in time, so the Mac's own cleanup is used" : "dictation polished")
        return answer
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
