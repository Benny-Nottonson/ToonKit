// MARK: - ToonSerializer

/// Converts a ``ToonValue`` tree into a TOON-format string.
///
/// Create a serializer with the encoder's configuration, then call ``serialize(_:)``
/// once. The serializer is stateless between calls and can be reused.
struct ToonSerializer {

    // MARK: - Config

    /// All encoder settings needed by the serializer, passed as a value type to
    /// make the data flow explicit.
    struct Config {
        /// Spaces per indentation level.
        let indent: Int
        /// The active delimiter character string (`,`, `\t`, or `|`).
        let delimiter: String
        /// Whether to encode `-0.0` as `-0` (`true`) or `0` (`false`).
        let preserveNegativeZero: Bool
        /// Strategy for encoding `nan`, `inf`, and `-inf` values.
        let nonFiniteFloatStrategy: ToonEncoder.NonFiniteFloatStrategy
        /// Whether key folding is enabled.
        let keyFolding: ToonEncoder.KeyFolding
        /// Maximum path segments to fold into a dotted key.
        let flattenDepth: Int
        /// Optional acceleration backend used during string serialization.
        let acceleration: ToonEncoder.Acceleration
    }

    let config: Config

    // MARK: - Init

    init(config: Config) {
        self.config = config
    }

    // MARK: - Public Entry Point

    /// Serializes `value` to a TOON string.
    func serialize(_ value: ToonValue) -> String {
        var lines: [String] = []
        writeValue(value, lines: &lines, depth: 0)
        return lines.joined(separator: "\n")
    }

    // MARK: - Value Dispatch

    func writeValue(_ value: ToonValue, lines: inout [String], depth: Int) {
        switch value {
        case .null, .bool, .int, .double, .string, .date, .url, .data:
            if depth == 0,
               let stringValue = encodePrimitive(value, delimiter: config.delimiter)
            {
                write(stringValue, depth: 0, to: &lines)
            }

        case .array(let array):
            encodeArray(key: nil, array: array, lines: &lines, depth: depth)

        case .object(let values, let keyOrder):
            encodeObject(values, keyOrder: keyOrder, lines: &lines, depth: depth)
        }
    }

    // MARK: - Object Encoding

    func encodeObject(
        _ values: [String: ToonValue],
        keyOrder: [String],
        lines: inout [String],
        depth: Int,
        allowFolding: Bool = true
    ) {
        for key in keyOrder {
            guard let value = values[key] else { continue }
            encodeKeyValuePair(
                key: key,
                value: value,
                lines: &lines,
                depth: depth,
                siblingKeys: keyOrder,
                allowFolding: allowFolding
            )
        }
    }

    func encodeKeyValuePair(
        key: String,
        value: ToonValue,
        lines: inout [String],
        depth: Int,
        siblingKeys: [String] = [],
        allowFolding: Bool = true
    ) {
        if allowFolding,
           let (path, foldedValue, hitLimit) = tryFoldKey(key: key, value: value, siblings: siblingKeys)
        {
            let encodedPath = encodeKey(path)
            switch foldedValue {
            case .null, .bool, .int, .double, .string, .date, .url, .data:
                if let stringValue = encodePrimitive(foldedValue, delimiter: config.delimiter) {
                    write("\(encodedPath): \(stringValue)", depth: depth, to: &lines)
                }
            case .array(let array):
                encodeArray(key: path, array: array, lines: &lines, depth: depth)
            case .object(let values, let keyOrder):
                write("\(encodedPath):", depth: depth, to: &lines)
                if !keyOrder.isEmpty {
                    encodeObject(values, keyOrder: keyOrder, lines: &lines, depth: depth + 1,
                                 allowFolding: !hitLimit)
                }
            }
            return
        }

        let encodedKey = encodeKey(key)
        switch value {
        case .null, .bool, .int, .double, .string, .date, .url, .data:
            if let stringValue = encodePrimitive(value, delimiter: config.delimiter) {
                write("\(encodedKey): \(stringValue)", depth: depth, to: &lines)
            }
        case .array(let array):
            encodeArray(key: key, array: array, lines: &lines, depth: depth)
        case .object(let values, let keyOrder):
            write("\(encodedKey):", depth: depth, to: &lines)
            if !keyOrder.isEmpty {
                encodeObject(values, keyOrder: keyOrder, lines: &lines, depth: depth + 1)
            }
        }
    }

    // MARK: - Key Folding

    /// Attempts to collapse a chain of single-key objects into a dotted path.
    ///
    /// Returns `(foldedPath, terminalValue, hitDepthLimit)` when folding is possible,
    /// or `nil` when folding is disabled or not safe.
    private func tryFoldKey(
        key: String,
        value: ToonValue,
        siblings: [String]
    ) -> (path: String, value: ToonValue, hitLimit: Bool)? {
        guard case .safe = config.keyFolding, config.flattenDepth >= 2 else { return nil }

        var path = [key]
        var current = value
        var hitLimit = false

        while case .object(let values, let keyOrder) = current,
              keyOrder.count == 1,
              let nextKey = keyOrder.first,
              let nextValue = values[nextKey],
              nextKey.isValidIdentifierSegment
        {
            guard path.count < config.flattenDepth else { hitLimit = true; break }
            path.append(nextKey)
            current = nextValue
        }

        guard path.count > 1 else { return nil }
        guard path.allSatisfy({ $0.isValidIdentifierSegment }) else { return nil }

        let dotted = path.joined(separator: ".")
        guard !siblings.contains(dotted) else { return nil }

        return (dotted, current, hitLimit)
    }

    // MARK: - Line Writing

    /// Appends a content string to `lines`, prefixed with the appropriate indentation.
    func write(_ content: String, depth: Int, to lines: inout [String]) {
        let indentation = String(repeating: " ", count: depth * config.indent)
        lines.append(indentation + content)
    }
}
