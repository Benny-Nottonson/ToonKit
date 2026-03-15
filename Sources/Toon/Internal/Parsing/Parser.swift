// MARK: - ToonParser

enum ToonPrimitiveParser {

    static func parsePrimitive(_ raw: String) throws -> ToonValue {
        let trimmedValue = raw.trimmingCharacters(in: .whitespaces)

        if trimmedValue.isEmpty { return .string("") }

        if trimmedValue.hasPrefix("\""), trimmedValue.hasSuffix("\"") {
            return try .string(unescapeString(String(trimmedValue.dropFirst().dropLast())))
        }

        if trimmedValue == "true"  { return .bool(true) }
        if trimmedValue == "false" { return .bool(false) }
        if trimmedValue == "null"  { return .null }

        if let integerValue = Int64(trimmedValue) { return .int(integerValue) }

        if let doubleValue = Double(trimmedValue),
              trimmedValue.contains(".") || trimmedValue.contains("e") || trimmedValue.contains("E")
        {
            return .double(doubleValue)
        }

        return .string(trimmedValue)
    }

    static func parsePrimitive(utf8 bytes: UnsafeBufferPointer<UInt8>) throws -> ToonValue {
        var start = 0
        var end = bytes.count

        while start < end, isASCIIWhitespace(bytes[start]) {
            start += 1
        }
        while end > start, isASCIIWhitespace(bytes[end - 1]) {
            end -= 1
        }

        if start == end {
            return .string("")
        }

        let trimmed = UnsafeBufferPointer(rebasing: bytes[start..<end])

        if trimmed.count >= 2, trimmed[0] == 34, trimmed[trimmed.count - 1] == 34 {
            let inner = UnsafeBufferPointer(rebasing: trimmed[1..<(trimmed.count - 1)])
            return try .string(unescapeString(utf8: inner))
        }

        if equalsASCII(trimmed, "true")  { return .bool(true) }
        if equalsASCII(trimmed, "false") { return .bool(false) }
        if equalsASCII(trimmed, "null")  { return .null }

        let scalarText = String(decoding: trimmed, as: UTF8.self)
        if let integerValue = Int64(scalarText) { return .int(integerValue) }

        if let doubleValue = Double(scalarText),
           scalarText.contains(".") || scalarText.contains("e") || scalarText.contains("E")
        {
            return .double(doubleValue)
        }

        return .string(scalarText)
    }

