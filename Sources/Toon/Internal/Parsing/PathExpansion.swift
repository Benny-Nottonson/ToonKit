// MARK: - Path Expansion

extension ToonParser {

    /// Inserts a value into the `values`/`keyOrder` dictionaries by expanding
    /// a dotted key like `user.profile.name` into nested objects.
    ///
    /// - Throws: ``ToonDecodingError/pathCollision(path:line:)`` when expansion would
    ///   overwrite a non-object with an object (or vice versa).
    func expandDottedPath(
        _ key: String,
        value: ToonValue,
        into values: inout [String: ToonValue],
        keyOrder: inout [String]
    ) throws {
        let segments = key.split(separator: ".").map(String.init)
        guard segments.count > 1 else {
            if !keyOrder.contains(key) { keyOrder.append(key) }
            values[key] = value
            return
        }

        let root = segments[0]
        if !keyOrder.contains(root) { keyOrder.append(root) }
        values[root] = try mergePath(
            into: values[root],
            segments: Array(segments.dropFirst()),
            value: value
        )
    }

    // MARK: - Private

    /// Recursively merges `value` into the object at `existing`, following the
    /// given path `segments`.
    private func mergePath(
        into existing: ToonValue?,
        segments: [String],
        value: ToonValue
    ) throws -> ToonValue {
        guard let head = segments.first else { return value }
        let tail = Array(segments.dropFirst())

        var objectValues: [String: ToonValue]
        var objectKeyOrder: [String]

        if let existing = existing {
            guard case let .object(existingValues, existingKeyOrder) = existing else {
                throw ToonDecodingError.pathCollision(path: head, line: currentLine)
            }
            objectValues = existingValues
            objectKeyOrder = existingKeyOrder
        } else {
            objectValues = [:]
            objectKeyOrder = []
        }

        objectValues[head] = try mergePath(into: objectValues[head], segments: tail, value: value)
        if !objectKeyOrder.contains(head) { objectKeyOrder.append(head) }
        return .object(objectValues, keyOrder: objectKeyOrder)
    }
}
