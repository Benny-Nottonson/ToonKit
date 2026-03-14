import Foundation
import Testing

@testable import Toon

// MARK: - Encoder Tests

@Suite("ToonEncoder")
struct EncoderTests {

    let encoder = ToonEncoder()

    // MARK: - Strings

    @Test("Safe strings are not quoted")
    func safeStrings() throws {
        #expect(toon("hello") == "hello")
        #expect(toon("Ada_99") == "Ada_99")
        #expect(toon("café") == "café")
        #expect(toon("你好") == "你好")
        #expect(toon("🚀") == "🚀")
    }

    @Test("Empty string is quoted")
    func emptyString() throws {
        #expect(toon("") == "\"\"")
    }

    @Test("Strings that look like booleans or null are quoted")
    func boolAndNullLookalikes() throws {
        #expect(toon("true")  == "\"true\"")
        #expect(toon("false") == "\"false\"")
        #expect(toon("null")  == "\"null\"")
    }

    @Test("Strings that look like numbers are quoted")
    func numberLookalikes() throws {
        #expect(toon("42")   == "\"42\"")
        #expect(toon("-3.14") == "\"-3.14\"")
        #expect(toon("1e-6") == "\"1e-6\"")
        #expect(toon("05")   == "\"05\"")
    }

    @Test("Strings with structural characters are quoted")
    func structuralCharacters() throws {
        #expect(toon("[3]: x") == "\"[3]: x\"")
        #expect(toon("- item") == "\"- item\"")
        #expect(toon("{key}")  == "\"{key}\"")
        #expect(toon("a:b")   == "\"a:b\"")
    }

    @Test("Control characters are escaped")
    func controlCharacters() throws {
        #expect(toon("line1\nline2")  == "\"line1\\nline2\"")
        #expect(toon("tab\there")     == "\"tab\\there\"")
        #expect(toon("C:\\Users")     == "\"C:\\\\Users\"")
    }

    // MARK: - Numbers

    @Test("Integers are encoded without decoration")
    func integers() throws {
        #expect(toon(42)   == "42")
        #expect(toon(-7)   == "-7")
        #expect(toon(0)    == "0")
        #expect(toon(Int64.max) == "9223372036854775807")
    }

    @Test("Doubles are encoded in canonical decimal form")
    func doubles() throws {
        #expect(toon(3.14)    == "3.14")
        #expect(toon(-3.14)   == "-3.14")
        #expect(toon(1e6)     == "1000000")
        #expect(toon(1e-6)    == "0.000001")
        #expect(toon(0.0)     == "0")
    }

    @Test("Negative zero is normalised by default")
    func negativeZeroNormalize() throws {
        #expect(toon(-0.0) == "0")
    }

    @Test("Negative zero can be preserved")
    func negativeZeroPreserve() throws {
        let customEncoder = ToonEncoder()
        customEncoder.negativeZeroStrategy = .preserve
        #expect(toon(-0.0, using: customEncoder) == "-0")
    }

    @Test("Non-finite floats default to null")
    func nonFiniteNull() throws {
        #expect(toon(Double.nan)       == "null")
        #expect(toon(Double.infinity)  == "null")
        #expect(toon(-Double.infinity) == "null")
    }

    @Test("Non-finite floats can be converted to strings")
    func nonFiniteConvertToString() throws {
        let customEncoder = ToonEncoder()
        customEncoder.nonFiniteFloatStrategy = .convertToString(
            positiveInfinity: "Inf", negativeInfinity: "-Inf", nan: "NaN"
        )
        #expect(toon(Double.nan,       using: customEncoder) == "NaN")
        #expect(toon(Double.infinity,  using: customEncoder) == "Inf")
        #expect(toon(-Double.infinity, using: customEncoder) == "\"-Inf\"")
    }

    @Test("Non-finite floats throw when strategy is .throw")
    func nonFiniteThrow() throws {
        let customEncoder = ToonEncoder()
        customEncoder.nonFiniteFloatStrategy = .throw
        #expect(throws: EncodingError.self) { try customEncoder.encode(Double.nan) }
        #expect(throws: EncodingError.self) { try customEncoder.encode(Double.infinity) }
    }

    // MARK: - Booleans

    @Test("Booleans encode as lowercase literals")
    func booleans() throws {
        #expect(toon(true)  == "true")
        #expect(toon(false) == "false")
    }

    // MARK: - Objects

    @Test("Simple struct")
    func simpleStruct() throws {
        struct Point: Encodable { let x: Int; let y: Int }
        let encodedText = toon(Point(x: 3, y: 7))
        #expect(encodedText.contains("x: 3"))
        #expect(encodedText.contains("y: 7"))
    }

