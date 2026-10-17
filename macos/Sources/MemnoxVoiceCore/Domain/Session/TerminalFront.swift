import Foundation

/// Whether an agent is the program in front on a terminal, read from `ps -o stat=,comm= -t <tty>`,
/// where `+` marks the foreground. The same programs the runtime and the editor extension check for.
public enum TerminalFront {
    private static let agentPrograms: Set<String> = ["claude", "node", "codex", "gemini", "cursor-agent", "aider", "opencode"]
    private static let foregroundMark: Character = "+"
    /// Folders a native install keeps an agent in; never node's, which holds shells and tools too.
    private static let agentFolders = agentPrograms.subtracting(["node"])
    /// The agent's own folder and the versions folder inside it.
    private static let versionedFolders = 2

    /// True when a line of the listing is an agent marked as in front, so the session lives in that terminal.
    public static func agentInFront(_ listing: String) -> Bool {
        listing.split(separator: "\n").contains { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard let stat = fields.first, stat.contains(foregroundMark), fields.count > 1 else { return false }
            let path = fields.dropFirst().joined(separator: " ")
            let parts = path.lowercased().split(separator: "/").map(String.init)
            guard let program = parts.last else { return false }
            if agentPrograms.contains(program) { return true }
            // A native install runs a binary named for its version, like claude/versions/2.1.3, so its folder names the agent.
            let folders = parts.dropLast().suffix(versionedFolders)
            return folders.contains { agentFolders.contains($0) }
        }
    }
}
