import Foundation

/// Where the words go out loud.
public protocol Speaker: AnyObject {
    /// One sentence, returning once it has been said.
    func speak(_ sentence: String) async
    /// Queued behind whatever is being said, so a reply's sentences run on as one.
    func queue(_ sentence: String)
    /// Returns once everything queued has been said.
    func drained() async
    func stop()
}
