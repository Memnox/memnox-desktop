import Foundation

/// The first name of the account's full name, which is what setup offers before asking.
public func suggestedName(fullName: String) -> String {
    fullName.split(separator: " ").first.map(String.init) ?? fullName
}

/// A held call as a person would put it: name, who, where, on what, wanting what, and why.
/// Built from facts the daemon sent, so it never says anything the daemon did not know.
/// `label` is the call's one label, "Claude Code on your Mac", said in place of the bare agent where it is given.
public func heldQuestion(owner: String?, event: DaemonEvent, label: String? = nil) -> String {
    var sentence: String
    if let what = event.what, !what.isEmpty {
        sentence = label ?? event.agentName ?? event.agent
        if let place = event.place, !place.isEmpty { sentence += " in \(place)" }
        // A follow up is what the call answers to, so it is said over the mission it belongs to.
        if let lastAsk = event.lastAsk, !lastAsk.isEmpty {
            sentence += ", after you said \(caption(lastAsk, limit: taskCaptionLimit)),"
        } else if let task = event.task, !task.isEmpty {
            sentence += ", working on \(caption(task, limit: taskCaptionLimit)),"
        }
        sentence += " wants to \(withShortPaths(what))"
    } else {
        // An older daemon sends only the summary, which already says who wants what.
        sentence = withShortPaths(event.summary)
    }
    if let owner, !owner.isEmpty { sentence = "\(owner), \(sentence)" }
    var question = ended(sentence)
    if let why = event.why, !why.isEmpty { question += " \(ended(withShortPaths(why)))" }
    return "\(question) \(heldAsk)"
}

/// A teammate's call the workspace routed here, said the way a call on this Mac is: who and where, what it wants and why.
/// Every ask names it to the brain, so it ends on the same question and the answer can be spoken or pressed.
public func teamQuestion(owner: String?, call: WorkspaceHeldCall) -> String {
    var question = "\(call.who) is waiting on you."
    if let owner, !owner.isEmpty { question = "\(owner), \(question)" }
    question += " \(ended(withShortPaths(call.what)))"
    let why = call.whyHeld
    if !why.isEmpty { question += " \(ended(withShortPaths(why)))" }
    return "\(question) \(heldAsk)"
}

/// The question every held call ends on, this Mac's, a server's or a team's.
public let heldAsk = "Allow it, or deny?"

/// A sentence that ends in punctuation, so the voice pauses where a person would.
private func ended(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let last = trimmed.last else { return trimmed }
    return sentenceEnds.contains(last) ? trimmed : "\(trimmed)."
}

/// Long enough to say what the agent is on, short enough that the question still comes quickly.
private let taskCaptionLimit = 70
/// Marks a sentence already ends with, so no full stop is added after them.
private let sentenceEnds = ".!?"
