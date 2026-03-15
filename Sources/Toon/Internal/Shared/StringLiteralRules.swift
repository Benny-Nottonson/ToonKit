import Foundation

enum ToonStringLiteralRules {
    static let trueLiteral: [UInt8] = [116, 114, 117, 101]
    static let falseLiteral: [UInt8] = [102, 97, 108, 115, 101]
    static let nullLiteral: [UInt8] = [110, 117, 108, 108]

    @inline(__always)
    static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        switch byte {
        case 9, 10, 11, 12, 13, 32:
            return true
        default:
            return false
        }
    }

    @inline(__always)
    static func requiresEscaping(_ byte: UInt8) -> Bool {
        switch byte {
        case 92, 34, 10, 13, 9:
            return true
        default:
            return false
        }
    }

    @inline(__always)
    static func appendEscapedByte(_ byte: UInt8, to output: inout [UInt8]) {
        switch byte {
        case 92:
            output.append(92)
            output.append(92)
        case 34:
            output.append(92)
            output.append(34)
        case 10:
            output.append(92)
            output.append(110)
        case 13:
            output.append(92)
            output.append(114)
        case 9:
            output.append(92)
            output.append(116)
        default:
            output.append(byte)
        }
    }

    static func bytesEqual(
        bytes: [UInt8],
        startIndex: Int,
        endIndex: Int,
        literal: [UInt8]
    ) -> Bool {
        if (endIndex - startIndex) != literal.count {
            return false
        }

        for offset in 0..<literal.count where bytes[startIndex + offset] != literal[offset] {
            return false
        }
        return true
    }

    static func isNumericASCII(bytes: [UInt8], startIndex: Int, endIndex: Int) -> Bool {
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

    @inline(__always)
    private static func isDigit(_ byte: UInt8) -> Bool {
        byte >= 48 && byte <= 57
    }
}
