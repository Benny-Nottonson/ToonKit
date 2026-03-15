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

        if T.self == String.self {
            if let strictQuoted = try decodeStrictQuotedJSONStringFastPath(from: data) {
                return strictQuoted as! T
            }

            if let fastString = try decodeTopLevelStringFastPath(from: data) {
                return fastString as! T
            }
        }

        if let scalarValue = try Self.parseTopLevelScalarFastPath(from: data) {
            if let directValue: T = Self.decodeDirectPrimitive(T.self, from: scalarValue) {
                return directValue
            }

            let implementation = ToonDecoderImplementation(
                value: scalarValue,
                codingPath: [],
                userInfo: [:]
            )
            return try T(from: implementation)
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

    private static func parseTopLevelScalarFastPath(from data: Data) throws -> ToonValue? {
        return try data.withUnsafeBytes { rawBuffer -> ToonValue? in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }

            let count = rawBuffer.count
            if count == 0 { return nil }

            var start = 0
            var end = count

            while start < end, Self.isASCIIWhitespace(baseAddress[start]) {
                start += 1
            }
            while end > start, Self.isASCIIWhitespace(baseAddress[end - 1]) {
                end -= 1
            }

            guard start < end else { return nil }

            var index = start
            while index < end {
                let byte = baseAddress[index]
                if byte == 10 || byte == 13 {
                    return nil
                }
                index += 1
            }

            if baseAddress[start] == 34, end - start >= 2, baseAddress[end - 1] == 34 {
                let value = try decodeQuotedStringFromUTF8(baseAddress, start: start + 1, end: end - 1)
                return .string(value)
            }

            let primitiveBytes = UnsafeBufferPointer(start: baseAddress + start, count: end - start)
            let parsedValue = try ToonPrimitiveParser.parsePrimitive(utf8: primitiveBytes)
            switch parsedValue {
            case .bool, .null, .int, .double:
                return parsedValue
            case .string, .array, .object, .date, .url, .data:
                return nil
            }
        }
    }

    private func decodeTopLevelStringFastPath(from data: Data) throws -> String? {
        try data.withUnsafeBytes { rawBuffer -> String? in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return nil
            }

            let count = rawBuffer.count
            if count == 0 { return nil }

            var start = 0
            var end = count

            while start < end, Self.isASCIIWhitespace(baseAddress[start]) {
                start += 1
            }
            while end > start, Self.isASCIIWhitespace(baseAddress[end - 1]) {
                end -= 1
            }
            guard start < end else { return nil }

            if baseAddress[start] != 34 || end - start < 2 || baseAddress[end - 1] != 34 {
                if baseAddress[start] == 91 {
                    return nil
                }

                var colonScanIndex = start
                while colonScanIndex < end {
                    if baseAddress[colonScanIndex] == 58 {
                        return nil
                    }
                    colonScanIndex += 1
                }

                let primitiveBytes = UnsafeBufferPointer(start: baseAddress + start, count: end - start)
                if isClearlyUnquotedString(primitiveBytes) {
                    return String(decoding: primitiveBytes, as: UTF8.self)
                }

                let parsedValue = try ToonPrimitiveParser.parsePrimitive(utf8: primitiveBytes)
                if case .string(let stringValue) = parsedValue {
                    return stringValue
                }
                return nil
            }

            var index = start
            while index < end {
                let byte = baseAddress[index]
                if byte == 10 || byte == 13 {
                    return nil
                }
                index += 1
            }

            do {
                if start == 0, end == data.count {
                    return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String
                }

                let trimmed = data.subdata(in: start..<end)
                return try JSONSerialization.jsonObject(with: trimmed, options: [.fragmentsAllowed]) as? String
            } catch {
                return try Self.decodeQuotedStringFromUTF8(baseAddress, start: start + 1, end: end - 1)
            }
        }
    }

    private func decodeStrictQuotedJSONStringFastPath(from data: Data) throws -> String? {
        guard data.count >= 2,
              data[data.startIndex] == 34,
              data[data.index(before: data.endIndex)] == 34
        else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String
    }

    private func isClearlyUnquotedString(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        if bytes.isEmpty { return false }

        if bytes.count == 4,
           bytes[0] == 116,
           bytes[1] == 114,
           bytes[2] == 117,
           bytes[3] == 101
        {
            return false
        }

        if bytes.count == 5,
           bytes[0] == 102,
           bytes[1] == 97,
           bytes[2] == 108,
           bytes[3] == 115,
           bytes[4] == 101
        {
            return false
        }

        if bytes.count == 4,
           bytes[0] == 110,
           bytes[1] == 117,
           bytes[2] == 108,
           bytes[3] == 108
        {
            return false
        }

        for byte in bytes {
            if byte >= 128 {
                return true
            }

            if (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122) {
                if byte != 101 && byte != 69 {
                    return true
                }
            }
        }

        return false
    }

    @inline(__always)
    private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == 32 || byte == 9 || byte == 11 || byte == 12
    }

    private static func decodeQuotedStringFromUTF8(
        _ bytes: UnsafePointer<UInt8>,
        start: Int,
        end: Int
    ) throws -> String {
        var hasEscape = false
        var index = start
        while index < end {
            if bytes[index] == 92 {
                hasEscape = true
                break
            }
            index += 1
        }

        if !hasEscape {
            return String(decoding: UnsafeBufferPointer(start: bytes + start, count: end - start), as: UTF8.self)
        }

        var decodedBytes: [UInt8] = []
        decodedBytes.reserveCapacity(end - start)

        index = start
        while index < end {
            let chunkStart = index
            while index < end, bytes[index] != 92 {
                index += 1
            }

            if chunkStart < index {
                decodedBytes.append(contentsOf: UnsafeBufferPointer(start: bytes + chunkStart, count: index - chunkStart))
            }

            if index == end {
                break
            }

            index += 1
            guard index < end else {
                throw ToonDecodingError.invalidEscapeSequence("Trailing backslash")
            }

            switch bytes[index] {
            case 92: decodedBytes.append(92)
            case 34: decodedBytes.append(34)
            case 110: decodedBytes.append(10)
            case 114: decodedBytes.append(13)
            case 116: decodedBytes.append(9)
            default:
                let invalid = String(decoding: [92, bytes[index]], as: UTF8.self)
                throw ToonDecodingError.invalidEscapeSequence(invalid)
            }
            index += 1
        }

        return String(decoding: decodedBytes, as: UTF8.self)
    }

    private static func decodeDirectPrimitive<T>(_: T.Type, from value: ToonValue) -> T? {
        switch value {
        case .string(let rawValue):
            if T.self == String.self { return rawValue as? T }
        case .bool(let rawValue):
            if T.self == Bool.self { return rawValue as? T }
        case .int(let rawValue):
            if T.self == Int.self, let castValue = Int(exactly: rawValue) { return castValue as? T }
            if T.self == Int8.self, let castValue = Int8(exactly: rawValue) { return castValue as? T }
            if T.self == Int16.self, let castValue = Int16(exactly: rawValue) { return castValue as? T }
            if T.self == Int32.self, let castValue = Int32(exactly: rawValue) { return castValue as? T }
            if T.self == Int64.self { return rawValue as? T }
            if T.self == UInt.self, let castValue = UInt(exactly: rawValue) { return castValue as? T }
            if T.self == UInt8.self, let castValue = UInt8(exactly: rawValue) { return castValue as? T }
            if T.self == UInt16.self, let castValue = UInt16(exactly: rawValue) { return castValue as? T }
            if T.self == UInt32.self, let castValue = UInt32(exactly: rawValue) { return castValue as? T }
            if T.self == UInt64.self, let castValue = UInt64(exactly: rawValue) { return castValue as? T }
            if T.self == Double.self { return Double(rawValue) as? T }
            if T.self == Float.self { return Float(rawValue) as? T }
        case .double(let rawValue):
            if T.self == Double.self { return rawValue as? T }
            if T.self == Float.self { return Float(rawValue) as? T }
        default:
            return nil
        }

        return nil
    }
}
