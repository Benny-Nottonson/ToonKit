// MARK: - Array Serialization

extension ToonSerializer {

    // MARK: - Entry

    /// Serializes an array value, choosing the most compact representation:
    ///
    /// 1. **Inline primitive:** `tags[3]: a,b,c`
    /// 2. **Tabular:** `items[2]{sku,name}:` followed by rows
    /// 3. **List of arrays:** `[2]:` followed by `- [3]: …` lines
    /// 4. **Mixed list:** `key[N]:` followed by `- …` lines
    func encodeArray(key: String?, array: [ToonValue], lines: inout [String], depth: Int) {
        if array.isEmpty {
            write(formatHeader(count: array.count, key: key), depth: depth, to: &lines)
            return
        }

        if array.allSatisfy({ $0.isPrimitive }) {
            encodeInlineArray(key: key, array: array, lines: &lines, depth: depth)
            return
        }

        if array.allSatisfy({ $0.isArray }) {
            let allPrimitiveChildren = array.allSatisfy { nestedArray in
                (nestedArray.arrayValue ?? []).allSatisfy { $0.isPrimitive }
            }
            if allPrimitiveChildren {
                encodeArraysAsList(key: key, array: array, lines: &lines, depth: depth)
                return
            }
        }

        if array.allSatisfy({ $0.isObject }),
           let header = detectTabularHeader(array)
        {
            encodeTabular(key: key, rows: array, header: header, lines: &lines, depth: depth)
            return
        }

        encodeMixedList(key: key, items: array, lines: &lines, depth: depth)
    }

    // MARK: - Inline Primitive Array

    private func encodeInlineArray(
        key: String?,
        array: [ToonValue],
        lines: inout [String],
        depth: Int
    ) {
        let header = formatHeader(count: array.count, key: key)
        let values = joinPrimitives(array)
        write("\(header) \(values)", depth: depth, to: &lines)
    }

    // MARK: - Array of Arrays (as List)

    private func encodeArraysAsList(
        key: String?,
        array: [ToonValue],
        lines: inout [String],
        depth: Int
    ) {
        write(formatHeader(count: array.count, key: key), depth: depth, to: &lines)
        for item in array {
            let inlineValues = encodePrimitiveList(
                item.arrayValue ?? [],
                delimiter: config.delimiter
            ).joined(separator: config.delimiter)
            let nestedHeader = formatHeader(count: item.arrayValue?.count ?? 0, key: nil)
            write("- \(nestedHeader) \(inlineValues)", depth: depth + 1, to: &lines)
        }
    }

    // MARK: - Tabular Array

    private func encodeTabular(
        key: String?,
        rows: [ToonValue],
        header: [String],
        lines: inout [String],
        depth: Int
    ) {
        write(
            formatHeader(count: rows.count, key: key, fields: header),
            depth: depth,
            to: &lines
        )
        appendTabularRows(rows: rows, header: header, lines: &lines, depth: depth + 1)
    }

    // MARK: - Mixed List

    func encodeMixedList(
        key: String?,
        items: [ToonValue],
        lines: inout [String],
        depth: Int
    ) {
        write(formatHeader(count: items.count, key: key), depth: depth, to: &lines)
        for item in items {
            switch item {
            case .null, .bool, .int, .double, .string, .date, .url, .data:
                if let stringValue = encodePrimitive(item, delimiter: config.delimiter) {
                    write("- \(stringValue)", depth: depth + 1, to: &lines)
                }
            case .array(let inner):
                if inner.allSatisfy({ $0.isPrimitive }) {
                    let header = formatHeader(count: inner.count, key: nil)
                    let values = joinPrimitives(inner)
                    write("- \(header) \(values)", depth: depth + 1, to: &lines)
                }
            case .object(let values, let keyOrder):
                encodeObjectAsListItem(
                    values: values, keyOrder: keyOrder, lines: &lines, depth: depth + 1
                )
            }
        }
    }

    // MARK: - Object as List Item

