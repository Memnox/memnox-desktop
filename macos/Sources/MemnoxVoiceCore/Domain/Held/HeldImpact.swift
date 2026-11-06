import Foundation

/// How the machine knows one claim about a held action, as memnox-cloud/src/held-calls/held-impact.ts names it.
public enum ClaimBasis: String, Equatable, Sendable, CaseIterable {
    case recorded, extracted, inferred, unknown

    /// The words "More about this" uses, never the face of the card.
    public var words: String {
        switch self {
        case .recorded: return "recorded"
        case .extracted: return "extracted"
        case .inferred: return "inferred, not checked"
        case .unknown: return "not established"
        }
    }
}

/// One sentence the machine wrote about a held action, with how it is known and from what.
public struct HeldClaim: Equatable, Sendable {
    public let text: String
    public let basis: ClaimBasis
    public let source: String

    public init(text: String, basis: ClaimBasis, source: String) {
        self.text = text
        self.basis = basis
        self.source = source
    }

    /// Nil where the text is empty or the basis is not one of the four, as the cloud reads it.
    init?(text: String?, basis: String?, source: String?) {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, let basis = basis.flatMap(ClaimBasis.init(rawValue:)) else { return nil }
        self.init(text: String(trimmed.prefix(HeldImpact.mostClaimText)), basis: basis,
                  source: String((source ?? "").prefix(HeldImpact.mostClaimText)))
    }
}

/// What a held action could affect, whether it can be undone and what was verified. An older runtime sends none, and
/// a part a person needs that is missing drops the whole of it, so the card is then drawn exactly as before.
public struct HeldImpact: Decodable, Equatable, Sendable {
    public let affected: HeldClaim
    public let undo: HeldClaim
    public let verified: [HeldClaim]

    /// A line on a card rather than a document.
    static let mostClaimText = 300
    static let mostVerified = 8

    public static let affectedLabel = "What could be affected"
    public static let undoLabel = "Can it be undone?"
    public static let verifiedLabel = "What has been verified"
    public static let moreLabel = "More about this"

    public init(affected: HeldClaim, undo: HeldClaim, verified: [HeldClaim]) {
        self.affected = affected
        self.undo = undo
        self.verified = verified
    }

    private enum Field: String, CodingKey { case affected, undo, verified }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: Field.self)
        let affected = try? fields.decode(LooseClaim.self, forKey: .affected).claim
        let undo = try? fields.decode(LooseClaim.self, forKey: .undo).claim
        guard let affected, let undo else {
            throw DecodingError.dataCorruptedError(forKey: .affected, in: fields, debugDescription: "affected and undo are both needed")
        }
        // Not a list drops the whole impact, as the cloud does; an unreadable item drops only itself.
        let listed = try fields.decode([LooseClaim].self, forKey: .verified)
        self.init(affected: affected, undo: undo, verified: listed.prefix(Self.mostVerified).compactMap(\.claim))
    }

    /// The three lines on the face of the card, verified claims joined by a space.
    public var lines: [(label: String, text: String)] {
        [(Self.affectedLabel, affected.text), (Self.undoLabel, undo.text),
         (Self.verifiedLabel, verified.map(\.text).joined(separator: " "))]
    }

    /// How each claim is known, for "More about this".
    public var evidence: [(label: String, value: String)] {
        ([affected, undo] + verified).map { claim in
            (claim.basis.words, claim.source.isEmpty ? claim.text : "\(claim.text) (\(claim.source))")
        }
    }
}

/// One claim read without throwing, so an odd item never takes the rest with it.
private struct LooseClaim: Decodable {
    let claim: HeldClaim?

    private enum Field: String, CodingKey { case text, basis, source }

    init(from decoder: Decoder) throws {
        let fields = try? decoder.container(keyedBy: Field.self)
        claim = HeldClaim(text: try? fields?.decodeIfPresent(String.self, forKey: .text),
                          basis: try? fields?.decodeIfPresent(String.self, forKey: .basis),
                          source: try? fields?.decodeIfPresent(String.self, forKey: .source))
    }
}
