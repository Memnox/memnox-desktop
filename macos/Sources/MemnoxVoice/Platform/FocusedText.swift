import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// The text field the cursor is in, read through Accessibility: what is selected, the words either side of the cursor,
/// and whether it is a password field. Some apps answer none of it, and then dictation still goes in, just without
/// being fitted to what surrounds it.
@MainActor
struct FocusedText {
    let element: AXUIElement?
    /// Selected text, when there is some.
    let selection: String?
    /// The text before and after the cursor or selection, a little of each, to fit the dictation between them.
    let before: String?
    let after: String?
    /// The whole value and where the cursor or selection sits in it, to see later what the person changed.
    let value: String?
    let range: NSRange?
    /// A password field, or anywhere macOS has secure input on: nothing is ever written there by voice.
    let isSecure: Bool
    /// The front window's title, which names the page a browser shows.
    let windowTitle: String?

    /// How much of the text either side is kept, enough to see a sentence end and no more.
    private static let around = 200

    static func read(in app: NSRunningApplication?) -> FocusedText {
        let secureInput = IsSecureEventInputEnabled()
        guard let app else {
            return FocusedText(element: nil, selection: nil, before: nil, after: nil, value: nil, range: nil,
                               isSecure: secureInput, windowTitle: nil)
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        let element = Self.element(application, kAXFocusedUIElementAttribute)
        let window = Self.element(application, kAXFocusedWindowAttribute)
        let title = window.flatMap { Self.string($0, kAXTitleAttribute) }
        guard let element else {
            return FocusedText(element: nil, selection: nil, before: nil, after: nil, value: nil, range: nil,
                               isSecure: secureInput, windowTitle: title)
        }
        let secureField = Self.string(element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole
        let value = Self.string(element, kAXValueAttribute)
        let range = Self.selectedRange(element)
        let selection = Self.string(element, kAXSelectedTextAttribute).flatMap { $0.isEmpty ? nil : $0 }
        var before: String?
        var after: String?
        if let value, let range, let swiftRange = Range(range, in: value) {
            before = String(value[..<swiftRange.lowerBound].suffix(around))
            after = String(value[swiftRange.upperBound...].prefix(around))
        }
        return FocusedText(element: element, selection: selection, before: before, after: after, value: value,
                           range: range, isSecure: secureInput || secureField, windowTitle: title)
    }

    /// The field's value now, for seeing what the person changed after it was written.
    static func value(of element: AXUIElement) -> String? {
        string(element, kAXValueAttribute)
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var found: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &found) == .success,
              let found, CFGetTypeID(found) == AXUIElementGetTypeID() else { return nil }
        // The type was checked just above, so this cast cannot fail.
        return (found as! AXUIElement)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var found: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &found) == .success else { return nil }
        return found as? String
    }

    private static func selectedRange(_ element: AXUIElement) -> NSRange? {
        var found: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &found) == .success,
              let found, CFGetTypeID(found) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        // The type was checked just above, so this cast cannot fail.
        guard AXValueGetValue(found as! AXValue, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }
}
