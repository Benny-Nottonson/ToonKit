import Foundation

// MARK: - ToonDecoder

/// A decoder that deserializes TOON-format data into `Decodable` values.
///
/// `ToonDecoder` mirrors the design of Foundation's `JSONDecoder`: configure it once
/// and call ``decode(_:from:)`` as many times as needed.
///
/// ```swift
/// let decoder = ToonDecoder()
/// decoder.expandPaths = .safe     // expand dotted keys into nested objects
///
/// let user = try decoder.decode(User.self, from: toonData)
/// ```
///
/// ## Supported Input
///
/// `decode(_:from:)` accepts UTF-8 encoded TOON text conforming to specification
/// version 3.0. Invalid UTF-8 or malformed TOON will throw a ``ToonDecodingError``.
///
/// ## Thread Safety
///
/// `ToonDecoder` instances are **not thread-safe**. Create a separate decoder per thread.
///
/// - SeeAlso: ``ToonEncoder``
public final class ToonDecoder {

    // MARK: - Configuration

    /// Determines how dotted keys (e.g., `user.profile.name`) are interpreted.
    ///
    /// Defaults to ``PathExpansion/automatic``.
    public var expandPaths: PathExpansion = .automatic

    /// Resource limits applied during decoding. Defaults to ``Limits/default``.
    public var limits: Limits = .default

    /// Optional acceleration used for large decoding workloads.
    /// Defaults to ``Acceleration/disabled``.
    public var acceleration: Acceleration = .disabled

    // MARK: - Nested Types

    /// How dotted keys are handled during decoding.
    ///
    /// Dotted keys can represent either:
    /// 1. A **literal** key whose name contains dots.
    /// 2. A **path** that should be expanded into nested objects.
    ///
    /// This mirrors the inverse of ``ToonEncoder/KeyFolding``.
    public enum PathExpansion: Hashable, Sendable {
        /// Expand dotted keys into nested objects, falling back to literal keys on collision
        /// instead of throwing an error. **(Default)**
        ///
        /// This is the safest choice for data from unknown sources.
        case automatic

        /// Never expand dotted keys; treat them as literal string keys.
        ///
        /// Use this when your data model intentionally contains dots in key names.
        case disabled

        /// Expand dotted keys strictly, throwing ``ToonDecodingError/pathCollision(path:line:)``
        /// when expansion would conflict with an existing key.
        case safe
    }

    /// Optional backend used to accelerate large decoding workloads.
    public enum Acceleration: Hashable, Sendable {
        /// Always use the built-in CPU implementation.
        case disabled
        /// Use the Metal-backed batch token decoder for sufficiently large tabular arrays.
        /// The value controls the minimum number of cells required before dispatch.
        case metal(minimumCellCount: Int = 512)
        /// Force the Metal backend when available, without threshold gating.
        /// Primarily useful for benchmarking CPU-vs-Metal behavior.
        case metalForced
    }

    /// Limits that cap resource consumption during decoding.
    public struct Limits: Hashable, Sendable {
        /// Maximum bytes in the input. Defaults to 10 MB.
        public var maxInputSize: Int
        /// Maximum object nesting depth. Defaults to `32`.
        public var maxDepth: Int
        /// Maximum number of keys in a single object. Defaults to `10_000`.
        public var maxObjectKeys: Int
        /// Maximum elements in a single array. Defaults to `100_000`.
        public var maxArrayLength: Int

        /// Default limits, suitable for production use.
        public static let `default` = Limits(
            maxInputSize: 10 * 1024 * 1024,
            maxDepth: 32,
            maxObjectKeys: 10_000,
            maxArrayLength: 100_000
        )

        /// No limits. Use only with fully trusted, locally constructed data.
        ///
        /// - Warning: Malicious input can cause excessive memory usage,
        ///   stack overflow from deep nesting, or denial-of-service attacks.
        public static let unlimited = Limits(
            maxInputSize: .max,
            maxDepth: .max,
            maxObjectKeys: .max,
            maxArrayLength: .max
        )

        public init(maxInputSize: Int, maxDepth: Int, maxObjectKeys: Int, maxArrayLength: Int) {
            self.maxInputSize = maxInputSize
            self.maxDepth = maxDepth
            self.maxObjectKeys = maxObjectKeys
            self.maxArrayLength = maxArrayLength
        }
    }

    // MARK: - Init

    /// Returns `true` when the current process can create the Metal pipeline used by
    /// ``Acceleration/metal(minimumCellCount:)``.
    public static var isMetalAccelerationAvailable: Bool {
        ToonMetalStringAccelerator.shared.isAvailable
    }

    /// Creates a decoder with default configuration.
    public init() {}

    // MARK: - Decoding

    /// Decodes a `Decodable` value from TOON-format data.
    ///
    /// - Parameters:
    ///   - type: The type to decode.
    ///   - data: UTF-8 encoded TOON text.
    /// - Returns: The decoded value.
    /// - Throws: ``ToonDecodingError`` for any parse or type error.
    public func decode<T: Decodable>(_: T.Type, from data: Data) throws -> T {
        guard data.count <= limits.maxInputSize else {
            throw ToonDecodingError.inputTooLarge(size: data.count, limit: limits.maxInputSize)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw ToonDecodingError.invalidFormat("Input is not valid UTF-8")
        }

        let parser = ToonParser(
            text: text,
            expandPaths: expandPaths,
            limits: limits,
            acceleration: acceleration
        )
        let intermediateRepresentation = try parser.parse()

        let implementation = ToonDecoderImplementation(
            value: intermediateRepresentation,
            codingPath: [],
            userInfo: [:]
        )
        return try T(from: implementation)
    }
}
