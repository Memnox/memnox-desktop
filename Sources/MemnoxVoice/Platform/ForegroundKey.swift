import AppKit
import MemnoxVoiceCore

/// The confirmation key with Memnox brought forward while it asks. The notch never activates the app, and a Touch ID
/// sheet raised by an app in the background can show without the sensor answering it, which is a finger on the key
/// that does nothing. The app the person was in comes back to the front once the sheet is gone.
final class ForegroundKey: ConfirmKey {
    private let key: ConfirmKey

    init(_ key: ConfirmKey) {
        self.key = key
    }

    var publicPoint: String { key.publicPoint }

    func sign(_ message: String, reason: String) async throws -> String? {
        let previous = await Self.comeForward()
        defer { Self.giveBack(to: previous) }
        return try await key.sign(message, reason: reason)
    }

    func sign(_ messages: [String], reason: String) async throws -> [String]? {
        let previous = await Self.comeForward()
        defer { Self.giveBack(to: previous) }
        return try await key.sign(messages, reason: reason)
    }

    /// Memnox in front, and the app that was there, unless it was Memnox already.
    @MainActor
    private static func comeForward() -> NSRunningApplication? {
        let front = NSWorkspace.shared.frontmostApplication
        NSApp.activate()
        return front?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : front
    }

    private static func giveBack(to app: NSRunningApplication?) {
        guard let app else { return }
        Task { @MainActor in app.activate() }
    }
}
