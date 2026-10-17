import Foundation

/// A walk through a session's change: a heading and one page per file.
public struct WalkCard: Equatable {
    public let title: String
    public let pages: [WalkPage]
    public let sessionId: String?
    public let host: DisplayHost?

    public init(title: String, pages: [WalkPage], sessionId: String? = nil, host: DisplayHost? = nil) {
        self.title = title
        self.pages = pages
        self.sessionId = sessionId
        self.host = host
    }
}

/// What a summary card shows: a heading, the summary being said, and the code behind it.
public struct SummaryCard: Equatable {
    public let title: String
    public let text: String
    public let files: [CardFile]
    public let excerpt: CardExcerpt?
    /// The session it summarises and where it runs, so a button on the card goes straight to it.
    public let sessionId: String?
    public let host: DisplayHost?

    public init(title: String, text: String, files: [CardFile] = [], excerpt: CardExcerpt? = nil,
                sessionId: String? = nil, host: DisplayHost? = nil) {
        self.title = title
        self.text = text
        self.files = files
        self.excerpt = excerpt
        self.sessionId = sessionId
        self.host = host
    }
}
