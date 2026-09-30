import Foundation
import os

/// What the app did lately, kept in memory so "Copy What Happened" can hand it to a person
/// when something goes quiet. The last few hundred steps, never written to disk.
public final class Diary: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private let limit = 300
    private let log = Logger(subsystem: "com.memnox.voice", category: "diary")
    private let clock = ISO8601DateFormatter()

    public init() {}

    public func note(_ line: String) {
        log.info("\(line, privacy: .public)")
        lock.lock()
        lines.append("\(clock.string(from: Date()))  \(line)")
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
        lock.unlock()
    }

    public var text: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}

/// The one diary the app writes to.
public let diary = Diary()
