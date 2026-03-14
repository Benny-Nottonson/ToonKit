import Foundation

// MARK: - ToonEncoder

/// An encoder that serializes `Encodable` values into TOON-format data.
///
/// `ToonEncoder` mirrors the design of Foundation's `JSONEncoder`: configure it once
/// and call ``encode(_:)`` as many times as needed.
///
/// ```swift
/// let encoder = ToonEncoder()
/// encoder.delimiter = .tab       // tab-separated arrays for extra efficiency
/// encoder.keyFolding = .safe     // fold `{ a: { b: 1 } }` → `a.b: 1`
///
/// let data = try encoder.encode(myValue)
/// let toon = String(data: data, encoding: .utf8)!
/// ```
///
/// ## Supported Types
///
/// Any `Encodable` type is supported, including:
/// - Swift standard types (`String`, `Int`, `Double`, `Bool`, …)
/// - Foundation types: `Date` (ISO 8601), `URL` (absolute string), `Data` (Base64)
/// - Arrays, dictionaries, and custom `Codable` structs / classes
///
/// ## Thread Safety
///
/// `ToonEncoder` instances are **not thread-safe**. Create a separate encoder per thread,
/// or protect access with a lock if sharing is required.
///
/// - SeeAlso: ``ToonDecoder``
public final class ToonEncoder {

    // MARK: - Configuration

    /// Number of spaces per indentation level. Defaults to `2`.
    public var indent: Int = 2

    /// The delimiter used in inline arrays and tabular rows. Defaults to ``Delimiter/comma``.
    public var delimiter: Delimiter = .comma

    /// How to encode `-0.0`. Defaults to ``NegativeZeroStrategy/normalize``.
    public var negativeZeroStrategy: NegativeZeroStrategy = .normalize

    /// How to encode `nan`, `inf`, and `-inf`. Defaults to ``NonFiniteFloatStrategy/null``.
    public var nonFiniteFloatStrategy: NonFiniteFloatStrategy = .null

    /// Whether to collapse single-key object chains into dotted keys. Defaults to ``KeyFolding/disabled``.
    public var keyFolding: KeyFolding = .disabled

    /// Maximum path depth when ``keyFolding`` is ``.safe``. Defaults to `Int.max` (unlimited).
    public var flattenDepth: Int = .max

    /// Resource limits applied during encoding. Defaults to ``Limits/default``.
    public var limits: Limits = .default

    /// Optional acceleration used for large string serialization workloads.
    /// Defaults to ``Acceleration/disabled``.
    public var acceleration: Acceleration = .disabled

    // MARK: - Nested Types

    /// The delimiter character separating values in inline arrays and tabular rows.
    public enum Delimiter: String, CaseIterable, Hashable, Sendable {
        /// Comma `,` — default, most compatible.
        case comma = ","
        /// Tab `\t` — useful when values may contain commas.
        case tab = "\t"
        /// Pipe `|` — readable alternative.
        case pipe = "|"
    }

    /// How to handle the IEEE 754 negative-zero value `-0.0`.
    public enum NegativeZeroStrategy: Hashable, Sendable {
        /// Encode `-0.0` as `0` (default).
        case normalize
        /// Encode `-0.0` as the literal `-0`.
        case preserve
    }

    /// How to handle non-finite floating-point values (`nan`, `inf`, `-inf`).
    public enum NonFiniteFloatStrategy: Hashable, Sendable {
        /// Encode as the TOON `null` literal (default).
        case null
        /// Throw an `EncodingError` immediately.
        case `throw`
        /// Encode as a configurable string literal.
        ///
        /// Example:
        /// ```swift
        /// encoder.nonFiniteFloatStrategy = .convertToString(
        ///     positiveInfinity: "Inf",
        ///     negativeInfinity: "-Inf",
        ///     nan: "NaN"
        /// )
        /// ```
        case convertToString(positiveInfinity: String, negativeInfinity: String, nan: String)
    }

    /// Optional backend used to accelerate large string serialization workloads.
    public enum Acceleration: Hashable, Sendable {
        /// Always use the built-in CPU implementation.
        case disabled
        /// Use the Metal-backed string classifier when available and the string is at
        /// least `minimumStringByteCount` UTF-8 bytes long.
        case metal(minimumStringByteCount: Int = 16_384)
        /// Force the Metal backend when available, without adaptive speed gating.
        /// Primarily useful for benchmarking CPU-vs-Metal behavior.
        case metalForced(minimumStringByteCount: Int = 16_384)
    }

