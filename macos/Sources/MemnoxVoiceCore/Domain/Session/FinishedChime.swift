import Foundation

/// Whether a session that finished is chimed: not while the person is in the app it runs in, since they watched it end
/// and a sound would only tell them what they already saw. A session that says nothing of where it runs is chimed.
public func chimesFinish(runningIn host: DisplayHost?, frontApp: String?, frontPath: String?) -> Bool {
    guard let host else { return true }
    if let path = host.appPath, let frontPath, standardized(path) == standardized(frontPath) { return false }
    if let app = host.app, let frontApp, app.caseInsensitiveCompare(frontApp) == .orderedSame { return false }
    return true
}

/// The same bundle however it was written, with or without the slash a folder path ends in.
private func standardized(_ path: String) -> String {
    URL(fileURLWithPath: path).standardizedFileURL.path
}