    static func unescapeString(_ str: String) throws -> String {
        guard str.utf8.contains(92) else {
            return str
        }

        return try str.utf8.withContiguousStorageIfAvailable { bytes -> String in
            var result: [UInt8] = []
            result.reserveCapacity(bytes.count)

            var index = bytes.startIndex
            while index < bytes.endIndex {
                let chunkStart = index
                while index < bytes.endIndex, bytes[index] != 92 {
                    index = bytes.index(after: index)
                }

                if chunkStart < index {
                    result.append(contentsOf: bytes[chunkStart..<index])
                }

                if index == bytes.endIndex {
                    break
                }

                index = bytes.index(after: index)
                guard index < bytes.endIndex else {
                    throw ToonDecodingError.invalidEscapeSequence("Trailing backslash")
                }

                switch bytes[index] {
                case 92: result.append(92)
                case 34: result.append(34)
                case 110: result.append(10)
                case 114: result.append(13)
                case 116: result.append(9)
                default:
                    let invalid = String(decoding: [92, bytes[index]], as: UTF8.self)
                    throw ToonDecodingError.invalidEscapeSequence(invalid)
                }

                index = bytes.index(after: index)
            }

            return String(decoding: result, as: UTF8.self)
        } ?? {
            var result = ""
            result.reserveCapacity(str.count)

            var escaped = false
            for character in str {
                if escaped {
                    switch character {
                    case "\\": result.append("\\")
                    case "\"": result.append("\"")
                    case "n":  result.append("\n")
                    case "r":  result.append("\r")
                    case "t":  result.append("\t")
                    default:
                        throw ToonDecodingError.invalidEscapeSequence("\\\\\(character)")
                    }
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else {
                    result.append(character)
                }
            }

            if escaped {
                throw ToonDecodingError.invalidEscapeSequence("Trailing backslash")
            }

            return result
        }()
    }

    static func unescapeString(utf8 bytes: UnsafeBufferPointer<UInt8>) throws -> String {
        var index = 0
        while index < bytes.count {
            if bytes[index] == 92 {
                var result: [UInt8] = []
                result.reserveCapacity(bytes.count)

                var copyStart = 0
                var escapeIndex = index
                while true {
                    if copyStart < escapeIndex {
                        result.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[copyStart..<escapeIndex]))
                    }

                    let escapedByteIndex = escapeIndex + 1
                    guard escapedByteIndex < bytes.count else {
                        throw ToonDecodingError.invalidEscapeSequence("Trailing backslash")
                    }

                    switch bytes[escapedByteIndex] {
                    case 92: result.append(92)
                    case 34: result.append(34)
                    case 110: result.append(10)
                    case 114: result.append(13)
                    case 116: result.append(9)
                    default:
                        let invalid = String(decoding: [92, bytes[escapedByteIndex]], as: UTF8.self)
                        throw ToonDecodingError.invalidEscapeSequence(invalid)
                    }

                    copyStart = escapedByteIndex + 1
                    escapeIndex = copyStart
                    while escapeIndex < bytes.count, bytes[escapeIndex] != 92 {
                        escapeIndex += 1
                    }

                    if escapeIndex >= bytes.count {
                        if copyStart < bytes.count {
                            result.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[copyStart..<bytes.count]))
                        }
                        return String(decoding: result, as: UTF8.self)
                    }
                }
            }
            index += 1
        }

        return String(decoding: bytes, as: UTF8.self)
    }

    @inline(__always)
    private static func isASCIIWhitespace(_ byte: UInt8) -> Bool {
        byte == 32 || byte == 9 || byte == 10 || byte == 11 || byte == 12 || byte == 13
    }

    private static func equalsASCII(_ bytes: UnsafeBufferPointer<UInt8>, _ string: StaticString) -> Bool {
        let expectedCount = string.utf8CodeUnitCount
        guard bytes.count == expectedCount else { return false }
        return string.withUTF8Buffer { literal in
            var index = 0
            while index < expectedCount {
                if bytes[index] != literal[index] {
                    return false
                }
                index += 1
            }
            return true
        }
    }
}

/// Parses a TOON-format string into a ``ToonValue`` tree.
///
/// Construct a parser with the source text and a ``ToonDecoder/Limits`` value,
/// then call ``parse()`` once to obtain the root value.
///
/// The parser is single-use: call ``parse()`` exactly once per instance.
final class ToonParser {

    // MARK: State

    var lines: [String]
    var currentLine: Int = 0

    /// Detected (or default) indent size in spaces per level.
    var indentSize: Int = 2
    var indentDetected: Bool = false

    // MARK: Configuration

    let expandPaths: ToonDecoder.PathExpansion
    let limits: ToonDecoder.Limits
    let acceleration: ToonDecoder.Acceleration

    // MARK: Init

    init(
        text: String,
        expandPaths: ToonDecoder.PathExpansion,
        limits: ToonDecoder.Limits,
        acceleration: ToonDecoder.Acceleration
    ) {
        lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        self.expandPaths = expandPaths
        self.limits = limits
        self.acceleration = acceleration
    }

    // MARK: Entry Point

    /// Parses the TOON source and returns the root value.
    ///
    /// - Throws: ``ToonDecodingError`` for any parse or structural problem.
    func parse() throws -> ToonValue {
        var firstNonEmptyLineIndex: Int?
        var nonEmptyLineCount = 0
        for lineIndex in lines.indices where !lines[lineIndex].isEmpty {
            if firstNonEmptyLineIndex == nil {
                firstNonEmptyLineIndex = lineIndex
            }
            nonEmptyLineCount += 1
        }

        guard let firstNonEmptyLineIndex else {
            return .object([:], keyOrder: [])
        }

        let firstContent = trimIndentation(lines[firstNonEmptyLineIndex]).content

        if firstContent.hasPrefix("["),
           (try? parseArrayHeader(String(firstContent))) != nil
        {
            currentLine = firstNonEmptyLineIndex
            return try parseArrayAtCurrentLine(depth: 0)
        }

        if nonEmptyLineCount == 1, !isKeyValuePair(String(firstContent)) {
            return try parsePrimitive(String(firstContent))
        }

        currentLine = 0
        return try parseObject(atDepth: 0)
    }

    // MARK: - Line Helpers

    func peekLine() -> String? {
        guard currentLine < lines.count else { return nil }
        return lines[currentLine]
    }

