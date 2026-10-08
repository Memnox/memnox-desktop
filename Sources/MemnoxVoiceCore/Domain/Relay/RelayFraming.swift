import Foundation

/// What the first byte of a payload inside a mailbox says follows, as remote-contract.md numbers them.
public enum FrameKind: UInt8, CaseIterable, Sendable {
    case handshake = 0x01
    case transport = 0x02
    /// The sender drops its session.
    case close = 0x03
}

/// Why a WebSocket message could not be made or read as a frame.
public enum FramingError: Error, Equatable {
    /// The mailbox id is not the 16 bytes the relay routes by.
    case badMailbox
    /// Past the 65552 bytes the relay forwards in one message.
    case tooLarge(Int)
}

/// One payload as it travels: its kind and the bytes after the kind.
public struct Frame: Equatable, Sendable {
    public let kind: FrameKind
    public let body: Data

    public init(kind: FrameKind, body: Data) {
        self.kind = kind
        self.body = body
    }
}

/// Every binary WebSocket message is mailbox, then kind, then body; the relay reads only the mailbox.
public enum RelayFraming {
    /// A mailbox id is 16 random bytes.
    public static let mailboxLength = 16
    /// The most the relay forwards in one message, mailbox included.
    public static let largestMessage = 65_552

    public static func message(mailbox: Data, frame: Frame) throws -> Data {
        guard mailbox.count == mailboxLength else { throw FramingError.badMailbox }
        var message = Data(mailbox)
        message.append(frame.kind.rawValue)
        message.append(frame.body)
        guard message.count <= largestMessage else { throw FramingError.tooLarge(message.count) }
        return message
    }

    /// The frame inside a message for this mailbox, or nil for one meant elsewhere, empty, or of a kind nobody sends.
    public static func frame(in message: Data, mailbox: Data) -> Frame? {
        let bytes = [UInt8](message)
        guard bytes.count > mailboxLength,
              Data(bytes[0..<mailboxLength]) == mailbox,
              let kind = FrameKind(rawValue: bytes[mailboxLength])
        else { return nil }
        return Frame(kind: kind, body: Data(bytes[(mailboxLength + 1)...]))
    }
}

/// A JSON line cut into transport plaintexts: a flag byte, then up to 65000 bytes of UTF-8.
public enum LineChunks {
    /// The most UTF-8 one chunk carries, which keeps a sealed chunk under Noise's 65535 byte message.
    public static let largestChunk = 65_000
    /// The flag on the chunk that ends a line.
    public static let endsLine: UInt8 = 0x00
    /// The flag on a chunk with more of the same line after it.
    public static let moreFollows: UInt8 = 0x01

    public static func chunks(of line: Data) -> [Data] {
        let bytes = [UInt8](line)
        guard !bytes.isEmpty else { return [Data([endsLine])] }
        var chunks: [Data] = []
        var start = 0
        while start < bytes.count {
            let end = min(start + largestChunk, bytes.count)
            var chunk = Data([end == bytes.count ? endsLine : moreFollows])
            chunk.append(contentsOf: bytes[start..<end])
            chunks.append(chunk)
            start = end
        }
        return chunks
    }
}

/// Why a chunk could not join a line.
public enum ChunkError: Error, Equatable {
    case empty
    case unknownFlag(UInt8)
    /// Longer than any line this app takes, so a peer that never ends one cannot fill the memory.
    case lineTooLong
}

/// Joins chunks back into whole lines as they are decrypted.
public struct LineJoiner {
    private var pending = Data()
    private let longestLine: Int
    /// Many megabytes, far past any answer the daemon sends, and still a bound.
    public static let defaultLongestLine = 16 * 1_024 * 1_024

    public init(longestLine: Int = LineJoiner.defaultLongestLine) {
        self.longestLine = longestLine
    }

    /// The whole line once its last chunk arrives, nil while more is to come.
    public mutating func push(_ plaintext: Data) throws -> Data? {
        guard let flag = plaintext.first else { throw ChunkError.empty }
        pending.append(plaintext.dropFirst())
        guard pending.count <= longestLine else {
            pending = Data()
            throw ChunkError.lineTooLong
        }
        switch flag {
        case LineChunks.endsLine:
            defer { pending = Data() }
            return pending
        case LineChunks.moreFollows:
            return nil
        default:
            pending = Data()
            throw ChunkError.unknownFlag(flag)
        }
    }
}
