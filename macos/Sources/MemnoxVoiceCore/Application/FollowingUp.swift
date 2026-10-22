import Foundation

/// How a follow up typed in the notch went.
public enum FollowUpState: Equatable, Sendable {
    /// The daemon took the words, and how they reach the session.
    case sent(FollowUpOutcome)
    /// The person closed Touch ID, so nothing was sent.
    case cancelled
    /// The runtime said no, with its reason.
    case refused(String)
    case unreachable
}

/// Words typed in the notch into one session, as the phone's composer sends them: Touch ID signs memnox-follow-up:v1
/// over that session and those exact words, and the runtime hands them to the agent as they are. No brain reads them
/// and nothing here matches a word.
public final class FollowingUp: @unchecked Sendable {
    private let link: DaemonLink
    private let key: ConfirmKey
    private let ids: RequestIds

    static let reason = "send your words to the agent"
    static let noReason = "Memnox would not send that to the agent."

    public init(link: DaemonLink, key: ConfirmKey, ids: RequestIds) {
        self.link = link
        self.key = key
        self.ids = ids
    }

    public func send(_ words: String, to sessionId: String) async -> FollowUpState {
        let said = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !said.isEmpty else { return .refused(Self.noReason) }
        let signature: String?
        do {
            signature = try await key.sign(followUpMessage(sessionId: sessionId, words: said), reason: Self.reason)
        } catch {
            diary.note("Touch ID could not sign the follow up: \(error)")
            return .refused("Touch ID could not sign that.")
        }
        guard let signature else { return .cancelled }
        var request = DaemonRequest(id: ids.next(), method: .followUp)
        request.sessionId = sessionId
        request.said = said
        request.signature = signature
        guard let response = try? await link.request(request) else { return .unreachable }
        if response.ok, let outcome = response.outcome.flatMap(FollowUpOutcome.init(rawValue:)) {
            diary.note("follow up sent to session \(sessionId): \(outcome.rawValue)")
            return .sent(outcome)
        }
        let why = response.reason ?? response.error ?? Self.noReason
        diary.note("follow up refused: \(why)")
        return .refused(why)
    }
}