    /// Key-folding strategy: whether to collapse chains of single-key objects.
    ///
    /// Example with ``KeyFolding/safe``:
    /// ```
    /// // Input:  { user: { profile: { name: Ada } } }
    /// // Output: user.profile.name: Ada
    /// ```
    public enum KeyFolding: Hashable, Sendable {
        /// No folding — every nesting level is indented (default).
        case disabled
        /// Fold when all path segments are valid identifiers (letters, digits, `_`).
        case safe
    }

    /// Limits that cap resource consumption during encoding.
    public struct Limits: Hashable, Sendable {
        /// Maximum nesting depth. Defaults to `32`.
        public var maxDepth: Int

        /// Sensible defaults for production use (`maxDepth` = 32).
        public static let `default` = Limits(maxDepth: 32)

        /// No limits. Use only with fully trusted, locally constructed data.
        public static let unlimited = Limits(maxDepth: .max)

        public init(maxDepth: Int) { self.maxDepth = maxDepth }
    }

    // MARK: - Init

    /// Creates an encoder with default configuration.
    public init() {}

    /// Returns `true` when the current process can create the Metal pipeline used by
    /// ``Acceleration/metal(minimumStringByteCount:)``.
    public static var isMetalAccelerationAvailable: Bool {
        ToonStringLiteralEncoder.isMetalAccelerationAvailable
    }

    /// Returns `true` when the adaptive speed gate has enabled the Metal backend
    /// for the current process.
    public static var isMetalAccelerationEnabled: Bool {
        ToonStringLiteralEncoder.isMetalAccelerationEnabled
    }

    // MARK: - Encoding

    /// Encodes `value` and returns its UTF-8 TOON representation.
    ///
    /// - Parameter value: Any `Encodable` value.
    /// - Returns: UTF-8 data containing the TOON text.
    /// - Throws: `EncodingError` on failure, or if ``nonFiniteFloatStrategy`` is
    ///   ``NonFiniteFloatStrategy/throw`` and a non-finite `Double` or `Float` is encountered.
    public func encode<T: Encodable>(_ value: T) throws -> Data {
        let intermediateRepresentation = try buildIR(from: value)

        if case .throw = nonFiniteFloatStrategy {
            try validateNonFinite(in: intermediateRepresentation, path: [])
        }

        let configuration = ToonSerializer.Config(
            indent: indent,
            delimiter: delimiter.rawValue,
            preserveNegativeZero: (negativeZeroStrategy == .preserve),
            nonFiniteFloatStrategy: nonFiniteFloatStrategy,
            keyFolding: keyFolding,
            flattenDepth: flattenDepth,
            acceleration: acceleration
        )
        let text = ToonSerializer(config: configuration).serialize(intermediateRepresentation)
        return text.data(using: .utf8) ?? Data()
    }

    // MARK: - Private

    private func buildIR<T: Encodable>(from value: T) throws -> ToonValue {
        if let dateValue = value as? Date { return .date(dateValue) }
        if let urlValue = value as? URL { return .url(urlValue) }
        if let dataValue = value as? Data { return .data(dataValue) }

        let implementation = ToonEncoderImplementation(userInfo: [.toonMaxDepth: limits.maxDepth])
        try value.encode(to: implementation)
        return implementation.result
    }

    /// Recursively walks `value` looking for non-finite doubles.
    /// Called only when ``nonFiniteFloatStrategy`` is ``NonFiniteFloatStrategy/throw``.
    private func validateNonFinite(in value: ToonValue, path: [CodingKey]) throws {
        switch value {
        case .double(let doubleValue) where !doubleValue.isFinite:
            throw EncodingError.invalidValue(
                doubleValue,
                EncodingError.Context(
                    codingPath: path,
                    debugDescription: "Non-finite Double: \(doubleValue)"
                )
            )
        case .array(let array):
            for (index, element) in array.enumerated() {
                try validateNonFinite(in: element, path: path + [IndexedCodingKey(index)])
            }
        case .object(let values, let keyOrder):
            for key in keyOrder {
                if let nestedValue = values[key] {
                    try validateNonFinite(in: nestedValue, path: path + [_StringCodingKey(key)])
                }
            }
        default:
            break
        }
    }
}

private struct _StringCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
