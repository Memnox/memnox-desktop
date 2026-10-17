import Foundation

/// Daemon text made safe to place inside an AppleScript, because a script runs with the person's own rights.
public enum AppleScriptText {
    /// Where macOS keeps terminal devices, which AppleScript names them by.
    private static let devicePrefix = "/dev/"
    /// A terminal device and nothing else, such as ttys004, so no other text can reach a script through it.
    private static let terminalDevicePattern = #"^ttys?[0-9]+$"#

    /// The text as the body of one AppleScript string: on a single line, with backslashes and quotes escaped.
    public static func quoted(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// The terminal device as AppleScript names it, or nil for anything that is not a real terminal device.
    public static func device(_ tty: String?) -> String? {
        guard let tty else { return nil }
        let name = tty.hasPrefix(devicePrefix) ? String(tty.dropFirst(devicePrefix.count)) : tty
        guard name.range(of: terminalDevicePattern, options: .regularExpression) != nil else { return nil }
        return devicePrefix + name
    }
}