    @discardableResult
    func consumeLine() -> String? {
        guard currentLine < lines.count else { return nil }
        defer { currentLine += 1 }
        return lines[currentLine]
    }

    func skipEmptyLines() {
        while currentLine < lines.count, lines[currentLine].isEmpty {
            currentLine += 1
        }
    }

    // MARK: - Indentation

    func trimIndentation(_ line: String) -> (depth: Int, content: Substring) {
        var spaces = 0
        var index = line.startIndex
        while index < line.endIndex, line[index] == " " {
            spaces += 1
            index = line.index(after: index)
        }
        if spaces > 0, !indentDetected {
            indentSize = spaces
            indentDetected = true
        }
        let depth = indentSize > 0 ? spaces / indentSize : 0
        return (depth, line[index...])
    }

    // MARK: - Object Parsing

    func parseObject(atDepth depth: Int) throws -> ToonValue {
        if depth > limits.maxDepth {
            throw ToonDecodingError.depthLimitExceeded(depth: depth, limit: limits.maxDepth)
        }

        var values: [String: ToonValue] = [:]
        var keyOrder: [String] = []
        var keySet = Set<String>()

        while let line = peekLine() {
            if line.isEmpty { consumeLine(); continue }

            let (lineDepth, content) = trimIndentation(line)
            if lineDepth < depth { break }

            guard lineDepth == depth else {
                throw ToonDecodingError.invalidIndentation(
                    line: currentLine + 1,
                    message: "Expected depth \(depth), got \(lineDepth)"
                )
            }
            consumeLine()

            let (key, value) = try parseKeyValuePair(String(content), atDepth: depth)

            if (expandPaths == .safe || expandPaths == .automatic),
               key.contains("."),
               key.split(separator: ".").allSatisfy({ $0.isValidIdentifier }),
               key.split(separator: ".").count > 1
            {
                do {
                    try expandDottedPath(key, value: value, into: &values, keyOrder: &keyOrder)
                    if let rootSegment = key.split(separator: ".", maxSplits: 1).first {
                        keySet.insert(String(rootSegment))
                    }
                } catch {
                    if expandPaths == .automatic {
                        if keySet.insert(key).inserted { keyOrder.append(key) }
                        values[key] = value
                    } else {
                        throw error
                    }
                }
            } else {
                if keySet.insert(key).inserted { keyOrder.append(key) }
                values[key] = value
            }

            if keyOrder.count > limits.maxObjectKeys {
                throw ToonDecodingError.objectKeyLimitExceeded(
                    count: keyOrder.count,
                    limit: limits.maxObjectKeys
                )
            }
        }

        return .object(values, keyOrder: keyOrder)
    }

    func parseKeyValuePair(_ content: String, atDepth depth: Int) throws -> (String, ToonValue) {
        if let header = try? parseArrayHeader(content) {
            let array = try parseArrayContent(header: header, atDepth: depth)
            return (header.key ?? "", array)
        }

        guard let colonIndex = findKeyValueSeparator(in: content) else {
            throw ToonDecodingError.invalidFormat(
                "Expected key: value pair at line \(currentLine), got: \(content)"
            )
        }

        let key = try parseKey(String(content[..<colonIndex]))
        let afterColon = content.index(after: colonIndex)
        let valuePart = String(content[afterColon...]).trimmingLeadingSpace()

        if valuePart.isEmpty {
            let nested = try parseNestedValue(atDepth: depth + 1)
            return (key, nested)
        } else {
            return (key, try parsePrimitive(valuePart))
        }
    }

    // MARK: - Key / Value Helpers

    /// Finds the `:` that separates a key from its value, skipping quoted strings,
    /// brackets, and braces so array headers are not mistakenly split.
    func findKeyValueSeparator(in content: String) -> String.Index? {
        var inQuotes = false
        var escaped = false
        var bracketDepth = 0

        var index = content.startIndex
        while index < content.endIndex {
            let character = content[index]
            if escaped {
                escaped = false
                index = content.index(after: index)
                continue
            }
            if character == "\\" { escaped = true; index = content.index(after: index); continue }
            if character == "\"" { inQuotes.toggle(); index = content.index(after: index); continue }
            if !inQuotes {
                if character == "[" { bracketDepth += 1 }
                else if character == "]" { bracketDepth -= 1 }
                else if character == ":", bracketDepth == 0 {
                    return index
                }
            }
            index = content.index(after: index)
        }
        return nil
    }

