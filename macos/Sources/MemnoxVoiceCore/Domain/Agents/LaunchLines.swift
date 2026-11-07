import Foundation

/// The words Launch on an agent's card says, the same as Windows and Linux say them in launch-lines.ts.
public enum LaunchLines {
    /// A folder the runtime can open an agent in: absolute on a Mac or Linux, on a drive or a share on Windows.
    public static func isAbsoluteFolder(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("\\\\") { return true }
        return trimmed.range(of: #"^[A-Za-z]:[\\/]"#, options: .regularExpression) != nil
    }

    /// What the Launch field says before it is sent, or nil when the folder will do.
    public static func folderProblem(_ path: String) -> String? {
        if path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Choose the folder it opens in." }
        return isAbsoluteFolder(path) ? nil : "Give the whole path, from the top of the drive."
    }

    /// "Opened Claude Code in /code/app, typing claude." said under the card.
    public static func launched(_ launched: AgentLaunched, name: String) -> String {
        "Opened \(name) in \(launched.workingDirectory), typing \(launched.line)."
    }
}
