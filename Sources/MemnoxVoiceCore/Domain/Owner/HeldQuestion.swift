import Foundation

/// The first name of the account's full name, which is what setup offers before asking.
public func suggestedName(fullName: String = NSFullUserName()) -> String {
    fullName.split(separator: " ").first.map(String.init) ?? fullName
}

/// A held call as a person would put it: name, who, where, on what, wanting what, and why.
/// Built from facts the daemon sent, so it never says anything the daemon did not know.
public func heldQuestion(owner: String?, event: DaemonEvent) -> String {
    var sentence: String
    if let what = event.what, !what.isEmpty {
        sentence = event.agentName ?? event.agent
        if let place = event.place, !place.isEmpty { sentence += " in \(place)" }
        if let task = event.task, !task.isEmpty {
            sentence += ", working on \(caption(task, limit: taskCaptionLimit)),"
        }
        sentence += " wants to \(what)"
    } else {
        // An older daemon sends only the summary, which already says who wants what.
        sentence = event.summary
    }
    if let owner, !owner.isEmpty { sentence = "\(owner), \(sentence)" }
    var question = ended(sentence)
    if let why = event.why, !why.isEmpty { question += " \(ended(why))" }
    return "\(question) Allow it, or deny?"
}

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
