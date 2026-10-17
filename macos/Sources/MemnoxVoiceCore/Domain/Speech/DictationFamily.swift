import Foundation

/// The kind of place dictated words land, which decides how they are laid out and never what they say. Read from
/// the app in front by its bundle identifier, and for a browser from the page's window title, since Gmail in Chrome
/// is mail and Linear in Safari is a ticket. The raw values are the ones Memnox Cloud's polish takes.
public enum DictationFamily: String, CaseIterable, Sendable {
    case email
    case workChat = "work_chat"
    case personalChat = "personal_chat"
    case document
    case project
    case codeReview = "code_review"
    case prompt
    case support
    case social
    case general

    /// The family for the app in front, and for a browser the page it shows; general where nothing says otherwise.
    public init(bundleID: String?, windowTitle: String? = nil) {
        let bundle = bundleID?.lowercased() ?? ""
        if let known = Self.apps.first(where: { bundle == $0.key || bundle.hasPrefix($0.key + ".") })?.value {
            self = known
            return
        }
        let title = windowTitle?.lowercased() ?? ""
        if Self.browsers.contains(where: { bundle.hasPrefix($0) }),
           let site = Self.sites.first(where: { title.contains($0.key) })?.value {
            self = site
            return
        }
        self = .general
    }

    /// How the Mac's own cleanup ends a line of this kind: a chat message and a prompt go without a full stop.
    public var style: DictationStyle {
        switch self {
        case .workChat, .personalChat, .social: return .chat
        case .prompt: return .bare
        case .email, .document, .project, .codeReview, .support, .general: return .written
        }
    }

    private static let apps: [String: DictationFamily] = [
        "com.apple.mail": .email, "com.microsoft.outlook": .email, "com.readdle.smartemail-mac": .email,
        "com.superhuman.electron": .email, "com.google.gmail": .email,
        "com.tinyspeck.slackmacgap": .workChat, "com.microsoft.teams": .workChat, "com.microsoft.teams2": .workChat,
        "com.mattermost.desktop": .workChat, "com.hnc.discord": .workChat,
        "com.apple.mobilesms": .personalChat, "net.whatsapp.whatsapp": .personalChat, "desktop.whatsapp": .personalChat,
        "ru.keepcoder.telegram": .personalChat, "org.whispersystems.signal-desktop": .personalChat,
        "com.apple.iwork.pages": .document, "com.microsoft.word": .document, "notion.id": .document,
        "md.obsidian": .document, "com.apple.notes": .document, "com.apple.textedit": .document,
        "com.linear": .project, "com.todoist.mac.todoist": .project, "com.culturedcode.thingsmac": .project,
        "com.github.githubclient": .codeReview,
        "com.microsoft.vscode": .prompt, "com.microsoft.vscodeinsiders": .prompt, "com.todesktop.230313mzl4w4u92": .prompt,
        "com.exafunction.windsurf": .prompt, "com.apple.dt.xcode": .prompt, "com.googlecode.iterm2": .prompt,
        "com.apple.terminal": .prompt, "dev.warp.warp-stable": .prompt, "com.mitchellh.ghostty": .prompt,
        "com.anthropic.claudefordesktop": .prompt, "com.openai.chat": .prompt, "com.openai.codex": .prompt,
        "com.jetbrains": .prompt, "com.sublimetext.4": .prompt, "dev.zed.zed": .prompt,
        "com.tweetbot": .social,
    ]

    private static let browsers = [
        "com.apple.safari", "com.google.chrome", "company.thebrowser.browser", "org.mozilla.firefox",
        "com.microsoft.edgemac", "com.brave.browser", "com.operasoftware.opera",
    ]

    /// What a page's title names, as browsers put it in the window title.
    private static let sites: [(key: String, value: DictationFamily)] = [
        ("gmail", .email), ("outlook", .email), ("inbox", .email),
        ("slack", .workChat), ("teams", .workChat), ("discord", .workChat),
        ("whatsapp", .personalChat), ("messenger", .personalChat), ("telegram", .personalChat),
        ("google docs", .document), ("notion", .document), ("confluence", .document),
        ("linear", .project), ("jira", .project), ("asana", .project), ("trello", .project),
        ("pull request", .codeReview), ("github", .codeReview), ("gitlab", .codeReview),
        ("claude", .prompt), ("chatgpt", .prompt), ("gemini", .prompt),
        ("zendesk", .support), ("intercom", .support), ("help scout", .support),
        ("linkedin", .social), (" / x", .social), ("twitter", .social), ("bluesky", .social),
    ]
}
