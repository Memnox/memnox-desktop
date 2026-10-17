import Foundation

/// Splits bytes into lines, keeping a partial line until the rest of it arrives.
public struct LineSplitter {
    private var pending = Data()
    /// The byte that ends every line of the daemon's protocol.
    private static let newline: UInt8 = 0x0A

    public init() {}

    public mutating func push(_ bytes: Data) -> [String] {
        pending.append(bytes)
        var lines: [String] = []
        while let end = pending.firstIndex(of: Self.newline) {
            let line = pending[pending.startIndex..<end]
            pending.removeSubrange(pending.startIndex...end)
            if let text = String(data: line, encoding: .utf8),
               !text.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.append(text)
            }
        }
        return lines
    }
}

/// `~/.memnox/memnox.sock`, the same path the runtime's `socketPathFor` builds.
public func defaultSocketPath(home: String = NSHomeDirectory()) -> String {
    (home as NSString).appendingPathComponent(socketPathInHome)
}

/// Where the daemon listens, under the person's home folder.
private let socketPathInHome = ".memnox/memnox.sock"
/// How much is read from the socket at once; a longer line simply arrives over several reads.
private let readBufferSize = 64 * 1024

/// One connection per request, the way every seam talks to the daemon.
public final class UnixSocketLink: DaemonLink {
    private let path: String

    public init(path: String = defaultSocketPath()) {
        self.path = path
    }

    public func stream(_ request: DaemonRequest) -> AsyncThrowingStream<DaemonResponse, Error> {
        let path = self.path
        return AsyncThrowingStream { continuation in
            let descriptor: Int32
            do {
                descriptor = try connectUnix(path)
                let line = try encodeLine(request)
                try writeAll(descriptor, line)
            } catch {
                continuation.finish(throwing: error)
                return
            }
            let reader = Thread {
                var splitter = LineSplitter()
                var buffer = [UInt8](repeating: 0, count: readBufferSize)
                while true {
                    let count = read(descriptor, &buffer, buffer.count)
                    if count <= 0 { break }
                    for line in splitter.push(Data(buffer[0..<count])) {
                        do {
                            continuation.yield(try decodeLine(line))
                        } catch {
                            continuation.finish(throwing: error)
                            close(descriptor)
                            return
                        }
                    }
                }
                close(descriptor)
                continuation.finish()
            }
            // Closing the socket ends the blocking read, which is how a caller stops listening.
            continuation.onTermination = { _ in shutdown(descriptor, SHUT_RDWR) }
            reader.start()
        }
    }
}

private func connectUnix(_ path: String) throws -> Int32 {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw ProtocolError.refused("no socket: \(errno)") }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8CString)
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        close(descriptor)
        throw ProtocolError.refused("the socket path is too long: \(path)")
    }
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
        for (index, byte) in bytes.enumerated() { raw[index] = UInt8(bitPattern: byte) }
    }
    let size = socklen_t(MemoryLayout<sockaddr_un>.size)
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, size) }
    }
    guard connected == 0 else {
        close(descriptor)
        throw ProtocolError.notRunning("the Memnox daemon is not running at \(path)")
    }
    guard peerIsCurrentUser(descriptor) else {
        close(descriptor)
        throw ProtocolError.refused("the socket at \(path) belongs to another user, so it is not this person's Memnox")
    }
    return descriptor
}

/// Only a daemon running as this same user may answer, because what it sends is spoken, shown and typed into the person's terminal.
func peerIsCurrentUser(_ descriptor: Int32, user: uid_t = getuid()) -> Bool {
    var peerUser: uid_t = 0
    var peerGroup: gid_t = 0
    return getpeereid(descriptor, &peerUser, &peerGroup) == 0 && peerUser == user
}

private func writeAll(_ descriptor: Int32, _ data: Data) throws {
    try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        var offset = 0
        // Never empty: every line ends in a newline, so the base address exists.
        while offset < raw.count {
            let written = write(descriptor, raw.baseAddress!.advanced(by: offset), raw.count - offset)
            if written <= 0 { throw ProtocolError.disconnected }
            offset += written
        }
    }
}
