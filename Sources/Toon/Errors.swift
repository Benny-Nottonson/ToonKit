// MARK: - ToonDecodingError

/// Errors thrown during TOON decoding.
///
/// These errors cover both syntactic issues (malformed TOON text) and
/// semantic issues (type mismatches, missing keys, limit violations).
public enum ToonDecodingError: Error, Equatable {

    // MARK: Parse Errors

    /// The input could not be interpreted as valid TOON.
    case invalidFormat(String)

    /// A line's indentation depth was unexpected.
    case invalidIndentation(line: Int, message: String)

    /// A quoted string contained an unrecognised escape sequence.
    case invalidEscapeSequence(String)

    // MARK: Structural Errors

    /// An array had fewer or more elements than declared in its header.
    ///
    /// For example, `tags[3]: a,b` has `expected` = 3 but `actual` = 2.
    case countMismatch(expected: Int, actual: Int, line: Int)

    /// A tabular row had a different number of fields than the column header.
    case fieldCountMismatch(expected: Int, actual: Int, line: Int)

    /// A blank line appeared inside a block where blank lines are not permitted
    /// (inside a fixed-count array body).
    case unexpectedBlankLine(line: Int)

    /// An array header line was syntactically invalid.
    case invalidHeader(String)

    // MARK: Decoding Errors

    /// The TOON value at a key was a different type than the one requested.
    ///
    /// For example, decoding an `Int` from a `bool` value.
    case typeMismatch(expected: String, actual: String)

    /// A required key was absent from the object being decoded.
    case keyNotFound(String)

    /// A value was present but could not be converted to the target type.
    ///
    /// For example, an integer that is outside the range of `Int8`.
    case dataCorrupted(String)

    // MARK: Path Expansion Errors

    /// A dotted key could not be expanded because it collided with an existing key.
    ///
    /// Only thrown when ``ToonDecoder/PathExpansion/safe`` is selected.
    /// In ``ToonDecoder/PathExpansion/automatic`` mode, the key is preserved as-is
    /// instead of raising an error.
    case pathCollision(path: String, line: Int)

    // MARK: Limit Errors

    /// The input data exceeded the ``ToonDecoder/Limits/maxInputSize`` limit.
    case inputTooLarge(size: Int, limit: Int)

    /// The TOON structure exceeds the ``ToonDecoder/Limits/maxDepth`` nesting limit.
    case depthLimitExceeded(depth: Int, limit: Int)

    /// The object has more keys than ``ToonDecoder/Limits/maxObjectKeys`` permits.
    case objectKeyLimitExceeded(count: Int, limit: Int)

    /// The array length exceeds the ``ToonDecoder/Limits/maxArrayLength`` limit.
    case arrayLengthLimitExceeded(length: Int, limit: Int)
}
