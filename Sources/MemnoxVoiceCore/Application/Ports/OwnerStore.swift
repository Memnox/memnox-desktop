import Foundation

/// Who the voice is talking to, by the name they chose, so a question starts with their name
/// the way a colleague's would.
public protocol OwnerStore: AnyObject {
    var name: String? { get set }
}
