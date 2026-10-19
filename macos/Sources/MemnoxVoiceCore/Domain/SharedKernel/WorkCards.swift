import Foundation

/// A tool the person asked for and has not signed in to, with the page that signs them in once.
public struct ToolSignIn: Decodable, Equatable, Identifiable, Sendable {
    public let toolkit: String
    public let url: String
    /// Signed in before as somebody else's account, so this signs in again with their own.
    public let again: Bool?

    public init(toolkit: String, url: String, again: Bool? = nil) {
        self.toolkit = toolkit
        self.url = url
        self.again = again
    }

    public var id: String { toolkit }
    public var signsInAgain: Bool { again == true }
}

/// A sign in that finished, or never did: the tool, the account it reached, what to carry on with, and the
/// proposal "that's me" confirms where nothing ties the account to the person yet.
public struct SignedInNotice: Decodable, Equatable, Sendable {
    public let toolkit: String
    public let account: WorkAccount?
    public let resume: String?
    public let confirm: String?

    public init(toolkit: String, account: WorkAccount? = nil, resume: String? = nil, confirm: String? = nil) {
        self.toolkit = toolkit
        self.account = account
        self.resume = resume
        self.confirm = confirm
    }

    /// Finished, as opposed to a sign in that never did, which reached no account.
    public var finished: Bool { account != nil }

    /// The same sign in with nothing to carry on with, once the conversation has moved past it.
    public var withoutResume: SignedInNotice {
        SignedInNotice(toolkit: toolkit, account: account, confirm: confirm)
    }
}

/// A proposal that an account is the person's own, named so the island answers it from its pill.
public struct AccountClaim: Decodable, Equatable, Sendable {
    public let toolkit: String
    public let label: String
}

/// Whether the account a sign in reached is known to be the person's own, as the workspace checked it.
public enum AccountCheck: String, Sendable {
    case matched
    case unverified
    case mismatch
    case unknown
}

/// The account something goes out as, as the tool itself named it.
public struct WorkAccount: Decodable, Equatable, Sendable {
    public let key: String?
    public let handle: String?
    public let name: String?
    public let check: String

    public init(key: String? = nil, handle: String? = nil, name: String? = nil, check: String) {
        self.key = key
        self.handle = handle
        self.name = name
        self.check = check
    }

    public var accountCheck: AccountCheck { AccountCheck(rawValue: check) ?? .unknown }
    /// The name a card shows: the handle the tool knows them by, else their name.
    public var shown: String? { handle ?? name }
}

/// What kind of thing is drafted, which decides how its card is laid out.
public enum WorkDraftKind: String, Sendable {
    case message
    case comment
    case email
    case issue
    case other
}

public struct WorkField: Decodable, Equatable, Sendable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

/// Something about to go out in the person's name, laid out the way its own tool lays it out.
public struct WorkDraft: Decodable, Equatable, Sendable {
    public let toolkit: String
    public let tool: String
    public let kind: String
    public let account: WorkAccount?
    public let to: [String]?
    /// On a mail, the name the voice found for whom it goes to, shown beside the address and never in its place.
    public let toName: String?
    /// On a mail, the person may rewrite its addresses on the card, which their Touch ID then covers.
    public let toEditable: Bool?
    /// Where it lands: `owner/repo#412`, an issue, a page.
    public let `where`: String?
    public let subject: String?
    public let body: String?
    /// Every other argument, so nothing goes out that the card did not show.
    public let fields: [WorkField]

    public init(
        toolkit: String, tool: String, kind: String, account: WorkAccount? = nil, to: [String]? = nil,
        toName: String? = nil, toEditable: Bool? = nil,
        where place: String? = nil, subject: String? = nil, body: String? = nil, fields: [WorkField] = []
    ) {
        self.toolkit = toolkit
        self.tool = tool
        self.kind = kind
        self.account = account
        self.to = to
        self.toName = toName
        self.toEditable = toEditable
        self.where = place
        self.subject = subject
        self.body = body
        self.fields = fields
    }

    public var draftKind: WorkDraftKind { WorkDraftKind(rawValue: kind) ?? .other }
    /// Whether the card offers the addresses to rewrite, which only a mail with one address argument does.
    public var readdressable: Bool { toEditable == true }

    /// What Touch ID says it is for, so the sheet names the tool and the account it goes out as.
    public var touchIDReason: String { touchIDReason(to: nil) }

    /// The same, naming the addresses the person typed on the card, so the sheet says where it now goes.
    public func touchIDReason(to addresses: [String]?) -> String {
        let tool = ToolkitName.of(toolkit)
        let whom = addresses.map { " to \($0.joined(separator: ", "))" } ?? ""
        guard let who = account?.shown else { return "send this\(whom) on \(tool)" }
        return "send this\(whom) on \(tool) as \(who)"
    }
}

/// Addresses typed on a mail's card, read the one way the runtime reads them so a signature it refuses is never asked for.
public enum MailAddresses {
    /// Every address in what was typed, split on commas and spaces, or nil while any of them is not a plain address.
    public static func parse(_ typed: String) -> [String]? {
        let parts = typed.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy(isAddress) else { return nil }
        return parts
    }

    /// One plain address, refusing the colon, comma and space that would make the signed text read two ways.
    public static func isAddress(_ text: String) -> Bool {
        text.range(of: #"^[^\s:,@]+@[^\s:,@]+\.[^\s:,@]+$"#, options: .regularExpression) != nil
    }

    /// The addresses as the wire and the signature carry them.
    public static func joined(_ addresses: [String]) -> String { addresses.joined(separator: ",") }
}

/// How the person reads each tool's name, which its slug says badly.
public enum ToolkitName {
    private static let names: [String: String] = [
        "github": "GitHub", "gmail": "Gmail", "googledocs": "Google Docs",
        "linear": "Linear", "notion": "Notion", "slack": "Slack",
    ]

    public static func of(_ toolkit: String) -> String {
        names[toolkit] ?? toolkit.prefix(1).uppercased() + toolkit.dropFirst()
    }
}
