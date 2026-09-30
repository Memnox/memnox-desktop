import Foundation

/// What the orb shows. Each state looks and moves differently, so a glance says which it is.
public enum VoiceState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
    /// Apple's Touch ID sheet is up, which is the one state that wants a hand and not a voice.
    case needsYou
}

/// Where the words go out loud.
public protocol Speaker: AnyObject {
    func speak(_ sentence: String) async
    func stop()
}

/// The orb and the pill, told what to show.
public protocol Face: AnyObject {
    func show(_ state: VoiceState, caption: String)
}

/// Talks and listens on the person's behalf: what they said goes whole to their own brain, what
/// is waiting on them is said out loud, and every allow waits for their fingerprint. It holds no
/// policy and never matches words: the brain understands them and the daemon decides.
public final class Conversation {
    private let link: DaemonLink
    private let speaker: Speaker
    private let key: ConfirmKey
    private let face: Face
    private var nextId = 1
    /// The held call last asked about out loud, so an answer elsewhere can end the question.
    private var asking: String?
    /// Set when the person talks over an answer, so the rest of it is never said.
    private var interrupted = false

    public init(link: DaemonLink, speaker: Speaker, key: ConfirmKey, face: Face) {
        self.link = link
        self.speaker = speaker
        self.key = key
        self.face = face
    }

    /// Registers this Mac's key, and says so when somebody else's is already there.
    public func introduce() async {
        var request = DaemonRequest(id: takeId(), method: .registerKey)
        request.point = key.publicPoint
        guard let response = try? await link.request(request) else { return }
        if response.outcome == "another key" {
            await say("Another key is registered for confirmations on this Mac, so I will not confirm anything. Run memnox voice forget-key in a terminal, then open me again.")
        }
    }

    /// What the person said, whole. No keyword decides anything here.
    public func heard(_ said: String) async {
        let words = said.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        interrupted = false
        face.show(.thinking, caption: caption(words))
        var request = DaemonRequest(id: takeId(), method: .ask)
        request.said = words
        var sentences = SentenceSplitter()
        do {
            for try await response in link.stream(request) {
                if let error = response.error, !response.ok {
                    await say("I could not ask: \(error).")
                    break
                }
                guard let chunk = response.chunk else { continue }
                if try await play(chunk, into: &sentences) { break }
            }
        } catch {
            await say("I cannot reach Memnox on this Mac right now.")
        }
        if let rest = sentences.flush(), !interrupted { await say(rest) }
        face.show(.listening, caption: "")
    }

    /// The person started talking over the answer: the voice stops now and the brain stops too.
    public func interrupt() async {
        interrupted = true
        speaker.stop()
        _ = try? await link.request(DaemonRequest(id: takeId(), method: .cancel))
    }

    /// Returns true once the turn is over.
    private func play(_ chunk: AskChunk, into sentences: inout SentenceSplitter) async throws -> Bool {
        switch chunk.chunkKind {
        case .text:
            for sentence in sentences.push(chunk.text ?? "") where !interrupted { await say(sentence) }
        case .tool:
            face.show(.thinking, caption: "reading \(toolWord(chunk.tool))")
        case .limited:
            if let rest = sentences.flush() { await say(rest) }
            await say("Your plan has reached its limit, so I could not finish that.")
        case .failed:
            if let rest = sentences.flush() { await say(rest) }
            await say("That did not work: \(chunk.text ?? "the brain stopped").")
        case .done, .cancelled, .none:
            break
        }
        return chunk.endsTurn
    }

    /// Something that started or stopped waiting on the person.
    public func handle(_ event: DaemonEvent) async {
        switch event.eventKind {
        case .held:
            asking = event.subject
            await say("\(event.summary). Allow it, or deny?")
            face.show(.listening, caption: caption("\(event.summary) · allow / deny"))
        case .proposal:
            await confirm(event)
        case .paused:
            await say("I paused a session: \(event.summary).")
        case .settled:
            if asking == event.subject {
                asking = nil
                speaker.stop()
                face.show(.idle, caption: "answered elsewhere")
            }
        case .none:
            break
        }
    }

    /// A proposal to let something happen: Touch ID signs exactly this one, or it is declined.
    private func confirm(_ event: DaemonEvent) async {
        let answerKind: ProposalAnswer
        var signature: String?
        face.show(.needsYou, caption: caption("Touch ID to \(event.summary)"))
        do {
            signature = try await key.sign(
                confirmationMessage(subject: event.subject, answer: ProposalAnswer.confirmed.rawValue),
                reason: event.summary
            )
            answerKind = signature == nil ? .declined : .confirmed
        } catch {
            answerKind = .declined
        }
        var request = DaemonRequest(id: takeId(), method: .confirm)
        request.subject = event.subject
        request.answer = answerKind.rawValue
        request.signature = signature
        let response = try? await link.request(request)
        if response?.ok == true {
            await say(answerKind == .confirmed ? "Done." : "Left as it was.")
        } else {
            await say("That was not confirmed: \(response?.error ?? "Memnox did not answer").")
        }
    }

    private func say(_ sentence: String) async {
        face.show(.speaking, caption: caption(sentence))
        await speaker.speak(sentence)
    }

    private func takeId() -> Int {
        defer { nextId += 1 }
        return nextId
    }
}
