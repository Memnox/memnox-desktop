import Foundation
import os

/// Every step of a turn, readable with: log stream --predicate 'subsystem == "com.memnox.voice"'
public let voiceLog = Logger(subsystem: "com.memnox.voice", category: "conversation")

/// Where the confirmation key stands with the daemon.
public enum KeyStatus: Equatable {
    case registered
    /// Somebody else's key is trusted, so nothing can be confirmed from here.
    case anotherKey
    case unreachable
    /// The daemon answers but does not know voice: an older Memnox than this app.
    case tooOld
}

/// Whether the daemon can hold a conversation, which setup checks before saying it is ready.
public enum DaemonVoice: Equatable {
    case ready
    case tooOld
    case unreachable
}

/// What the orb shows. Each state looks and moves differently, so a glance says which it is.
public enum VoiceState: Equatable, Sendable {
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
    private let owner: OwnerStore
    private var nextId = 1
    /// The held call last asked about out loud, so an answer elsewhere can end the question.
    private var asking: String?
    /// Set when the person talks over an answer, so the rest of it is never said.
    private var interrupted = false
    /// When the person last said something, since an allow may only follow their own words.
    private var lastHeard: Date?
    private let now: () -> Date
    /// Said when the daemon is older than the app, which is the one fix a person can make.
    static let tooOld = "The Memnox running on this Mac is older than this app, so it cannot answer yet. Update Memnox and ask me again."
    /// Long enough to say "yes, go ahead" and have the brain propose it.
    static let answerWindow: TimeInterval = 120

    public init(
        link: DaemonLink,
        speaker: Speaker,
        key: ConfirmKey,
        face: Face,
        owner: OwnerStore,
        now: @escaping () -> Date = Date.init
    ) {
        self.now = now
        self.link = link
        self.speaker = speaker
        self.key = key
        self.face = face
        self.owner = owner
    }

    /// Whether the daemon answers, and whether it speaks voice rather than only answering ok.
    public func daemonVoice() async -> DaemonVoice {
        guard let response = try? await link.request(DaemonRequest(id: takeId(), method: .waiting)) else {
            return .unreachable
        }
        return response.ok && response.waiting != nil ? .ready : .tooOld
    }

    /// Registers this Mac's key with the daemon, which trusts the first one it is given.
    public func registerKey() async -> KeyStatus {
        var request = DaemonRequest(id: takeId(), method: .registerKey)
        request.point = key.publicPoint
        guard let response = try? await link.request(request) else { return .unreachable }
        if response.outcome == "another key" { return .anotherKey }
        // Only the word itself counts, since an older daemon answered anything with a bare ok.
        return response.ok && response.outcome == "registered" ? .registered : .tooOld
    }

    /// At launch: registers the key, and says so when somebody else's is already there.
    public func introduce() async {
        if await registerKey() == .anotherKey {
            await say("Another key is registered for confirmations on this Mac, so I will not confirm anything. Run memnox voice forget-key in a terminal, then open me again.")
        }
    }

    /// What the person said, whole. No keyword decides anything here.
    public func heard(_ said: String) async {
        let words = said.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        interrupted = false
        lastHeard = now()
        voiceLog.info("heard: \(words, privacy: .private)")
        face.show(.thinking, caption: caption(words))
        var request = newRequest(.ask)
        request.said = words
        let told = await speakStream(request)
        if told == .unreachable { await say("I cannot reach Memnox on this Mac right now.") }
        if case .refused(let error) = told {
            await say(error == Self.tooOld ? error : "I could not ask: \(error).")
        }
        face.show(.listening, caption: "")
    }

    /// Welcome back: what happened while they were away, told by their own brain.
    public func welcomeBack(since: Date) async {
        interrupted = false
        face.show(.thinking, caption: "catching up")
        var request = newRequest(.brief)
        request.briefing = Briefing.back.rawValue
        request.since = ISO8601DateFormatter().string(from: since)
        _ = await speakStream(request)
    }

    /// How a streamed answer ended, so a brief that said nothing can fall back to the facts.
    enum Told: Equatable {
        case spoke
        case silent
        case refused(String)
        case unreachable
    }

    /// Streams a turn into speech, sentence by sentence, and says how it ended.
    private func speakStream(_ request: DaemonRequest) async -> Told {
        var sentences = SentenceSplitter()
        var spoke = false
        do {
            for try await response in link.stream(request) {
                if let error = response.error, !response.ok {
                    voiceLog.error("\(request.method, privacy: .public) refused: \(error, privacy: .public)")
                    return .refused(error.hasPrefix("no method") ? Self.tooOld : error)
                }
                // An older daemon answers a method it does not know with a bare ok and nothing more.
                guard let chunk = response.chunk else {
                    if response.event == nil, response.waiting == nil {
                        voiceLog.error("\(request.method, privacy: .public) answered with nothing: an older daemon")
                        return .refused(Self.tooOld)
                    }
                    continue
                }
                voiceLog.debug("chunk \(chunk.kind, privacy: .public)")
                if chunk.chunkKind == .text, !(chunk.text ?? "").isEmpty { spoke = true }
                if try await play(chunk, into: &sentences) { break }
            }
        } catch {
            voiceLog.error("\(request.method, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            return spoke ? .spoke : .unreachable
        }
        if let rest = sentences.flush(), !interrupted {
            spoke = true
            await say(rest)
        }
        return spoke ? .spoke : .silent
    }

    private func newRequest(_ method: DaemonMethod) -> DaemonRequest {
        var request = DaemonRequest(id: takeId(), method: method)
        request.owner = owner.name
        return request
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
            interrupted = false
            var request = newRequest(.brief)
            request.briefing = Briefing.held.rawValue
            request.subject = event.subject
            face.show(.thinking, caption: "\(event.agentName ?? event.agent) needs you")
            // Told by their own brain with what the session has been doing; the facts alone if it cannot.
            if await speakStream(request) != .spoke {
                await say(heldQuestion(owner: owner.name, event: event))
            }
            let who = event.agentName ?? event.agent
            face.show(.listening, caption: caption("\(who) wants to \(event.what ?? event.summary)"))
        case .proposal:
            // Only after the person spoke: an allow nobody asked for is left alone, not put to Touch ID.
            if let heard = lastHeard, now().timeIntervalSince(heard) < Self.answerWindow {
                await confirm(event)
            } else {
                await decline(event)
            }
        case .paused:
            var request = newRequest(.brief)
            request.briefing = Briefing.paused.rawValue
            request.subject = event.subject
            if await speakStream(request) != .spoke {
                await say("I paused a session: \(event.summary).")
            }
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
        var request = newRequest(.confirm)
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

    private func decline(_ event: DaemonEvent) async {
        var request = newRequest(.confirm)
        request.subject = event.subject
        request.answer = ProposalAnswer.declined.rawValue
        _ = try? await link.request(request)
        await say("Something proposed an allow you did not ask for, so I left it as it was.")
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