    /// Writes an object as a TOON list item, starting with `- key: value` for the
    /// first field and then indenting the remaining fields one extra level.
    func encodeObjectAsListItem(
        values: [String: ToonValue],
        keyOrder: [String],
        lines: inout [String],
        depth: Int
    ) {
        guard !keyOrder.isEmpty else {
            write("-", depth: depth, to: &lines)
            return
        }

        let firstKey = keyOrder[0]
        let firstValue = values[firstKey]!
        let encodedFirstKey = encodeKey(firstKey)

        switch firstValue {
        case .null, .bool, .int, .double, .string, .date, .url, .data:
            if let stringValue = encodePrimitive(firstValue, delimiter: config.delimiter) {
                write("- \(encodedFirstKey): \(stringValue)", depth: depth, to: &lines)
            }
        case .array(let array):
            if array.allSatisfy({ $0.isPrimitive }) {
                let header = formatHeader(count: array.count, key: firstKey)
                let values = joinPrimitives(array)
                write("- \(header) \(values)", depth: depth, to: &lines)
            } else if array.allSatisfy({ $0.isObject }),
                      let header = detectTabularHeader(array)
            {
                let tableHeader = formatHeader(count: array.count, key: firstKey, fields: header)
                write("- \(tableHeader)", depth: depth, to: &lines)
                appendTabularRows(rows: array, header: header, lines: &lines, depth: depth + 1)
            } else {
                write(
                    "- \(encodedFirstKey)[\(array.count)]:",
                    depth: depth, to: &lines
                )
                for item in array {
                    if case let .object(values, keyOrder) = item {
                        encodeObjectAsListItem(values: values, keyOrder: keyOrder, lines: &lines, depth: depth + 1)
                    }
                }
            }
        case .object(let nested, let nestedOrder):
            if nestedOrder.isEmpty {
                write("- \(encodedFirstKey):", depth: depth, to: &lines)
            } else {
                write("- \(encodedFirstKey):", depth: depth, to: &lines)
                encodeObject(nested, keyOrder: nestedOrder, lines: &lines, depth: depth + 2)
            }
        }

        for index in 1 ..< keyOrder.count {
            let key = keyOrder[index]
            guard let value = values[key] else { continue }
            encodeKeyValuePair(
                key: key, value: value, lines: &lines, depth: depth + 1, siblingKeys: keyOrder
            )
        }
    }

    // MARK: - Tabular Detection

    /// Returns the column names if `rows` can be serialized as a tabular array
    /// (all objects, same keys, all primitive values), or `nil` otherwise.
    func detectTabularHeader(_ rows: [ToonValue]) -> [String]? {
        guard let (_, keyOrder) = rows.first?.objectValue, !keyOrder.isEmpty else { return nil }
        for row in rows {
            guard let (values, rowKeyOrder) = row.objectValue,
                  rowKeyOrder.count == keyOrder.count
            else { return nil }
            for key in keyOrder {
                guard let value = values[key], value.isPrimitive else { return nil }
            }
        }
        return keyOrder
    }

    // MARK: - Formatting Helpers

    /// Builds the TOON array header string, e.g. `items[3]{sku,name}:`.
    func formatHeader(
        count: Int,
        key: String? = nil,
        fields: [String]? = nil
    ) -> String {
        var header = key.map { encodeKey($0) } ?? ""
        let delimSuffix = config.delimiter != "," ? config.delimiter : ""
        header += "[\(count)\(delimSuffix)]"
        if let fields = fields {
            header += "{\(fields.map { encodeKey($0) }.joined(separator: config.delimiter))}"
        }
        header += ":"
        return header
    }

    /// Joins an array of primitive values using the active delimiter.
    func joinPrimitives(_ values: [ToonValue]) -> String {
        encodePrimitiveList(values, delimiter: config.delimiter)
            .joined(separator: config.delimiter)
    }

    private func appendTabularRows(
        rows: [ToonValue],
        header: [String],
        lines: inout [String],
        depth: Int
    ) {
        let preEncodedStringColumns = preEncodeTabularStringColumns(rows: rows, header: header)

        for (rowIndex, row) in rows.enumerated() {
            guard let (values, _) = row.objectValue else { continue }

            var encodedCells: [String] = []
            encodedCells.reserveCapacity(header.count)

            for key in header {
                guard let value = values[key] else { continue }

                if case .string = value,
                   let encodedColumn = preEncodedStringColumns[key]
                {
                    encodedCells.append(encodedColumn[rowIndex])
                } else {
                    encodedCells.append(encodePrimitive(value, delimiter: config.delimiter) ?? "")
                }
            }

            write(encodedCells.joined(separator: config.delimiter), depth: depth, to: &lines)
        }
    }

    private func preEncodeTabularStringColumns(
        rows: [ToonValue],
        header: [String]
    ) -> [String: [String]] {
        var encodedColumns: [String: [String]] = [:]
        encodedColumns.reserveCapacity(header.count)

        for key in header {
            var stringColumn: [String] = []
            stringColumn.reserveCapacity(rows.count)

            var canBatchEncodeColumn = true
            for row in rows {
                guard let (values, _) = row.objectValue,
                      let value = values[key],
                      case .string(let stringValue) = value
                else {
                    canBatchEncodeColumn = false
                    break
                }
                stringColumn.append(stringValue)
            }

            guard canBatchEncodeColumn,
                  let encodedColumn = ToonStringLiteralEncoder.encodeBatch(
                    stringColumn,
                    delimiter: config.delimiter,
                    acceleration: config.acceleration
                  )
            else {
                continue
            }

            encodedColumns[key] = encodedColumn
        }

        return encodedColumns
    }
}
