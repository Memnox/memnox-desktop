import Foundation

/// How a session reads on its detail card: its badge, where it runs, and its changed
/// lines laid out the way a diff reads, kept apart from the view so each is tested without a window.
public enum SessionDetailText {
    /// The badge's words, with how long it has been quiet when that is all there is to say.
    public static func statusLabel(of session: SessionView, now: Date) -> String {
        guard session.status == .quiet, let ago = SessionText.ago(session.lastActive, now: now) else { return session.status.label }
        return "Quiet, \(ago)"
    }

    /// The repository and the app it runs in, which is what tells two sessions of one agent apart.
    public static func place(of session: SessionView) -> String? {
        let parts = [session.repository, session.runningIn].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: SessionText.separator)
    }

    /// The folders a file sits in, last few only, since the file's own name is already in its tab.
    public static func folder(of path: String) -> String {
        let parts = path.split(separator: "/").dropLast()
        return parts.suffix(shownFolders).joined(separator: "/")
    }

    /// A changed line as a diff marks it, and what is left once the indent every line shares is taken off.
    public struct DiffLine: Equatable, Sendable {
        public let added: Bool
        public let text: String
    }

    /// The changed lines with the marker split off and the indent they all share removed, so deeply
    /// nested code still starts at the left edge rather than half way across a narrow panel.
    public static func diffLines(_ lines: [String]) -> [DiffLine] {
        let split = lines.map { line -> (Bool, Substring) in
            (!line.hasPrefix(removedMarker), line.hasPrefix(addedMarker) || line.hasPrefix(removedMarker) ? line.dropFirst() : Substring(line))
        }
        let indents = split.map(\.1).filter { !$0.allSatisfy(\.isWhitespace) }.map { $0.prefix(while: { $0 == " " || $0 == "\t" }).count }
        let shared = indents.min() ?? 0
        return split.map { DiffLine(added: $0.0, text: String($0.1.dropFirst(min(shared, $0.1.prefix(while: { $0 == " " || $0 == "\t" }).count)))) }
    }

    /// The counts of the file the excerpt is from, when the session's file list has it.
    public static func counts(for path: String, in files: [CardFile]) -> CardFile? {
        files.first { $0.path == path } ?? files.first { path.hasSuffix($0.path) || $0.path.hasSuffix(path) }
    }

    private static let addedMarker = "+"
    private static let removedMarker = "-"
    /// Three folders above the file are enough to place it in a repository.
    private static let shownFolders = 3
}
