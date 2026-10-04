import Foundation

/// How the person asked to be addressed, kept by the runtime in `~/.memnox/voice/owner.json`; nil when
/// they chose none, which means no honorific at all.
public func chosenAddress(home: String = NSHomeDirectory()) -> String? {
    let path = (home as NSString).appendingPathComponent(ownerFilePath)
    guard let data = FileManager.default.contents(atPath: path),
          let owner = try? JSONDecoder().decode(OwnerFile.self, from: data),
          let address = owner.address
    else { return nil }
    let trimmed = address.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? nil : trimmed
}

/// Their name as the runtime keeps it, which the voice keeps for a greeting; nil when it is not known.
public func chosenName(home: String = NSHomeDirectory()) -> String? {
    let path = (home as NSString).appendingPathComponent(ownerFilePath)
    guard let data = FileManager.default.contents(atPath: path),
          let owner = try? JSONDecoder().decode(OwnerFile.self, from: data),
          let name = owner.name
    else { return nil }
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? nil : trimmed
}

/// Where the runtime keeps the person's voice choices, under their home folder.
private let ownerFilePath = ".memnox/voice/owner.json"

/// The fields of the runtime's owner file the voice reads; the rest is the runtime's own.
private struct OwnerFile: Decodable {
    let address: String?
    let name: String?
}
