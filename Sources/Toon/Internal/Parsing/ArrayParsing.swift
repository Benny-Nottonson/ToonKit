// MARK: - Array Header

/// Describes a parsed TOON array header such as `items[3]{sku,name}:`.
struct ArrayHeader {
    /// The key before the `[`, or `nil` for root-level / keyed-on-parent arrays.
    let key: String?
    /// The declared element count.
    let count: Int
    /// The separator character (`","`, `"|"`, or `"\t"`).
    let delimiter: String
    /// Column names for tabular format, or `nil` for plain list / inline format.
    let fields: [String]?
}

// MARK: - Array Parsing Extension

extension ToonParser {

    // MARK: Header Parsing

    /// Parses an array header string like `key[3]{a,b,c}:` or `[2|]:` into
    /// an ``ArrayHeader``.
    ///
    /// - Throws: ``ToonDecodingError/invalidHeader(_:)`` if the syntax is wrong.
    func parseArrayHeader(_ content: String) throws -> ArrayHeader {
        var rest = content[...]

        var key: String? = nil
        if rest.first == "\"" {
            guard let closeQuote = findClosingQuote(in: rest) else {
                throw ToonDecodingError.invalidHeader("Unterminated quoted key: \(content)")
            }
            let inner = String(rest[rest.index(after: rest.startIndex) ..< closeQuote])
            key = try unescapeString(inner)
            rest = rest[rest.index(after: closeQuote)...]
        } else if let bracket = rest.firstIndex(of: "[") {
            let before = rest[..<bracket]
            if !before.isEmpty { key = String(before) }
            rest = rest[bracket...]
        }

        guard rest.first == "[" else {
            throw ToonDecodingError.invalidHeader("Expected '[': \(content)")
        }
        rest = rest.dropFirst()

        if rest.first == "#" {
            throw ToonDecodingError.invalidHeader(
                "Length marker '#' is not valid in TOON v3: \(content)"
            )
        }

        var countStr = ""
        while let character = rest.first, character.isNumber {
            countStr.append(character)
            rest = rest.dropFirst()
        }
        guard let count = Int(countStr) else {
            throw ToonDecodingError.invalidHeader("Non-numeric count: \(content)")
        }

        var delimiter = ","
        if let first = rest.first, first == "|" || first == "\t" {
            delimiter = String(first)
            rest = rest.dropFirst()
        }

        guard rest.first == "]" else {
            throw ToonDecodingError.invalidHeader("Expected ']': \(content)")
        }
        rest = rest.dropFirst()

        var fields: [String]? = nil
        if rest.first == "{" {
            rest = rest.dropFirst()
            guard let closeBrace = rest.firstIndex(of: "}") else {
                throw ToonDecodingError.invalidHeader("Unterminated fields list: \(content)")
            }
            fields = try parseFieldsList(String(rest[..<closeBrace]), delimiter: delimiter)
            rest = rest[rest.index(after: closeBrace)...]
        }

        guard rest.first == ":" else {
            throw ToonDecodingError.invalidHeader("Expected ':' at end of header: \(content)")
        }

        return ArrayHeader(key: key, count: count, delimiter: delimiter, fields: fields)
    }

    // MARK: Array Content

    /// Parses the content of an array (inline values or multi-line list/tabular rows)
    /// after the header has already been consumed.
    func parseArrayContent(header: ArrayHeader, atDepth depth: Int) throws -> ToonValue {
        guard header.count <= limits.maxArrayLength else {
            throw ToonDecodingError.arrayLengthLimitExceeded(
                length: header.count, limit: limits.maxArrayLength
            )
        }

        let headerLine = lines[currentLine - 1]
        let (_, headerContent) = trimIndentation(headerLine)
        if let colon = headerContent.lastIndex(of: ":") {
            let inlineString = String(headerContent[headerContent.index(after: colon)...])
                .trimmingLeadingSpace()
            if !inlineString.isEmpty {
                let items = try parseDelimitedValues(inlineString, delimiter: header.delimiter)
                guard items.count == header.count else {
                    throw ToonDecodingError.countMismatch(
                        expected: header.count, actual: items.count, line: currentLine
                    )
                }
                return .array(items)
            }
        }

        if header.count == 0 { return .array([]) }

        let items: [ToonValue]
        if let fields = header.fields {
            items = try parseTabularRows(
                count: header.count,
                fields: fields,
                delimiter: header.delimiter,
                atDepth: depth
            )
        } else {
            items = try parseListItems(
                count: header.count,
                delimiter: header.delimiter,
                atDepth: depth
            )
        }

        guard items.count == header.count else {
            throw ToonDecodingError.countMismatch(
                expected: header.count, actual: items.count, line: currentLine
            )
        }
        return .array(items)
    }

    /// Convenience: consumes the current line as an array header and then parses
    /// the array body.
    func parseArrayAtCurrentLine(depth: Int) throws -> ToonValue {
        guard let line = consumeLine() else {
            throw ToonDecodingError.invalidFormat("Expected array header line")
        }
        let (_, content) = trimIndentation(line)
        let header = try parseArrayHeader(String(content))
        return try parseArrayContent(header: header, atDepth: depth)
    }

    // MARK: Tabular Rows

