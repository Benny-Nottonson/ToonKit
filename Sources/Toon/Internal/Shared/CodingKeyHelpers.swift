// MARK: - CodingKey Helpers

/// A `CodingKey` backed by a plain integer, used for array element positions.
///
/// Swift's unkeyed decoding containers report integer indexes through the coding path,
/// which is useful for detailed error messages that include the position of a bad value.
struct IndexedCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(_ index: Int) {
        intValue = index
        stringValue = String(index)
    }

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init(intValue: Int) {
        self.intValue = intValue
        stringValue = String(intValue)
    }
}

// MARK: - CodingUserInfoKey

extension CodingUserInfoKey {
    /// Passes the ``ToonEncoder/Limits/maxDepth`` value through Swift's `userInfo`
    /// dictionary to the inner encoding containers.
    static let toonMaxDepth = CodingUserInfoKey(rawValue: "toon.maxDepth")!
}
