import Foundation
import MemnoxNoise

// A thin Swift face over native/noise's C ABI. Every Noise mechanic, the prologue included, comes
// from snow inside that crate; this file only moves bytes in and out of its handles.

/// A nonzero return code from the library.
public struct NoiseError: Error, Equatable {
    public let code: Int32
}

/// The two handshakes remote-contract.md names.
public enum NoisePattern: Sendable {
    /// Noise_IK_25519_ChaChaPoly_BLAKE2s, every connection after pairing.
    case ik
    /// Noise_XXpsk0_25519_ChaChaPoly_BLAKE2s, pairing, with the QR's secret as the PSK.
    case xxpsk0

    var raw: UInt32 {
        switch self {
        case .ik: return UInt32(MEMNOX_NOISE_PATTERN_IK)
        case .xxpsk0: return UInt32(MEMNOX_NOISE_PATTERN_XXPSK0)
        }
    }
}

/// An X25519 keypair made by the library.
public struct NoiseKeypair: Sendable {
    public let publicKey: Data
    public let privateKey: Data

    public static func generate() throws -> NoiseKeypair {
        var publicKey = [UInt8](repeating: 0, count: Int(MEMNOX_NOISE_KEY_LEN))
        var privateKey = [UInt8](repeating: 0, count: Int(MEMNOX_NOISE_KEY_LEN))
        try check(memnox_noise_generate_keypair(&publicKey, &privateKey))
        return NoiseKeypair(publicKey: Data(publicKey), privateKey: Data(privateKey))
    }
}

/// One handshake in progress. Not safe across threads, so its owner keeps it inside an actor.
public final class NoiseHandshake {
    private var handle: OpaquePointer?

    private init(handle: OpaquePointer?) {
        self.handle = handle
    }

    deinit { memnox_noise_handshake_free(handle) }

    public static func initiator(_ pattern: NoisePattern, localPrivate: Data, remotePublic: Data? = nil, psk: Data? = nil) throws -> NoiseHandshake {
        var handle: OpaquePointer?
        try localPrivate.withBytes { local, localLength in
            try (remotePublic ?? Data()).withBytes { remote, remoteLength in
                try (psk ?? Data()).withBytes { psk, pskLength in
                    try check(memnox_noise_handshake_initiator(pattern.raw, local, localLength, remote, remoteLength, psk, pskLength, &handle))
                }
            }
        }
        return NoiseHandshake(handle: handle)
    }

    public static func responder(_ pattern: NoisePattern, localPrivate: Data, psk: Data? = nil) throws -> NoiseHandshake {
        var handle: OpaquePointer?
        try localPrivate.withBytes { local, localLength in
            try (psk ?? Data()).withBytes { psk, pskLength in
                try check(memnox_noise_handshake_responder(pattern.raw, local, localLength, psk, pskLength, &handle))
            }
        }
        return NoiseHandshake(handle: handle)
    }

    public func writeMessage(_ payload: Data) throws -> Data {
        try takeBuffer { out in payload.withBytes { memnox_noise_handshake_write_message(handle, $0, $1, out) } }
    }

    public func readMessage(_ message: Data) throws -> Data {
        try takeBuffer { out in message.withBytes { memnox_noise_handshake_read_message(handle, $0, $1, out) } }
    }

    public var isFinished: Bool {
        var finished = false
        return memnox_noise_handshake_is_finished(handle, &finished) == MEMNOX_NOISE_OK && finished
    }

    public func handshakeHash() throws -> Data {
        try takeBuffer { memnox_noise_handshake_hash(handle, $0) }
    }

    /// Nil while the peer's static key is still unknown.
    public func remoteStatic() throws -> Data? {
        let key = try takeBuffer { memnox_noise_handshake_remote_static(handle, $0) }
        return key.isEmpty ? nil : key
    }

    /// Moves the finished state into a transport; this handshake answers nothing after.
    public func intoTransport() throws -> NoiseTransport {
        var transport: OpaquePointer?
        try check(memnox_noise_handshake_into_transport(handle, &transport))
        return NoiseTransport(handle: transport)
    }
}

/// The cipher states after a handshake. Not safe across threads, so its owner keeps it inside an actor.
public final class NoiseTransport {
    private let handle: OpaquePointer?

    init(handle: OpaquePointer?) {
        self.handle = handle
    }

    deinit { memnox_noise_transport_free(handle) }

    public func encrypt(_ plaintext: Data) throws -> Data {
        try takeBuffer { out in plaintext.withBytes { memnox_noise_transport_encrypt(handle, $0, $1, out) } }
    }

    public func decrypt(_ ciphertext: Data) throws -> Data {
        try takeBuffer { out in ciphertext.withBytes { memnox_noise_transport_decrypt(handle, $0, $1, out) } }
    }

    public func rekeyOutgoing() throws {
        try check(memnox_noise_transport_rekey_outgoing(handle))
    }

    public func rekeyIncoming() throws {
        try check(memnox_noise_transport_rekey_incoming(handle))
    }
}

/// The six digits both screens show, computed by the library from the handshake hash.
public func pairingCode(handshakeHash: Data) throws -> String {
    var code = [CChar](repeating: 0, count: pairingCodeBytes)
    try handshakeHash.withBytes { hash, length in
        try check(memnox_noise_pairing_code(hash, length, &code))
    }
    let digits = code.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: digits, as: UTF8.self)
}

/// Six digits and the terminating zero the library writes.
private let pairingCodeBytes = 7

private func check(_ code: Int32) throws {
    guard code == MEMNOX_NOISE_OK else { throw NoiseError(code: code) }
}

/// Runs a call that fills a library buffer, copies it out, and hands it back to the library to free.
private func takeBuffer(_ call: (UnsafeMutablePointer<MemnoxNoiseBuffer>) -> Int32) throws -> Data {
    var buffer = MemnoxNoiseBuffer(ptr: nil, len: 0)
    let code = call(&buffer)
    defer { memnox_noise_buffer_free(buffer) }
    try check(code)
    guard let pointer = buffer.ptr, buffer.len > 0 else { return Data() }
    return Data(bytes: pointer, count: buffer.len)
}

extension Data {
    /// The bytes as the C ABI takes them: a pointer, null when empty, and a length.
    fileprivate func withBytes<T>(_ body: (UnsafePointer<UInt8>?, Int) throws -> T) rethrows -> T {
        try withUnsafeBytes { raw in
            // The library refuses a pointer with a zero length, since an absent key must be NULL.
            try body(raw.isEmpty ? nil : raw.bindMemory(to: UInt8.self).baseAddress, raw.count)
        }
    }
}
