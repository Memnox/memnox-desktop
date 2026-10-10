import AppKit
import MemnoxVoiceCore

/// Reads a terminal tab back after words were typed into it, so the voice only calls them sent when
/// they are there to be seen. Both terminals answer by script whether or not the tab is in front.
@MainActor
enum Readback {
    /// The two terminals whose tabs can be read by script.
    enum Terminal {
        case iTerm
        case terminal

        var name: String {
            switch self {
            case .iTerm: return "iTerm"
            case .terminal: return "Terminal"
            }
        }
    }

    private enum Timing {
        /// How often the tab is read while the words settle into it.
        static let poll: TimeInterval = 0.1
        /// Long enough for an agent to echo a prompt, short enough to answer before the brain stops waiting.
        static let looks = 30
        static let nanosecondsPerSecond: TimeInterval = 1_000_000_000
    }

    /// Everything the tab shows now, or nil when no tab holds the terminal.
    static func text(_ terminal: Terminal, tty: String) -> String? {
        guard let device = AppleScriptText.device(tty) else { return nil }
        return run(terminal == .iTerm ? iTermContents(device) : terminalHistory(device))
    }

    /// Reads the tab until the words show there once more than before, then says what was seen.
    static func landed(_ words: String, in terminal: Terminal, tty: String, before: String?) async -> Proof? {
        guard let before else { return nil }
        for _ in 0..<Timing.looks {
            try? await Task.sleep(nanoseconds: UInt64(Timing.poll * Timing.nanosecondsPerSecond))
            guard let after = text(terminal, tty: tty) else { return nil }
            if Evidence.landed(words, before: before, after: after) {
                return Proof(checked: "the words in its \(terminal.name) tab", seen: Evidence.excerpt(after, around: words))
            }
        }
        diary.note("typed into \(tty) but never saw the words there")
        return nil
    }

    private static func iTermContents(_ tty: String) -> String {
        """
        tell application "iTerm"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then return contents of s
                    end repeat
                end repeat
            end repeat
        end tell
        return ""
        """
    }

    private static func terminalHistory(_ tty: String) -> String {
        """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then return history of t
                end repeat
            end repeat
        end tell
        return ""
        """
    }

    /// The script's text, or nil when it failed or found no tab.
    private static func run(_ source: String) -> String? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { diary.note("could not read the terminal back: \(error)") }
        guard let text = result?.stringValue, !text.isEmpty else { return nil }
        return text
    }
}
