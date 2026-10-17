import Foundation

/// Everything a person says to Memnox, feature by feature, so the recognizer expects each word and
/// whole request rather than hearing "surgeons" for sessions or "right away" for Railway. These only
/// help it hear; the brain still reads every sentence whole, and nothing here acts on a word.
enum SpokenTerms {
    /// Single words and short names, hinted to the recognizer and taught to its model.
    static let terms: [String] = agents + sessions + rules + protection + history + git + tools + workspace + places

    /// Whole requests with how often people say them, which teach the model what follows what.
    static let phrases: [(String, Int)] = naming + asking + acting + ruling + protecting + looking + working + finding

    // MARK: Terms

    private static let agents = [
        "Memnox", "Claude Code", "Claude", "Codex", "Cursor", "Gemini", "Windsurf", "Copilot", "Aider", "Goose",
        "OpenCode", "Hermes", "OpenClaw", "Ruflo", "agent", "agents", "subagent", "subagents", "helper", "helpers",
        "operator", "brain", "voice agent", "Claude desktop", "Claude app", "Codex app", "Codex desktop", "ChatGPT",
        "Cursor app", "Hermes app", "Hermes desktop", "desktop app",
    ]

    private static let sessions = [
        "session", "sessions", "last session", "new session", "latest session", "working", "thinking", "handed back",
        "waiting on you", "paused", "ended", "idle", "quiet", "turn", "prompt", "instruction", "conversation",
        "watch live", "live window", "card", "cards", "panel", "panels", "notch", "island", "orb",
    ]

    private static let rules = [
        "rule", "rules", "policy", "policies", "allow", "allow once", "allow for this session", "deny", "ask",
        "enforce", "enforced", "observe", "investigate", "autonomous", "mode", "Touch ID", "fingerprint",
        "approval", "approvals", "held", "held call", "proposal", "confirm", "decline", "not now", "this Mac",
        "whole Mac", "repository", "repositories", "scope", "force push", "on main",
    ]

    private static let protection = [
        "protect", "protection", "freeze", "unfreeze", "lift the freeze", "lock", "unlock", "budget", "budgets",
        "spend", "limit", "circuit breaker", "probation", "trust", "untrusted", "interceptors", "hooks", "sandbox",
        "credentials", "secrets", "dot env", "SSH keys", "egress", "network", "exfiltration", "unattended",
        "autopilot", "pause", "resume", "stop", "start",
    ]

    private static let history = [
        "timeline", "replay", "rewind", "roll back", "rollback", "checkpoint", "checkpoints", "put it back", "undo",
        "trace", "traces", "why", "explain", "claims", "black box", "ledger", "what happened", "what changed",
        "diff", "changes", "files changed", "walk me through", "summary", "report", "status", "doctor",
        "what to automate next", "capability drift", "effective capability",
    ]

    private static let git = [
        "git", "git status", "git history", "git log", "git diff", "git push", "git pull", "git commit", "git branch",
        "git stash", "git rebase", "git merge", "git checkout", "git fetch", "git reset", "commit", "commits",
        "push", "pull", "pull request", "PR", "branch", "branches", "main", "release branch", "merge", "rebase",
        "stash", "checkout", "tag", "clone", "worktree", "conflict", "collision", "the tests", "tests pass",
        "test suite", "build", "deploy", "lint", "type check",
    ]

    private static let tools = [
        "MCP", "MCP server", "MCP servers", "tool", "tools", "terminal", "iTerm", "Terminal", "VS Code",
        "Visual Studio Code", "Xcode", "Finder", "GitHub", "GitHub CLI", "Linear", "Jira", "Slack", "Discord",
        "Notion", "Gmail", "Outlook", "Railway", "Vercel", "Docker", "Kubernetes", "kubectl", "npm", "pnpm",
        "Yarn", "Node", "Swift", "Postgres", "MongoDB", "Supabase", "AWS", "Anthropic", "OpenAI", "API key",
        "TypeScript", "JavaScript", "Python", "Rust", "Golang", "JSON", "YAML", "TOML", "Markdown", "React", "Next.js",
        "Tailwind", "Vite", "Vitest", "Jest", "ESLint", "Prettier", "Redis", "SQLite", "SQL", "GraphQL", "REST API",
        "API", "endpoint", "webhook", "CI", "GitHub Actions", "Homebrew", "SwiftUI", "Cloudflare", "Netlify",
        "Heroku", "Terraform", "Stripe", "OAuth", "JWT", "localhost", "refactor", "unit test", "Playwright",
        "Figma", "Sentry", "Datadog", "PostHog", "Electron", "monorepo", "changeset", "lockfile", "dependency",
    ]

    private static let workspace = [
        "Memnox Cloud", "Memnox runtime", "Memnox client", "Memnox macOS", "workspace", "log in", "login",
        "sign in", "decisions", "decision", "memory", "brief", "owner", "owners", "ticket", "tickets", "issue",
        "mail", "email", "inbox", "draft", "reply", "send it", "message", "notify me", "tell me when", "remind me",
    ]

    private static let places = [
        "folder", "folders", "open folder", "project", "projects", "Documents", "Desktop", "Downloads", "home folder",
        "in Finder", "in VS Code", "in the editor", "in a terminal", "most used folders",
    ]

    // MARK: Phrases

