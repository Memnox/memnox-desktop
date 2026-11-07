import Foundation

/// A JSON value from the demo world, kept typed so a fixture is filtered and stamped without reaching for Any.
public enum DemoJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([DemoJSON])
    case object([String: DemoJSON])

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let flag = try? value.decode(Bool.self) {
            self = .bool(flag)
        } else if let number = try? value.decode(Double.self) {
            self = .number(number)
        } else if let text = try? value.decode(String.self) {
            self = .string(text)
        } else if let items = try? value.decode([DemoJSON].self) {
            self = .array(items)
        } else {
            self = .object(try value.decode([String: DemoJSON].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .null: try value.encodeNil()
        case .bool(let flag): try value.encode(flag)
        case .number(let number):
            // A whole number goes out as one, since the protocol's counts decode as Int.
            if number.rounded() == number, abs(number) < Self.wholeLimit { try value.encode(Int(number)) } else { try value.encode(number) }
        case .string(let text): try value.encode(text)
        case .array(let items): try value.encode(items)
        case .object(let fields): try value.encode(fields)
        }
    }

    /// Past this a Double no longer holds every whole number exactly, so it stays a Double.
    private static let wholeLimit: Double = 9_007_199_254_740_992

    public subscript(key: String) -> DemoJSON? {
        guard case .object(let fields) = self else { return nil }
        return fields[key]
    }

    public var text: String? {
        guard case .string(let text) = self else { return nil }
        return text
    }

    public var items: [DemoJSON] {
        guard case .array(let items) = self else { return [] }
        return items
    }

    public var fields: [String: DemoJSON] {
        guard case .object(let fields) = self else { return [:] }
        return fields
    }

    /// The same object with one field set, for the answers the demo builds from its pieces.
    public func with(_ key: String, _ value: DemoJSON) -> DemoJSON {
        var copy = fields
        copy[key] = value
        return .object(copy)
    }

    /// Every `"$now-5m"` turned into the time five minutes before `now`, so the demo always reads as today.
    public func stamped(now: Date) -> DemoJSON {
        switch self {
        case .string(let text): return .string(DemoTime.stamp(text, now: now) ?? text)
        case .array(let items): return .array(items.map { $0.stamped(now: now) })
        case .object(let fields): return .object(fields.mapValues { $0.stamped(now: now) })
        case .null, .bool, .number: return self
        }
    }
}

/// The relative times the fixture is written in: `$now`, `$now-12m`, `$now+2d`, in seconds, minutes, hours or days.
public enum DemoTime {
    private static let marker = "$now"
    private static let units: [Character: TimeInterval] = ["s": 1, "m": 60, "h": 60 * 60, "d": 24 * 60 * 60]

    /// The time a marker names, written as the daemon writes times, or nil when the text is not a marker.
    public static func stamp(_ text: String, now: Date) -> String? {
        guard text.hasPrefix(marker) else { return nil }
        let rest = text.dropFirst(marker.count)
        var offset: TimeInterval = 0
        if let sign = rest.first, sign == "+" || sign == "-", let unit = rest.last, let size = units[unit],
           let amount = Double(rest.dropFirst().dropLast()) {
            offset = (sign == "-" ? -amount : amount) * size
        } else if !rest.isEmpty {
            return nil
        }
        return iso(now.addingTimeInterval(offset))
    }

    public static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    public static func date(_ text: String) -> Date? {
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