    func parseKey(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
            return try unescapeString(String(trimmed.dropFirst().dropLast()))
        }
        return trimmed
    }

    func parseNestedValue(atDepth depth: Int) throws -> ToonValue {
        skipEmptyLines()
        guard let line = peekLine() else {
            return .object([:], keyOrder: [])
        }
        let (lineDepth, content) = trimIndentation(line)
        if lineDepth < depth { return .object([:], keyOrder: []) }
        guard lineDepth == depth else {
            throw ToonDecodingError.invalidIndentation(
                line: currentLine + 1,
                message: "Expected depth \(depth), got \(lineDepth)"
            )
        }
        guard !content.hasPrefix("- ") else {
            throw ToonDecodingError.invalidFormat(
                "Unexpected list item at line \(currentLine + 1)"
            )
        }
        return try parseObject(atDepth: depth)
    }

    // MARK: - Primitive Parsing

    /// Parses a raw TOON value string (not a key-value line) into a ``ToonValue``.
    func parsePrimitive(_ raw: String) throws -> ToonValue {
        try ToonPrimitiveParser.parsePrimitive(raw)
    }

    /// Splits a delimited string (e.g., `a,b,c`) into individual ``ToonValue``s,
    /// respecting quoted substrings so that a delimiter inside quotes is not treated
    /// as a separator.
    func parseDelimitedValues(_ content: String, delimiter: String) throws -> [ToonValue] {
        guard let delimiterByte = delimiter.utf8.first,
              delimiter.utf8.count == 1
        else {
            throw ToonDecodingError.invalidFormat("Delimiter cannot be empty")
        }

        if let fastResult = try content.utf8.withContiguousStorageIfAvailable({ bytes -> [ToonValue] in
            var result: [ToonValue] = []
            result.reserveCapacity(1 + bytes.reduce(into: 0) { count, byte in
                if byte == delimiterByte { count += 1 }
            })

            var start = bytes.startIndex
            var index = bytes.startIndex
            var inQuotes = false
            var escaped = false

            while index < bytes.endIndex {
                let byte = bytes[index]
                if escaped {
                    escaped = false
                    index = bytes.index(after: index)
                    continue
                }

                if byte == 92 {
                    escaped = true
                    index = bytes.index(after: index)
                    continue
                }

                if byte == 34 {
                    inQuotes.toggle()
                    index = bytes.index(after: index)
                    continue
                }

                if !inQuotes, byte == delimiterByte {
                    let tokenBytes = UnsafeBufferPointer(rebasing: bytes[start..<index])
                    result.append(try ToonPrimitiveParser.parsePrimitive(utf8: tokenBytes))
                    start = bytes.index(after: index)
                }

                index = bytes.index(after: index)
            }

            let tailBytes = UnsafeBufferPointer(rebasing: bytes[start..<bytes.endIndex])
            if !tailBytes.isEmpty || !result.isEmpty {
                result.append(try ToonPrimitiveParser.parsePrimitive(utf8: tailBytes))
            }

            return result
        }) {
            return fastResult
        }

        var result: [ToonValue] = []
        var current = ""
        var inQuotes = false
        var escaped = false
        guard let delimiterCharacter = delimiter.first else {
            throw ToonDecodingError.invalidFormat("Delimiter cannot be empty")
        }

        for char in content {
            if escaped {
                current.append(char)
                escaped = false
                continue
            }
            if char == "\\" { escaped = true; current.append(char); continue }
            if char == "\"" { inQuotes.toggle(); current.append(char); continue }
            if !inQuotes, char == delimiterCharacter {
                result.append(try ToonPrimitiveParser.parsePrimitive(current))
                current = ""
                continue
            }
            current.append(char)
        }

        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty || !result.isEmpty {
            result.append(try ToonPrimitiveParser.parsePrimitive(tail))
        }
        return result
    }

    // MARK: - String Unescaping

    /// Replaces TOON escape sequences with their literal characters.
    ///
    /// - Throws: ``ToonDecodingError/invalidEscapeSequence(_:)`` for unrecognised sequences.
    func unescapeString(_ str: String) throws -> String {
        try ToonPrimitiveParser.unescapeString(str)
    }

    // MARK: - Utility

    /// Returns `true` when a content string represents a key-value line
    /// (contains a `:` that is not inside quotes or brackets).
    private func isKeyValuePair(_ content: String) -> Bool {
        findKeyValueSeparator(in: content) != nil
    }
}
