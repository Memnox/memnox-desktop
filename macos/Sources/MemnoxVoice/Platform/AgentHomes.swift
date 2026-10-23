import AppKit
import CoreServices

/// An app the person runs their agents in, as setup asks about it: the editors Memnox types into and opens chats in,
/// and the terminals whose tabs it finds. Each needs something of its own before Memnox works in it, which setup walks.
enum AgentHome: String, CaseIterable, Identifiable {
    case vscode
    case cursor
    case windsurf
    case iTerm
    case terminal

    var id: String { rawValue }

    var name: String {
        switch self {
        case .vscode: return "VS Code"
        case .cursor: return "Cursor"
        case .windsurf: return "Windsurf"
        case .iTerm: return "iTerm"
        case .terminal: return "Terminal"
        }
    }

    var bundleID: String {
        switch self {
        case .vscode: return "com.microsoft.VSCode"
        case .cursor: return "com.todesktop.230313mzl4w4u92"
        case .windsurf: return "com.exafunction.windsurf"
        case .iTerm: return "com.googlecode.iterm2"
        case .terminal: return "com.apple.Terminal"
        }
    }

    var isEditor: Bool {
        switch self {
        case .vscode, .cursor, .windsurf: return true
        case .iTerm, .terminal: return false
        }
    }

    /// The scheme its links open with, which is also how a link reaches an extension inside it.
    var scheme: String? {
        switch self {
        case .vscode: return "vscode"
        case .cursor: return "cursor"
        case .windsurf: return "windsurf"
        case .iTerm, .terminal: return nil
        }
    }

    /// Where it keeps its extensions under the home folder.
    private var extensionsFolder: String? {
        switch self {
        case .vscode: return ".vscode/extensions"
        case .cursor: return ".cursor/extensions"
        case .windsurf: return ".windsurf/extensions"
        case .iTerm, .terminal: return nil
        }
    }

    var app: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    var installed: Bool { app != nil }
    var running: NSRunningApplication? { NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first }

    /// When an extension whose folder starts so went in, or nil while it is not in.
    func extensionAdded(_ prefix: String) -> Date? {
        guard let extensionsFolder else { return nil }
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(extensionsFolder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix(prefix) }
            .compactMap { try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent($0).path)[.creationDate] as? Date }
            .max()
    }

    /// The link that opens Claude Code's chat in it, the same one a follow up from Memnox opens.
    var claudeChatLink: URL? { scheme.flatMap { URL(string: "\($0)://\(AgentHomeIDs.claudeCode)/open") } }

    /// The page in it that offers Claude Code's extension, for an editor that does not have it yet.
    var claudeExtensionPage: URL? { scheme.flatMap { URL(string: "\($0):extension/\(AgentHomeIDs.claudeCode)") } }
}

/// The extension folders and ids the checks read, kept apart from the cases they belong to.
enum AgentHomeIDs {
    static let memnoxTerminals = "memnox.memnox-terminals-"
    static let claudeCode = "anthropic.claude-code"
    static let claudeCodeFolder = "anthropic.claude-code-"
}

/// Whether Memnox may send a terminal Apple Events, which is how it finds the tab a session runs in and types into it.
enum Automation: Equatable {
    case allowed
    case denied
    /// macOS has not asked yet, so the Allow button asks.
    case notAsked
    /// It can only be asked about while it runs.
    case notRunning

    /// Asks macOS, putting up its question when `ask` is set; it waits on the person, so it never runs on the main thread.
    static func of(_ bundleID: String, ask: Bool) async -> Automation {
        await Task.detached {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
            let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
            switch status {
            case noErr: return Automation.allowed
            case OSStatus(errAEEventNotPermitted): return Automation.denied
            case OSStatus(procNotFound): return Automation.notRunning
            default: return Automation.notAsked
            }
        }.value
    }
}