    /// Memnox and its projects, weighted well above everything else: the name is in no dictionary, so
    /// without the weight "my Knox runtime" outscores "Memnox runtime" on every common word around it.
    private static let naming: [(String, Int)] = [
        ("Memnox", 600),
        ("hey Memnox", 300),
        ("Memnox runtime", 500),
        ("Memnox client", 400),
        ("Memnox cloud", 400),
        ("Memnox macOS", 400),
        ("in Memnox runtime", 300),
        ("within Memnox runtime", 300),
        ("in Memnox client", 200),
        ("in Memnox macOS", 200),
        // "Memnox Marco's" was heard for the Mac app's folder.
        ("Claude Code in Memnox macOS", 200),
        ("Memnox macOS folder", 150),
        ("my Memnox runtime", 200),
        ("open Memnox", 200),
        ("ask Memnox", 200),
        ("Claude Code", 500),
        ("a new Claude Code session", 300),
        ("open Codex", 200),
        // "keto", "cars" and "a mess this up" were heard for these on 2026-10-04.
        ("open Codex desktop", 300),
        ("open the Codex app", 300),
        ("start Codex desktop", 200),
        ("open Claude desktop", 300),
        ("open the Claude app", 200),
        ("open the Cursor app", 200),
        ("open Hermes", 200),
        ("open the Hermes app", 300),
        ("open Hermes desktop", 300),
        ("start Hermes", 200),
    ]

    private static let asking: [(String, Int)] = [
        ("show me all my sessions", 200),
        ("can you show me all my sessions", 200),
        ("what are my agents doing", 200),
        ("what is my last session doing", 150),
        ("is any of these sessions working", 150),
        ("are any of my sessions working", 150),
        ("which sessions are working", 150),
        ("how many sessions are working", 150),
        ("how many agents are working", 150),
        ("how many subagents are running", 100),
        ("what is Claude Code doing", 150),
        ("what did it change", 150),
        ("what files did it change", 100),
        ("did the tests pass", 150),
        ("what is it asking me", 100),
        ("what needs me", 100),
        ("is anything waiting on me", 100),
        ("what happened while I was away", 100),
    ]

    private static let acting: [(String, Int)] = [
        ("tell Claude Code to", 200),
        ("tell my last session to", 150),
        ("ask it to", 150),
        ("tell it to continue", 100),
        ("start a new Claude Code session", 150),
        ("start a new session in", 150),
        ("open the last session", 100),
        ("watch it live", 100),
        ("close all these panels", 100),
        ("close all these session panels", 100),
        ("clear the screen", 100),
        ("close the session", 100),
        ("pause the session", 100),
        ("resume the session", 100),
        ("commit and push", 100),
        ("ask it to review my changes", 200),
        ("review my changes", 200),
        ("git push", 200),
        // Heard as "gate history" and "gate through" when nothing tells the recognizer this is about code.
        ("ask it to check the git history", 200),
        ("a follow up on the last session", 200),
        ("do a follow up in the same session", 200),
        ("in the VS Code terminal", 200),
        ("the Claude Code extension in VS Code", 150),
        ("open VS Code", 150),
        ("git pull", 150),
        ("git commit", 150),
        ("create a pull request", 150),
        ("ask before you push", 100),
        ("ask before you create a pull request", 100),
        ("push to the release branch", 100),
        ("open a pull request", 100),
        ("wait no", 100),
        ("actually", 100),
    ]

    private static let ruling: [(String, Int)] = [
        ("deny git push on main", 150),
        ("never push to main", 100),
        ("always ask before", 100),
        ("allow it once", 100),
        ("allow it for this session", 100),
        ("enforce it on the whole Mac", 100),
        ("only in this repository", 100),
        ("never read the SSH keys", 100),
        ("never touch the env file", 100),
        ("switch to autonomous mode", 100),
        ("switch to observe mode", 100),
    ]

    private static let protecting: [(String, Int)] = [
        ("freeze everything", 100),
        ("lift the freeze", 100),
        ("set a budget", 100),
        ("how much has it spent", 100),
        ("rewind it", 100),
        ("rewind the last change", 100),
        ("roll it back", 100),
        ("put it back the way it was", 100),
        ("can I leave it running", 100),
        ("what can I safely let my agents do", 100),
        ("what should I automate next", 100),
    ]

    private static let looking: [(String, Int)] = [
        ("can you scan my computer", 150),
        ("scan my computer", 150),
        ("show me my agents", 150),
        ("show me the timeline", 100),
        ("show me the trace", 100),
        ("why did it do that", 100),
        ("why was that refused", 100),
        ("walk me through the changes", 100),
        ("show me the git status", 100),
        ("show me the git history", 100),
        // "gate three session" and "recession" were heard for these, so they are weighted over the common words.
        ("review the git history", 150),
        ("check the git history", 150),
        ("the git history session", 150),
        ("is the git history session still running", 150),
        ("is the session still running", 150),
        ("is it still running", 100),
        ("run memnox doctor", 100),
        ("what is my status", 100),
    ]

    private static let working: [(String, Int)] = [
        ("log in to Memnox", 100),
        ("what did we decide about", 100),
        ("who owns", 100),
        ("implement the ticket", 100),
        ("read my mail", 100),
        ("reply to", 100),
        ("tell me when it finishes", 150),
        ("tell me when the tests pass", 100),
        ("remember that", 100),
        ("forget that word", 100),
    ]

    private static let finding: [(String, Int)] = [
        ("open my folder", 100),
        ("open the folder", 150),
        ("open it in Finder", 100),
        // "VS to your code", "VS studio code" and "an item" were heard for these.
        ("open it in VS Code", 200),
        ("open a new session in VS Code", 200),
        ("in VS Code not in iTerm", 150),
        ("I said VS Code", 150),
        ("open it in iTerm", 150),
        ("not in iTerm", 100),
        ("open it in the terminal", 100),
        ("which folders do I use most", 100),
        ("open the memnox runtime folder", 100),
        ("open the memnox macOS folder", 100),
    ]
}
