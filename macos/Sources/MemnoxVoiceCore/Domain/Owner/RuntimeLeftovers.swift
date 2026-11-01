import Foundation

/// What `memnox uninstall --purge` would take out of each agent's own files, for the app to take out itself when there
/// is no memnox left to ask: our hook, our session server and our workspace server. An entry is ours only when its own
/// text names Memnox, so a hook or server the person wrote stays exactly as it was.
public enum RuntimeLeftovers {
    /// The hook every agent runs before a tool call, as the runtime's edit hook names its binary.
    public static let hookMark = "memnox-edit-hook"
    /// The two servers the runtime writes into an agent's MCP config, by the names the runtime gives them.
    public static let serverNames = ["memnox-session", "memnox"]
    /// The keys an agent keeps its servers under: Claude Code, Cursor, Gemini and Windsurf say mcpServers, VS Code servers.
    static let serverKeys = ["mcpServers", "servers"]
    /// The TOML tables the runtime writes servers under, Codex's spelling first, as its mcp-keys.ts lists them.
    static let tomlServers = ["mcp_servers", "mcpServers"]
    /// The runtime's own PATH block, which `memnox setup --path` writes and the app never does.
    public static let pathBegin = "# >>> memnox >>>"
    public static let pathEnd = "# <<< memnox <<<"

    /// The settings with every hook naming our binary taken out, in either shape: nested under a matcher as Claude
    /// Code, Codex and Gemini keep them, or flat as Cursor and Windsurf do. Nil when nothing of ours was there or the
    /// file is not plain JSON, which is left alone rather than rewritten without what could not be read.
    public static func withoutHooks(_ data: Data) -> Data? {
        guard var settings = object(data), let hooks = settings["hooks"] as? [String: Any] else { return nil }
        var kept: [String: Any] = [:]
        var changed = false
        for (event, value) in hooks {
            guard let entries = value as? [Any] else {
                kept[event] = value
                continue
            }
            let remaining = entries.compactMap { entry -> Any? in
                guard let entry = entry as? [String: Any] else { return entry }
                if isOurHook(entry) { return nil }
                guard let inner = entry["hooks"] as? [Any] else { return entry }
                let left = inner.filter { !isOurHook($0 as? [String: Any] ?? [:]) }
                if left.count == inner.count { return entry }
                if left.isEmpty { return nil }
                var trimmed = entry
                trimmed["hooks"] = left
                return trimmed
            }
            if remaining.count != entries.count || !same(remaining, entries) { changed = true }
            if !remaining.isEmpty { kept[event] = remaining }
        }
        guard changed else { return nil }
        if kept.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = kept }
        return encoded(settings)
    }

    /// The MCP config with our two servers taken out where their own text names Memnox; nil when neither was there.
    public static func withoutServers(_ data: Data) -> Data? {
        guard var config = object(data) else { return nil }
        var changed = false
        for key in serverKeys {
            guard var servers = config[key] as? [String: Any] else { continue }
            for name in serverNames {
                guard let entry = servers[name], mentionsMemnox(entry) else { continue }
                servers.removeValue(forKey: name)
                changed = true
            }
            config[key] = servers
        }
        return changed ? encoded(config) : nil
    }

    /// Codex's config.toml with our two server tables taken out, sub tables such as their env included, where the
    /// table's own lines name Memnox; nil when neither was there.
    public static func withoutTomlServers(_ text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        var kept: [String] = []
        var index = 0
        var changed = false
        while index < lines.count {
            let line = lines[index]
            guard let name = ourTable(line) else {
                kept.append(line)
                index += 1
                continue
            }
            var end = index + 1
            while end < lines.count {
                let next = lines[end].trimmingCharacters(in: .whitespaces)
                if next.hasPrefix("["), ourTable(lines[end]) != name { break }
                end += 1
            }
            let body = lines[(index + 1)..<end].joined(separator: "\n")
            if body.lowercased().contains("memnox") {
                changed = true
                // A table that ran to the end takes the blank line that set it off, so the file ends where its last table does.
                if end == lines.count, kept.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { kept.removeLast() }
            } else {
                kept.append(contentsOf: lines[index..<end])
            }
            index = end
        }
        return changed ? kept.joined(separator: "\n") : nil
    }

    /// The links in a global bin folder that lead into the memnox package, by name, so a bin of the same name that
    /// leads anywhere else is left alone. Each pair is a link's name and the path it resolves to.
    public static func binsInto(_ package: String, among links: [(name: String, resolved: String)]) -> [String] {
        let inside = package.hasSuffix("/") ? package : package + "/"
        return links.filter { $0.resolved == package || $0.resolved.hasPrefix(inside) }.map(\.name)
    }

    /// Which of our two server tables a TOML header opens, its own sub tables included.
    private static func ourTable(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
        let inner = trimmed.dropFirst().dropLast().trimmingCharacters(in: .whitespaces)
        for tables in tomlServers {
            for name in serverNames {
                let table = "\(tables).\(name)"
                if inner == table || inner.hasPrefix(table + ".") { return table }
            }
        }
        return nil
    }

    private static func isOurHook(_ hook: [String: Any]) -> Bool {
        (hook["command"] as? String)?.contains(hookMark) == true
    }

    private static func mentionsMemnox(_ entry: Any) -> Bool {
        guard JSONSerialization.isValidJSONObject(entry),
              let data = try? JSONSerialization.data(withJSONObject: entry),
              let text = String(data: data, encoding: .utf8) else { return false }
        return text.lowercased().contains("memnox")
    }

    private static func same(_ left: [Any], _ right: [Any]) -> Bool {
        NSArray(array: left).isEqual(to: right)
    }

    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func encoded(_ value: [String: Any]) -> Data? {
        guard var data = try? JSONSerialization.data(withJSONObject: value,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else {
            return nil
        }
        data.append(Data("\n".utf8))
        return data
    }
}
