import Foundation

// MARK: - ToonValue

/// The internal intermediate representation (IR) used during TOON encoding and decoding.
///
/// During **encoding**, a tree of `ToonValue` nodes is built by the Codable containers
/// as `Encodable.encode(to:)` is called. The complete tree is then serialized to text
/// by ``ToonSerializer``.
///
/// During **decoding**, ``ToonParser`` parses the TOON text into a `ToonValue` tree,
/// which is then consumed by the Codable containers when `Decodable.init(from:)` is called.
///
/// `ToonValue` maps directly to the types defined by the TOON specification:
/// - **Scalars:** null, bool, integer (Int64), floating-point (Double), string
/// - **Foundation types:** date (encoded as ISO 8601), URL (string), data (Base64)
/// - **Structured:** ordered arrays and key-ordered objects
enum ToonValue: Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case date(Date)
    case url(URL)
    case data(Data)
    case array([ToonValue])
    /// An ordered dictionary. `keyOrder` preserves insertion order so that
    /// serialized output matches the property declaration order of `Encodable` types.
    case object([String: ToonValue], keyOrder: [String])
}

// MARK: - Type Checks

extension ToonValue {

    var isNull: Bool {
        guard case .null = self else { return false }
        return true
    }

    /// Returns `true` for all scalar value categories (null, bool, int, double,
    /// string, date, url, data). Returns `false` for arrays and objects.
    var isPrimitive: Bool {
        switch self {
        case .null, .bool, .int, .double, .string, .date, .url, .data: return true
        case .array, .object: return false
        }
    }

    var isArray: Bool {
        guard case .array = self else { return false }
        return true
    }

    var isObject: Bool {
        guard case .object = self else { return false }
        return true
    }
}

// MARK: - Value Accessors

extension ToonValue {

    var boolValue: Bool? {
        guard case let .bool(booleanValue) = self else { return nil }
        return booleanValue
    }

    var intValue: Int64? {
        guard case let .int(integerValue) = self else { return nil }
        return integerValue
    }

    /// Returns the double value, automatically widening `int` values to `Double`.
    var doubleValue: Double? {
        if case let .double(doubleValue) = self { return doubleValue }
        if case let .int(integerValue) = self { return Double(integerValue) }
        return nil
    }

    var stringValue: String? {
        guard case let .string(stringValue) = self else { return nil }
        return stringValue
    }

    var arrayValue: [ToonValue]? {
        guard case let .array(arrayValue) = self else { return nil }
        return arrayValue
    }

    /// Returns the object contents as a `(values:keyOrder:)` tuple, or `nil` if this is
    /// not an object node.
    var objectValue: (values: [String: ToonValue], keyOrder: [String])? {
        guard case let .object(values, keyOrder) = self else { return nil }
        return (values, keyOrder)
    }

    /// A human-readable type name used in error messages.
    var typeName: String {
        switch self {
        case .null:   return "null"
        case .bool:   return "bool"
        case .int:    return "int"
        case .double: return "double"
        case .string: return "string"
        case .date:   return "date"
        case .url:    return "url"
        case .data:   return "data"
        case .array:  return "array"
        case .object: return "object"
        }
    }
}

// MARK: - Array Convenience

extension ToonValue {

    /// True when this is an array whose every element is a primitive.
    var isArrayOfPrimitives: Bool {
        guard let array = arrayValue else { return false }
        return array.allSatisfy { $0.isPrimitive }
    }

    /// True when this is an array whose every element is an object.
    var isArrayOfObjects: Bool {
        guard let array = arrayValue else { return false }
        return array.allSatisfy { $0.isObject }
    }

    /// True when this is an array whose every element is itself an array.
    var isArrayOfArrays: Bool {
        guard let array = arrayValue else { return false }
        return array.allSatisfy { $0.isArray }
    }
}