    @Test("Field order is preserved from CodingKeys declaration")
    func fieldOrder() throws {
        struct User: Encodable {
            let id: Int
            let name: String
            let active: Bool
        }
        let lines = toon(User(id: 1, name: "Ada", active: true))
            .components(separatedBy: "\n")
        #expect(lines[0] == "id: 1")
        #expect(lines[1] == "name: Ada")
        #expect(lines[2] == "active: true")
    }

    @Test("Null is encoded for nil optional values")
    func nilOptional() throws {
        struct Wrapper: Encodable { let value: String? }
        #expect(!toon(Wrapper(value: nil)).contains("value:"))
    }

    // MARK: - Arrays

    @Test("Primitive arrays are inline with declared length")
    func primitiveArray() throws {
        struct Tags: Encodable { let tags: [String] }
        let encodedText = toon(Tags(tags: ["a", "b", "c"]))
        #expect(encodedText.contains("tags[3]: a,b,c"))
    }

    @Test("Tabular arrays use compact header and rows")
    func tabularArray() throws {
        struct Item: Encodable { let sku: String; let qty: Int }
        struct Bag: Encodable { let items: [Item] }
        let encodedText = toon(Bag(items: [Item(sku: "A1", qty: 2), Item(sku: "B2", qty: 1)]))
        #expect(encodedText.contains("items[2]{sku,qty}:"))
        #expect(encodedText.contains("A1,2"))
        #expect(encodedText.contains("B2,1"))
    }

    @Test("Alternative delimiters are reflected in the header")
    func tabDelimiter() throws {
        let customEncoder = ToonEncoder()
        customEncoder.delimiter = .tab
        struct Pair: Encodable { let leftValue: Int; let rightValue: Int }
        struct Container: Encodable { let pairs: [Pair] }
        let encodedText = toon(
            Container(pairs: [Pair(leftValue: 1, rightValue: 2)]),
            using: customEncoder
        )
        #expect(encodedText.contains("[1\t]"))
    }

    @Test("Metal acceleration is disabled by default")
    func metalAccelerationDefault() {
        #expect(encoder.acceleration == .disabled)
    }

    @Test("Metal acceleration preserves quoted string output")
    func metalAccelerationMatchesCPU() throws {
        let repeatedSegment = String(repeating: "alpha,beta:\"line\"\\path\\n", count: 8_192)
        let defaultOutput = toon(repeatedSegment)

        let acceleratedEncoder = ToonEncoder()
        acceleratedEncoder.acceleration = .metalForced(minimumStringByteCount: 1)
        let acceleratedOutput = toon(repeatedSegment, using: acceleratedEncoder)

        #expect(defaultOutput == acceleratedOutput)
    }

    @Test("Metal acceleration preserves batched string array output")
    func metalAccelerationMatchesCPUForStringArrays() throws {
        let repeatedSegment = String(repeating: "alpha,beta:\"line\"\\path\\n", count: 1_024)
        let repeatedArray = Array(repeating: repeatedSegment, count: 64)
        let defaultOutput = toon(repeatedArray)

        let acceleratedEncoder = ToonEncoder()
        acceleratedEncoder.acceleration = .metalForced(minimumStringByteCount: 1)
        let acceleratedOutput = toon(repeatedArray, using: acceleratedEncoder)

        #expect(defaultOutput == acceleratedOutput)
    }

    // MARK: - Key Folding

    @Test("Key folding collapses single-key chains")
    func keyFolding() throws {
        let customEncoder = ToonEncoder()
        customEncoder.keyFolding = .safe

        struct Inner: Encodable { let count: Int }
        struct Middle: Encodable { let branch: Inner }
        struct Root: Encodable { let account: Middle }

        let encodedText = toon(
            Root(account: Middle(branch: Inner(count: 42))),
            using: customEncoder
        )
        #expect(encodedText == "account.branch.count: 42")
    }

    // MARK: - Foundation Types

    @Test("URL is encoded as its absolute string")
    func urlEncoding() throws {
        let url = URL(string: "https://example.com/path")!
        #expect(toon(url) == "https://example.com/path")
    }

    @Test("Data is encoded as Base64")
    func dataEncoding() throws {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        #expect(toon(data) == "3q2+7w==")
    }

    // MARK: - Helpers

    /// Encodes a value using the shared encoder, returning the UTF-8 string.
    private func toon<T: Encodable>(_ value: T, using encoderOverride: ToonEncoder? = nil) -> String {
        let activeEncoder = encoderOverride ?? encoder
        let data = (try? activeEncoder.encode(value)) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
