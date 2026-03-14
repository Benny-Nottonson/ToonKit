import Foundation

// MARK: - Foundation Type Encoding

/// Encodes a `Date` as an ISO 8601 string with fractional seconds and timezone.
///
/// TOON represents dates as quoted ISO 8601 strings, for example:
/// `"2025-11-24T12:00:00.000Z"`
func encodeDateValue(_ date: Date) -> ToonValue {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return .string(formatter.string(from: date))
}

/// Encodes a `URL` as its absolute string representation.
func encodeURLValue(_ url: URL) -> ToonValue {
    .string(url.absoluteString)
}

/// Encodes `Data` as a Base64 string.
func encodeDataValue(_ data: Data) -> ToonValue {
    .string(data.base64EncodedString())
}

// MARK: - Foundation Type Decoding

/// Decodes a `Date` from a TOON value.
///
/// The value must be a string in ISO 8601 format with fractional seconds.
/// - Throws: ``ToonDecodingError/typeMismatch(expected:actual:)`` or
///   ``ToonDecodingError/dataCorrupted(_:)`` on failure.
func decodeDate(from value: ToonValue) throws -> Date {
    guard let string = value.stringValue else {
        throw ToonDecodingError.typeMismatch(expected: "date string", actual: value.typeName)
    }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = formatter.date(from: string) else {
        throw ToonDecodingError.dataCorrupted("Invalid ISO 8601 date: \(string)")
    }
    return date
}

/// Decodes a `URL` from a TOON value.
///
/// The value must be a non-empty string containing a valid URL.
/// - Throws: ``ToonDecodingError/typeMismatch(expected:actual:)`` or
///   ``ToonDecodingError/dataCorrupted(_:)`` on failure.
func decodeURL(from value: ToonValue) throws -> URL {
    guard let string = value.stringValue else {
        throw ToonDecodingError.typeMismatch(expected: "URL string", actual: value.typeName)
    }
    guard !string.isEmpty, let url = URL(string: string) else {
        throw ToonDecodingError.dataCorrupted("Invalid URL: \(string)")
    }
    return url
}

/// Decodes `Data` from a TOON value.
///
/// The value must be a string containing valid Base64.
/// - Throws: ``ToonDecodingError/typeMismatch(expected:actual:)`` or
///   ``ToonDecodingError/dataCorrupted(_:)`` on failure.
func decodeData(from value: ToonValue) throws -> Data {
    guard let string = value.stringValue else {
        throw ToonDecodingError.typeMismatch(expected: "base64 string", actual: value.typeName)
    }
    guard let data = Data(base64Encoded: string) else {
        throw ToonDecodingError.dataCorrupted("Invalid Base64 data")
    }
    return data
}
