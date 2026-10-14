import Foundation

/// The Memnox terminals extension the daemon puts into VS Code, Cursor and Windsurf each time it starts, so the voice
/// reaches a session's own tab. The app only looks whether it landed, since installing it is the daemon's job.
enum EditorExtension {
    /// Where each editor keeps its extensions, under the home folder.
    private static let extensionFolders = [".vscode/extensions", ".cursor/extensions", ".windsurf/extensions"]
    /// The folder the extension installs as, followed by its version.
    private static let folderPrefix = "memnox.memnox-terminals-"

    /// The editors the extension is in, by their folder, so the row can say which.
    static var installedIn: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return extensionFolders.compactMap { folder in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(folder).path)) ?? []
            return names.contains { $0.hasPrefix(folderPrefix) } ? folder : nil
        }
    }

    /// Which editors are on this Mac at all, so a missing extension is only a gap where an editor is.
    static var editorsPresent: Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return extensionFolders.contains { FileManager.default.fileExists(atPath: home.appendingPathComponent($0).path) }
    }
}
