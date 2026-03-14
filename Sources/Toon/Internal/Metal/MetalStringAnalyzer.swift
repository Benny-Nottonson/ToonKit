import Foundation

struct ToonASCIIStringRange {
    let originalIndex: Int
    let startIndex: Int
    let endIndex: Int
}

private enum ToonASCIIStringFlags {
    static let needsEscape: UInt8 = 1 << 0
    static let structuralOrDelimiter: UInt8 = 1 << 1
    static let nonASCII: UInt8 = 1 << 7
}

enum ToonASCIIStringAnalyzer {
    static func encode(
        bytes: [UInt8],
        flags: [UInt8],
        range: ToonASCIIStringRange,
        originalString: String
    ) -> String? {
        flags.withUnsafeBufferPointer { flagBuffer in
            encode(bytes: bytes, flags: flagBuffer, range: range, originalString: originalString)
        }
    }

    static func encode(
        bytes: [UInt8],
        flags: UnsafeBufferPointer<UInt8>,
        range: ToonASCIIStringRange,
        originalString: String
    ) -> String? {
        guard range.startIndex >= 0,
              range.endIndex <= bytes.count,
              range.endIndex <= flags.count,
              range.startIndex <= range.endIndex
        else {
            return nil
        }

        if range.startIndex == range.endIndex {
            return "\"\""
        }

        let firstByte = bytes[range.startIndex]
        let lastByte = bytes[range.endIndex - 1]
        let requiresLeadingOrTrailingWhitespaceQuoting = isASCIIWhitespace(firstByte) || isASCIIWhitespace(lastByte)
        let isReservedLiteral = bytesEqual(bytes: bytes, range: range, literal: [116, 114, 117, 101])
            || bytesEqual(bytes: bytes, range: range, literal: [102, 97, 108, 115, 101])
            || bytesEqual(bytes: bytes, range: range, literal: [110, 117, 108, 108])
        let isNumericLike = isNumericASCII(bytes: bytes, startIndex: range.startIndex, endIndex: range.endIndex)
        let startsWithListMarker = firstByte == 45

        var hasEscape = false
        var hasStructuralOrDelimiter = false
        var index = range.startIndex

        while index < range.endIndex {
            let flag = flags[index]
            if flag & ToonASCIIStringFlags.nonASCII != 0 {
                return nil
            }
            if flag & ToonASCIIStringFlags.needsEscape != 0 {
                hasEscape = true
            }
            if flag & ToonASCIIStringFlags.structuralOrDelimiter != 0 {
                hasStructuralOrDelimiter = true
            }
            index += 1
        }

        let requiresQuoting = requiresLeadingOrTrailingWhitespaceQuoting
            || isReservedLiteral
            || isNumericLike
            || hasEscape
            || hasStructuralOrDelimiter
            || startsWithListMarker

        if !requiresQuoting {
            return originalString
        }

        if !hasEscape {
            return "\"\(originalString)\""
        }

        var escapedBytes: [UInt8] = []
        escapedBytes.reserveCapacity((range.endIndex - range.startIndex) + 8)

        index = range.startIndex
        while index < range.endIndex {
            let byte = bytes[index]
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
            index += 1
        }

        return "\"\(String(decoding: escapedBytes, as: UTF8.self))\""
    }

    private static func bytesEqual(bytes: [UInt8], range: ToonASCIIStringRange, literal: [UInt8]) -> Bool {
        if (range.endIndex - range.startIndex) != literal.count {
            return false
        }
        for offset in 0..<literal.count where bytes[range.startIndex + offset] != literal[offset] {
            return false
        }
        return true
    }

    private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        switch byte {
        case 9, 10, 11, 12, 13, 32:
            return true
        default:
            return false
        }
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= 48 && byte <= 57
    }

    private static func isNumericASCII(bytes: [UInt8], startIndex: Int, endIndex: Int) -> Bool {
        if startIndex >= endIndex { return false }

        var index = startIndex
        if bytes[index] == 45 {
            index += 1
            if index >= endIndex { return false }
        }

        let integerStartIndex = index
        while index < endIndex, isDigit(bytes[index]) {
            index += 1
        }
        if index == integerStartIndex { return false }

        if index < endIndex, bytes[index] == 46 {
            index += 1
            let fractionalStartIndex = index
            while index < endIndex, isDigit(bytes[index]) {
                index += 1
            }
            if index == fractionalStartIndex { return false }
        }

        if index < endIndex, bytes[index] == 101 || bytes[index] == 69 {
            index += 1
            if index < endIndex, bytes[index] == 43 || bytes[index] == 45 {
                index += 1
            }
            let exponentStartIndex = index
            while index < endIndex, isDigit(bytes[index]) {
                index += 1
            }
            if index == exponentStartIndex { return false }
        }

        return index == endIndex
    }
}