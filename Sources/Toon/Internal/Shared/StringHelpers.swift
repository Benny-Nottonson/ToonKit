import Foundation
import simd

// MARK: - String Escaping

extension String {
    /// Returns the string with all characters that must be escaped inside a TOON
    /// double-quoted string replaced by their escape sequences.
    ///
    /// The TOON specification defines five escape sequences:
    /// `\\`, `\"`, `\n`, `\r`, and `\t`.
    var toonEscaped: String {
        let utf8Bytes = Array(utf8)
        guard utf8Bytes.requiresToonEscapingSIMD else { return self }

        var escapedBytes: [UInt8] = []
        escapedBytes.reserveCapacity(utf8Bytes.count + utf8Bytes.count / 8)

        for byte in utf8Bytes {
            switch byte {
            case 92:
                escapedBytes.append(92)
                escapedBytes.append(92)
            case 34:
                escapedBytes.append(92)
                escapedBytes.append(34)
            case 10:
                escapedBytes.append(92)
                escapedBytes.append(110)
            case 13:
                escapedBytes.append(92)
                escapedBytes.append(114)
            case 9:
                escapedBytes.append(92)
                escapedBytes.append(116)
            default:
                escapedBytes.append(byte)
            }
        }

        return String(decoding: escapedBytes, as: UTF8.self)
    }
}

// MARK: - Safe-Unquoted Value Check

extension String {
    /// Returns `true` when this string can appear in TOON output *without* surrounding
    /// double quotes — i.e., it is unambiguously a string and not a number, boolean,
    /// null, or structural token.
    ///
    /// A string must be quoted when it:
    /// - Is empty
    /// - Has leading or trailing whitespace
    /// - Looks like a boolean (`true`, `false`) or null
    /// - Looks like a number (integer, decimal, or scientific notation)
    /// - Contains the active delimiter character
    /// - Contains structural characters: `:`, `[`, `]`, `{`, `}`
    /// - Contains characters that require escaping: `"`, `\`, `\n`, `\r`, `\t`
    /// - Starts with `-` (could be mistaken for a list item marker)
    func isSafeUnquoted(delimiter: String = ",") -> Bool {
        guard !isEmpty else { return false }
        guard self == trimmingCharacters(in: .whitespaces) else { return false }
        guard self != "true", self != "false", self != "null" else { return false }
        guard !hasPrefix("-") else { return false }
        guard !isNumericLike else { return false }

        if let delimiterByte = delimiter.utf8.first, delimiter.utf8.count == 1 {
            guard isSafeUnquotedASCII(delimiter: delimiterByte) else { return false }
        } else {
            guard !contains(delimiter) else { return false }
            guard !contains(":"), !contains("\""), !contains("\\") else { return false }
            guard !contains("["), !contains("]"), !contains("{"), !contains("}") else { return false }
            guard !contains("\n"), !contains("\r"), !contains("\t") else { return false }
        }

        return true
    }

    private func isSafeUnquotedASCII(delimiter: UInt8) -> Bool {
        for byte in utf8 {
            switch byte {
            case 34, 92, 10, 13, 9, 58, 91, 93, 123, 125:
                return false
            default:
                if byte == delimiter { return false }
            }
        }
        return true
    }

    /// Returns `true` when this string resembles a numeric literal.
    ///
    /// This covers integers (`42`, `-7`), decimals (`3.14`), scientific notation
    /// (`1.5e10`), and leading-zero sequences (`05`) that would be misread as numbers.
    var isNumericLike: Bool {
        let bytes = Array(utf8)
        guard !bytes.isEmpty else { return false }

        var index = 0
        if bytes[index] == 45 {
            index += 1
            guard index < bytes.count else { return false }
        }

        let integerStartIndex = index
        while index < bytes.count, bytes[index].isASCIIDigit {
            index += 1
        }
        guard index > integerStartIndex else { return false }

        if index < bytes.count, bytes[index] == 46 {
            index += 1
            let fractionalStartIndex = index
            while index < bytes.count, bytes[index].isASCIIDigit {
                index += 1
            }
            guard index > fractionalStartIndex else { return false }
        }

        if index < bytes.count, bytes[index] == 101 || bytes[index] == 69 {
            index += 1
            if index < bytes.count, bytes[index] == 43 || bytes[index] == 45 {
                index += 1
            }

            let exponentStartIndex = index
            while index < bytes.count, bytes[index].isASCIIDigit {
                index += 1
            }
            guard index > exponentStartIndex else { return false }
        }

        return index == bytes.count
    }
}

