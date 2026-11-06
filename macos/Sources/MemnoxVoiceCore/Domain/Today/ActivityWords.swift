import Foundation

/// An action an agent took, said the way a person would say it, such as Changed form-parts.tsx in memnox-client,
/// so Today reads without knowing what filesystem.write means; Activity keeps the action as written.
public enum ActivityWords {
    private static let changes: Set<String> = [
        "filesystem.write", "file.write", "file.edit", "file.create", "fs.write", "notebook.edit",
    ]
    private static let reads: Set<String> = ["filesystem.read", "file.read", "fs.read", "environment.read"]
    private static let deletes: Set<String> = ["filesystem.delete", "file.delete", "fs.delete"]
    private static let gitVerbs: [String: String] = [
        "git.push": "Pushed", "git.commit": "Saved a commit", "git.pull": "Pulled", "git.merge": "Merged",
        "git.checkout": "Switched branch", "git.reset": "Reset", "git.clone": "Copied a repository",
    ]
    /// Folders that sit inside a project, so the folder above the first of them names the project.
    private static let insideProject: Set<String> = [
        "apps", "app", "src", "packages", "lib", "Sources", "Tests", "components", "test", "tests", "docs",
        "cmd", "internal", "scripts", "public", ".github", "ios", "android", "macos", "shared",
    ]

    public static func line(operation: String, target: String?) -> String {
        let target = target?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        if changes.contains(operation) { return files("Changed", target) }
        if reads.contains(operation) { return files("Read", target) }
        if deletes.contains(operation) { return files("Deleted", target) }
        if let verb = gitVerbs[operation] { return verb }
        let family = operation.split(separator: ".").first.map(String.init) ?? operation
        switch family {
        case "shell", "process": return target.map { "Ran \(command($0))" } ?? "Ran a command"
        case "http", "web", "fetch": return target.map { "Reached \(host($0))" } ?? "Reached a website"
        case "mcp": return target.map { "Used \($0)" } ?? "Used a tool"
        default: return StudioLines.activityLine(operation: operation, target: target)
        }
    }

    private static func files(_ verb: String, _ target: String?) -> String {
        guard let target, target.hasPrefix("/") || target.hasPrefix("~") else {
            return target.map { "\(verb) \($0)" } ?? "\(verb) files"
        }
        let isFolder = target.hasSuffix("/") || target.hasSuffix("/.")
        let parts = target.split(separator: "/").map(String.init).filter { $0 != "." && $0 != "~" }
        let name = isFolder ? nil : parts.last
        let place = project(in: isFolder ? parts : Array(parts.dropLast()))
        switch (name, place) {
        case let (name?, place?): return "\(verb) \(name) in \(place)"
        case let (name?, nil): return "\(verb) \(name)"
        case let (nil, place?): return "\(verb) files in \(place)"
        case (nil, nil): return "\(verb) files"
        }
    }

    /// The folder above the first one that only a project holds, else the folder the file sits in.
    private static func project(in folders: [String]) -> String? {
        if let inside = folders.indices.first(where: { $0 > 0 && insideProject.contains(folders[$0]) }) {
            return folders[inside - 1]
        }
        return folders.last
    }

    /// The program a command ran, since its arguments can be long and say little to a person.
    private static func command(_ target: String) -> String {
        target.split(separator: " ").first.map(String.init) ?? target
    }

    private static func host(_ target: String) -> String {
        URL(string: target)?.host ?? target
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