    private func parseTabularRows(
        count: Int,
        fields: [String],
        delimiter: String,
        atDepth depth: Int
    ) throws -> [ToonValue] {
        var rows: [ToonValue] = []
        let expectedDepth = depth + 1

        for _ in 0 ..< count {
            skipEmptyLines()
            guard let line = consumeLine() else { break }
            guard !line.isEmpty else {
                throw ToonDecodingError.unexpectedBlankLine(line: currentLine)
            }
            let (lineDepth, content) = trimIndentation(line)
            guard lineDepth == expectedDepth else {
                throw ToonDecodingError.invalidIndentation(
                    line: currentLine,
                    message: "Expected depth \(expectedDepth), got \(lineDepth)"
                )
            }
            let cellValues = try parseDelimitedValues(String(content), delimiter: delimiter)
            guard cellValues.count == fields.count else {
                throw ToonDecodingError.fieldCountMismatch(
                    expected: fields.count, actual: cellValues.count, line: currentLine
                )
            }
            var objectValues: [String: ToonValue] = [:]
            for (field, cellValue) in zip(fields, cellValues) { objectValues[field] = cellValue }
            rows.append(.object(objectValues, keyOrder: fields))
        }
        return rows
    }

    // MARK: List Items

    private func parseListItems(
        count: Int,
        delimiter: String,
        atDepth depth: Int
    ) throws -> [ToonValue] {
        var items: [ToonValue] = []
        let expectedDepth = depth + 1

        for _ in 0 ..< count {
            skipEmptyLines()
            guard let line = peekLine() else { break }
            guard !line.isEmpty else {
                throw ToonDecodingError.unexpectedBlankLine(line: currentLine + 1)
            }
            let (lineDepth, content) = trimIndentation(line)
            guard lineDepth == expectedDepth else {
                throw ToonDecodingError.invalidIndentation(
                    line: currentLine + 1,
                    message: "Expected depth \(expectedDepth), got \(lineDepth)"
                )
            }
            consumeLine()
            guard content.hasPrefix("- ") else {
                throw ToonDecodingError.invalidFormat(
                    "Expected list item '- ' at line \(currentLine)"
                )
            }
            let itemContent = String(content.dropFirst(2))
            items.append(try parseListItemContent(itemContent, atDepth: expectedDepth))
        }
        return items
    }

    private func parseListItemContent(_ content: String, atDepth depth: Int) throws -> ToonValue {
        if content.hasPrefix("["), let header = try? parseArrayHeader(content) {
            return try parseArrayContent(header: header, atDepth: depth)
        }

        if let colonIndex = findKeyValueSeparator(in: content) {
            let key = try parseKey(String(content[..<colonIndex]))
            let afterColon = content.index(after: colonIndex)
            let valuePart = String(content[afterColon...]).trimmingLeadingSpace()

            var objectValues: [String: ToonValue] = [:]
            var keyOrder: [String] = [key]

            if valuePart.isEmpty {
                objectValues[key] = try parseNestedValue(atDepth: depth + 1)
            } else if let header = try? parseArrayHeader(content) {
                let array = try parseArrayContent(header: header, atDepth: depth)
                let arrayKey = header.key ?? key
                keyOrder = [arrayKey]
                objectValues[arrayKey] = array
            } else {
                objectValues[key] = try parsePrimitive(valuePart)
            }

            while let next = peekLine() {
                if next.isEmpty { consumeLine(); continue }
                let (nextDepth, nextContent) = trimIndentation(next)
                if nextDepth != depth + 1 { break }
                if nextContent.hasPrefix("- ") { break }
                consumeLine()
                let (nextKey, nextValue) = try parseKeyValuePair(String(nextContent), atDepth: depth + 1)
                if !keyOrder.contains(nextKey) { keyOrder.append(nextKey) }
                objectValues[nextKey] = nextValue
            }

            return .object(objectValues, keyOrder: keyOrder)
        }

        return try parsePrimitive(content)
    }

    // MARK: Field List

    private func parseFieldsList(_ raw: String, delimiter: String) throws -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false
        guard let delimiterCharacter = delimiter.first else {
            throw ToonDecodingError.invalidHeader("Delimiter cannot be empty")
        }

        for character in raw {
            if escaped { current.append(character); escaped = false; continue }
            if character == "\\" { escaped = true; current.append(character); continue }
            if character == "\"" { inQuotes.toggle(); current.append(character); continue }
            if !inQuotes, character == delimiterCharacter {
                fields.append(try parseFieldName(current))
                current = ""
                continue
            }
            current.append(character)
        }
        if !current.isEmpty { fields.append(try parseFieldName(current)) }
        return fields
    }

    private func parseFieldName(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\"") {
            return try unescapeString(String(trimmed.dropFirst().dropLast()))
        }
        return trimmed
    }

    // MARK: Quoted-Key Helpers

    private func findClosingQuote(in substring: Substring) -> String.Index? {
        var escaped = false
        var index = substring.index(after: substring.startIndex)
        while index < substring.endIndex {
            let character = substring[index]
            if escaped { escaped = false }
            else if character == "\\" { escaped = true }
            else if character == "\"" { return index }
            index = substring.index(after: index)
        }
        return nil
    }
}
