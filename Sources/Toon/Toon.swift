/// The ``Toon`` module provides ``ToonEncoder`` and ``ToonDecoder`` for serializing
/// and deserializing Swift `Codable` values to and from the TOON format.
///
/// # What is TOON?
///
/// **Token-Oriented Object Notation** is a compact, human-readable serialization format
/// designed to minimize LLM token usage. It achieves 30–60% token reduction compared to
/// JSON by combining:
///
/// - YAML-style indentation for nested structure
/// - CSV-style *tabular rows* for uniform arrays of objects  
/// - Declared length prefixes on arrays (`tags[3]: a,b,c`) so parsers can validate
///
/// ## Example
///
/// ```swift
/// import Toon
///
/// struct User: Codable, Equatable {
///     let id: Int
///     let name: String
///     let tags: [String]
///     let active: Bool
/// }
///
/// let user = User(id: 1, name: "Ada", tags: ["reading", "coding"], active: true)
///
/// // Encode to TOON
/// let encoder = ToonEncoder()
/// let data = try encoder.encode(user)
/// // id: 1
/// // name: Ada
/// // tags[2]: reading,coding
/// // active: true
///
/// // Decode from TOON
/// let decoder = ToonDecoder()
/// let decoded = try decoder.decode(User.self, from: data)
/// assert(decoded == user)
/// ```
///
/// ## Specification
///
/// This library implements **TOON specification version 3.0** (2025-11-24).
/// For the full specification, see <https://github.com/toon-format/spec>
public enum Toon {
    /// The TOON specification version implemented by this library.
    public static let specVersion = "3.0"
}