// MARK: - Valid Key Check

extension String {
    /// Returns `true` when this string can be written as an unquoted TOON object key.
    ///
    /// Unquoted keys follow the pattern `[A-Za-z_][\w.]*` — they start with a letter
    /// or underscore and contain only word characters and dots.
    var isValidUnquotedKey: Bool {
        guard let firstScalar = unicodeScalars.first else { return false }
        guard firstScalar.isASCIIAlpha || firstScalar == "_" else { return false }

        for scalar in unicodeScalars.dropFirst() {
            if scalar == "." { continue }
            if scalar.isASCIIAlphaNumeric || scalar == "_" { continue }
            return false
        }
        return true
    }

    /// Returns `true` when this string is a valid single path segment (no dots).
    ///
    /// Used by the key-folding and path-expansion logic to validate each component
    /// of a dotted key path like `user.profile.name`.
    var isValidIdentifierSegment: Bool {
        guard let firstScalar = unicodeScalars.first else { return false }
        guard firstScalar.isASCIIAlpha || firstScalar == "_" else { return false }

        for scalar in unicodeScalars.dropFirst() {
            guard scalar.isASCIIAlphaNumeric || scalar == "_" else { return false }
        }
        return true
    }
}

// MARK: - Leading Space Trimming

extension String {
    /// Removes a single leading space, if present.
    ///
    /// Used after the `: ` separator in a key-value pair to trim exactly one space
    /// without consuming meaningful leading whitespace in the value.
    func trimmingLeadingSpace() -> String {
        guard first == " " else { return self }
        return String(dropFirst())
    }
}

extension Substring {
    func trimmingLeadingSpace() -> Substring {
        guard first == " " else { return self }
        return dropFirst()
    }

    /// Returns `true` when this substring is a valid single identifier segment.
    var isValidIdentifier: Bool {
        guard let first = first else { return false }
        guard first.isLetter || first == "_" else { return false }
        return dropFirst().allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}

private extension UInt8 {
    var isASCIIDigit: Bool {
        self >= 48 && self <= 57
    }
}

private extension UnicodeScalar {
    var isASCIIAlpha: Bool {
        (value >= 65 && value <= 90) || (value >= 97 && value <= 122)
    }

    var isASCIIAlphaNumeric: Bool {
        isASCIIAlpha || (value >= 48 && value <= 57)
    }
}

private extension Array where Element == UInt8 {
    var requiresToonEscapingSIMD: Bool {
        guard !isEmpty else { return false }

        return withUnsafeBytes { rawBuffer in
            let quoteVector = SIMD16<UInt8>(repeating: 34)
            let backslashVector = SIMD16<UInt8>(repeating: 92)
            let newlineVector = SIMD16<UInt8>(repeating: 10)
            let carriageReturnVector = SIMD16<UInt8>(repeating: 13)
            let tabVector = SIMD16<UInt8>(repeating: 9)

            let vectorSize = MemoryLayout<SIMD16<UInt8>>.size
            var offset = 0
            let limit = rawBuffer.count - (rawBuffer.count % vectorSize)

            while offset < limit {
                let vector = rawBuffer.loadUnaligned(fromByteOffset: offset, as: SIMD16<UInt8>.self)
                if hasAnyTrue(vector .== quoteVector) ||
                    hasAnyTrue(vector .== backslashVector) ||
                    hasAnyTrue(vector .== newlineVector) ||
                    hasAnyTrue(vector .== carriageReturnVector) ||
                    hasAnyTrue(vector .== tabVector)
                {
                    return true
                }
                offset += vectorSize
            }

            while offset < rawBuffer.count {
                let byte = rawBuffer[offset]
                if byte == 34 || byte == 92 || byte == 10 || byte == 13 || byte == 9 {
                    return true
                }
                offset += 1
            }

            return false
        }
    }

    @inline(__always)
    private func hasAnyTrue(_ mask: SIMDMask<SIMD16<Int8>>) -> Bool {
        for index in 0..<mask.scalarCount {
            if mask[index] { return true }
        }
        return false
    }
}
