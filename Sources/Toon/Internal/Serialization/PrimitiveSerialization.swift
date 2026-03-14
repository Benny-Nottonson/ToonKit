import Foundation

// MARK: - Number Formatter

/// A shared `NumberFormatter` that renders floating-point values in canonical decimal
/// form without scientific notation or trailing zeros.
///
/// Configured once at module load time and shared across all serialization calls for
/// performance. `NumberFormatter` is not thread-safe for mutation, but this instance
/// is never mutated after initialisation.
let toonNumberFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = false
    formatter.maximumFractionDigits = 15
    formatter.minimumFractionDigits = 0
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
}()

// MARK: - Primitive Serialization

extension ToonSerializer {

    func encodePrimitiveList(_ values: [ToonValue], delimiter: String) -> [String] {
        var encodedValues = Array(repeating: "", count: values.count)
        var stringIndexes: [Int] = []
        var stringValues: [String] = []

        for (index, value) in values.enumerated() {
            switch value {
            case .string(let stringValue):
                stringIndexes.append(index)
                stringValues.append(stringValue)
            default:
                encodedValues[index] = encodePrimitive(value, delimiter: delimiter) ?? ""
            }
        }

        if let acceleratedStrings = ToonStringLiteralEncoder.encodeBatch(
            stringValues,
            delimiter: delimiter,
            acceleration: config.acceleration
        ) {
            for (offset, index) in stringIndexes.enumerated() {
                encodedValues[index] = acceleratedStrings[offset]
            }
            return encodedValues
        }

        for (offset, index) in stringIndexes.enumerated() {
            encodedValues[index] = encodeStringLiteral(stringValues[offset], delimiter: delimiter)
        }

        return encodedValues
    }

    /// Encodes a primitive ``ToonValue`` to its TOON text representation.
    ///
    /// Returns `nil` for non-primitive values (arrays and objects), which are handled
    /// by ``ToonSerializer`` directly.
    ///
    /// - Parameters:
    ///   - value: The primitive value to encode.
    ///   - delimiter: The active delimiter character (used to decide when to quote strings).
    func encodePrimitive(
        _ value: ToonValue,
        delimiter: String
    ) -> String? {
        switch value {
        case .null:
            return "null"

        case .bool(let booleanValue):
            return booleanValue ? "true" : "false"

        case .int(let integerValue):
            return String(integerValue)

        case .double(let doubleValue):
            return encodeDouble(doubleValue)

        case .string(let stringValue):
            return encodeStringLiteral(stringValue, delimiter: delimiter)

        case .date(let date):
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return encodeStringLiteral(formatter.string(from: date), delimiter: delimiter)

        case .url(let url):
            let absoluteString = url.absoluteString
            if absoluteString.contains(delimiter) || absoluteString.contains("\"") || absoluteString.contains("\\") {
                return "\"\(absoluteString.toonEscaped)\""
            }
            return absoluteString

        case .data(let data):
            return encodeStringLiteral(data.base64EncodedString(), delimiter: delimiter)

        case .array, .object:
            return nil
        }
    }

    // MARK: - Double Formatting

    private func encodeDouble(_ doubleValue: Double) -> String {
        guard doubleValue.isFinite else {
            return encodeNonFiniteDouble(doubleValue)
        }

        if doubleValue == 0.0, doubleValue.sign == .minus {
            return config.preserveNegativeZero ? "-0" : "0"
        }

        if let stringValue = toonNumberFormatter.string(from: NSNumber(value: doubleValue)) {
            return stringValue
        }
        return String(doubleValue)
    }

    private func encodeNonFiniteDouble(_ doubleValue: Double) -> String {
        switch config.nonFiniteFloatStrategy {
        case .null:
            return "null"
        case .throw:
            preconditionFailure("Non-finite Double reached serializer with .throw strategy")
        case .convertToString(let posInf, let negInf, let nan):
            let literal: String
            if doubleValue.isNaN { literal = nan }
            else if doubleValue.sign == .minus { literal = negInf }
            else { literal = posInf }
            return encodeStringLiteral(literal, delimiter: config.delimiter)
        }
    }

    // MARK: - String Quoting

    /// Returns the TOON text for a string value: unquoted when safe, quoted otherwise.
    func encodeStringLiteral(_ stringValue: String, delimiter: String) -> String {
        ToonStringLiteralEncoder.encode(
            stringValue,
            delimiter: delimiter,
            acceleration: config.acceleration
        )
    }

    // MARK: - Key Encoding

    /// Returns the TOON text for an object key: unquoted when valid, quoted otherwise.
    func encodeKey(_ key: String) -> String {
        key.isValidUnquotedKey ? key : "\"\(key.toonEscaped)\""
    }
}
