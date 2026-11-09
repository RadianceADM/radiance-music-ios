import Foundation

/**
 * Any JSON, read loosely (as org.json's opt… on Android): a missing key or the wrong type is nil, never a crash.
 * YouTube Music's answers are deep and change often, so they're walked with this, not with Codable types.
 */
public enum JSON: Sendable, Equatable {
    case object([String: JSON])
    case array([JSON])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public static func parse(_ data: Data) -> JSON? {
        try? JSONDecoder().decode(JSON.self, from: data)
    }

    public static func parse(_ text: String) -> JSON? {
        parse(Data(text.utf8))
    }

    public subscript(key: String) -> JSON? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    public subscript(index: Int) -> JSON? {
        if case .array(let a) = self, index >= 0, index < a.count { return a[index] }
        return nil
    }

    public var object: [String: JSON]? { if case .object(let o) = self { return o }; return nil }
    public var array: [JSON]? { if case .array(let a) = self { return a }; return nil }
    public var isNull: Bool { if case .null = self { return true }; return false }

    /** A string, or a number as text (org.json's optString). */
    public var string: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    public var double: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    public var int: Int? { double.flatMap { $0.isFinite ? Int($0) : nil } }
    public var int64: Int64? { double.flatMap { $0.isFinite ? Int64($0) : nil } }
    public var bool: Bool? { if case .bool(let b) = self { return b }; return nil }

    /** Every value under [key], at any depth (the walk Android's YouTube.collect does). */
    public func collect(_ key: String) -> [JSON] {
        var out: [JSON] = []
        func walk(_ v: JSON) {
            switch v {
            case .object(let o):
                // keys in a steady order, so the same answer always gives the same list
                for k in o.keys.sorted() {
                    let x = o[k]!
                    if k == key { out.append(x) }
                    walk(x)
                }
            case .array(let a):
                a.forEach(walk)
            default:
                break
            }
        }
        walk(self)
        return out
    }

    public func data() -> Data {
        (try? JSONEncoder().encode(self)) ?? Data("null".utf8)
    }

    public func text() -> String {
        String(decoding: data(), as: UTF8.self)
    }
}

extension JSON: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let o): try c.encode(o)
        case .array(let a): try c.encode(a)
        case .string(let s): try c.encode(s)
        case .number(let n):
            if n == n.rounded() && abs(n) < 1e15 { try c.encode(Int64(n)) } else { try c.encode(n) }
        case .bool(let b): try c.encode(b)
        case .null: try c.encodeNil()
        }
    }
}

extension JSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByDictionaryLiteral, ExpressibleByArrayLiteral, ExpressibleByNilLiteral, ExpressibleByFloatLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(dictionaryLiteral elements: (String, JSON)...) { self = .object(Dictionary(elements, uniquingKeysWith: { $1 })) }
    public init(arrayLiteral elements: JSON...) { self = .array(elements) }
    public init(nilLiteral: ()) { self = .null }
}
