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
        let requiresLeadingOrTrailingWhitespaceQuoting = ToonStringLiteralRules.isASCIIWhitespace(firstByte)
            || ToonStringLiteralRules.isASCIIWhitespace(lastByte)
        let isReservedLiteral = ToonStringLiteralRules.bytesEqual(
            bytes: bytes,
            startIndex: range.startIndex,
            endIndex: range.endIndex,
            literal: ToonStringLiteralRules.trueLiteral
        )
            || ToonStringLiteralRules.bytesEqual(
                bytes: bytes,
                startIndex: range.startIndex,
                endIndex: range.endIndex,
                literal: ToonStringLiteralRules.falseLiteral
            )
            || ToonStringLiteralRules.bytesEqual(
                bytes: bytes,
                startIndex: range.startIndex,
                endIndex: range.endIndex,
                literal: ToonStringLiteralRules.nullLiteral
            )
        let isNumericLike = ToonStringLiteralRules.isNumericASCII(
            bytes: bytes,
            startIndex: range.startIndex,
            endIndex: range.endIndex
        )
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
            ToonStringLiteralRules.appendEscapedByte(bytes[index], to: &escapedBytes)
            index += 1
        }

        return "\"\(String(decoding: escapedBytes, as: UTF8.self))\""
    }
}