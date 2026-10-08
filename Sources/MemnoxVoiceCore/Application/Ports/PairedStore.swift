import Foundation

/// Where the paired machines are kept between launches. Each record holds a private key, so the real one is the Keychain.
public protocol PairedStore: AnyObject, Sendable {
    /// Every machine this phone is paired with, oldest pairing first.
    func all() -> [PairedMachine]
    /// Kept beside the others, replacing an earlier pairing with the same machine.
    func save(_ machine: PairedMachine) throws
    func forget(machineId: String)
}
