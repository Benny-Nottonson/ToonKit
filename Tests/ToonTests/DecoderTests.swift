import Foundation
import Testing

@testable import Toon

// MARK: - Decoder Tests

@Suite("ToonDecoder")
struct DecoderTests {

    let decoder = ToonDecoder()

    // MARK: - Primitives

    @Test("Unquoted safe strings decode as strings")
    func safeStrings() throws {
        #expect(try toon("hello") == "hello")
        #expect(try toon("Ada_99") == "Ada_99")
    }

    @Test("Empty quoted string decodes as empty string")
    func emptyString() throws {
        #expect(try toon("\"\"") == "")
    }

    @Test("Quoted boolean-lookalike strings remain strings")
    func quotedBoolStrings() throws {
        #expect(try toon("\"true\"")  == "true")
        #expect(try toon("\"false\"") == "false")
        #expect(try toon("\"null\"")  == "null")
    }

    @Test("Escape sequences are unescaped correctly")
    func escapeSequences() throws {
        #expect(try toon("\"line1\\nline2\"") == "line1\nline2")
        #expect(try toon("\"tab\\there\"")   == "tab\there")
        #expect(try toon("\"C:\\\\Users\"")  == "C:\\Users")
        #expect(try toon("\"hello \\\"world\\\"\"") == "hello \"world\"")
    }

    @Test("Unicode strings decode without modification")
    func unicodeStrings() throws {
        #expect(try toon("café") == "café")
        #expect(try toon("你好")  == "你好")
        #expect(try toon("🚀")   == "🚀")
    }

    @Test("Integers decode correctly")
    func integers() throws {
        #expect(try toon("42",  as: Int.self) == 42)
        #expect(try toon("-7",  as: Int.self) == -7)
        #expect(try toon("0",   as: Int.self) == 0)
        #expect(try toon("9223372036854775807", as: Int64.self) == Int64.max)
    }

    @Test("Doubles decode correctly")
    func doubles() throws {
        #expect(try toon("3.14",   as: Double.self) == 3.14)
        #expect(try toon("-3.14",  as: Double.self) == -3.14)
        #expect(try toon("1.5e10", as: Double.self) == 1.5e10)
        #expect(try toon("0.0",    as: Double.self) == 0.0)
    }

    @Test("Booleans decode from literals")
    func booleans() throws {
        #expect(try toon("true",  as: Bool.self) == true)
        #expect(try toon("false", as: Bool.self) == false)
    }

    @Test("null literal decodes to nil optional")
    func nullOptional() throws {
        struct Wrapper: Decodable { let value: String? }
        let wrapper = try decoder.decode(Wrapper.self, from: "value: null".data(using: .utf8)!)
        #expect(wrapper.value == nil)
    }

    // MARK: - Objects

    @Test("Simple object decodes all fields")
    func simpleObject() throws {
        struct Config: Decodable { let host: String; let port: Int }
        let config = try decoder.decode(
            Config.self,
            from: "host: localhost\nport: 8080".data(using: .utf8)!
        )
        #expect(config.host == "localhost")
        #expect(config.port == 8080)
    }

    @Test("Nested objects decode correctly")
    func nestedObjects() throws {
        struct Address: Decodable { let city: String }
        struct Person: Decodable { let name: String; let address: Address }
        let person = try decoder.decode(
            Person.self,
            from: "name: Ada\naddress:\n  city: London".data(using: .utf8)!
        )
        #expect(person.name == "Ada")
        #expect(person.address.city == "London")
    }

    @Test("Missing required key throws keyNotFound")
    func missingKey() throws {
        struct User: Decodable { let id: Int; let name: String }
        #expect(throws: ToonDecodingError.self) {
            _ = try decoder.decode(User.self, from: "id: 1".data(using: .utf8)!)
        }
    }

    // MARK: - Arrays

    @Test("Inline primitive array decodes correctly")
    func inlineArray() throws {
        struct Tags: Decodable { let tags: [String] }
        let tags = try decoder.decode(
            Tags.self,
            from: "tags[3]: a,b,c".data(using: .utf8)!
        )
        #expect(tags.tags == ["a", "b", "c"])
    }

    @Test("Element count mismatch throws countMismatch")
    func countMismatch() throws {
        #expect(throws: ToonDecodingError.self) {
            _ = try decoder.decode(
                [String].self,
                from: "[3]: a,b".data(using: .utf8)!
            )
        }
    }

    @Test("Tabular array decodes into objects")
    func tabularArray() throws {
        struct Item: Decodable, Equatable { let sku: String; let qty: Int }
        struct Bag: Decodable { let items: [Item] }
        let toon = """
            items[2]{sku,qty}:
              A1,2
              B2,1
            """
        let bag = try decoder.decode(Bag.self, from: toon.data(using: .utf8)!)
        #expect(bag.items == [Item(sku: "A1", qty: 2), Item(sku: "B2", qty: 1)])
    }

    @Test("Forced Metal decoding preserves escaped tabular string values")
    func metalTabularDecodeEscapes() throws {
        struct Row: Codable, Equatable {
            let code: String
            let note: String
            let amount: Double
            let active: Bool
        }

        struct Payload: Codable, Equatable {
            let rows: [Row]
        }

        let rows = (0..<192).map { index in
            Row(
                code: "item_\(index)",
                note: "quoted \"value\" \\ path \n line \t tab \(index)",
                amount: Double(index) * 1.25,
                active: index.isMultiple(of: 2)
            )
        }

        let payload = Payload(rows: rows)
        let encoder = ToonEncoder()
        let data = try encoder.encode(payload)

        let acceleratedDecoder = ToonDecoder()
        acceleratedDecoder.acceleration = .metalForced

        let decoded = try acceleratedDecoder.decode(Payload.self, from: data)
        #expect(decoded == payload)
    }

    @Test("Forced Metal decoding falls back cleanly for non-ASCII tabular values")
    func metalTabularDecodeFallbacksForUnicode() throws {
        struct Row: Codable, Equatable {
            let code: String
            let city: String
            let active: Bool
        }

        struct Payload: Codable, Equatable {
            let rows: [Row]
        }

        let rows = (0..<192).map { index in
            Row(
                code: "row_\(index)",
                city: index == 73 ? "Montréal" : "London_\(index)",
                active: !index.isMultiple(of: 3)
            )
        }

        let payload = Payload(rows: rows)
        let encoder = ToonEncoder()
        let data = try encoder.encode(payload)

        let acceleratedDecoder = ToonDecoder()
        acceleratedDecoder.acceleration = .metalForced

        let decoded = try acceleratedDecoder.decode(Payload.self, from: data)
        #expect(decoded == payload)
    }

    @Test("Array of arrays decodes correctly")
    func arrayOfArrays() throws {
        struct Matrix: Decodable { let rows: [[Int]] }
        let toon = "rows[2]:\n  - [3]: 1,2,3\n  - [3]: 4,5,6"
        let matrix = try decoder.decode(Matrix.self, from: toon.data(using: .utf8)!)
        #expect(matrix.rows == [[1, 2, 3], [4, 5, 6]])
    }

    // MARK: - Path Expansion

    @Test("Dotted keys are expanded in .automatic mode")
    func pathExpansionAutomatic() throws {
        struct Profile: Decodable { let name: String }
        struct User: Decodable { let profile: Profile }
        let toon = "profile.name: Ada"
        let user = try decoder.decode(User.self, from: toon.data(using: .utf8)!)
        #expect(user.profile.name == "Ada")
    }

    @Test("Dotted keys are not expanded in .disabled mode")
    func pathExpansionDisabled() throws {
        let customDecoder = ToonDecoder()
        customDecoder.expandPaths = .disabled
        let toon = "a.b: hello"
        let dictionary = try customDecoder.decode([String: String].self, from: toon.data(using: .utf8)!)
        #expect(dictionary["a.b"] == "hello")
    }

    // MARK: - Limits

    @Test("Input size limit throws inputTooLarge")
    func inputSizeLimit() throws {
        let limitedDecoder = ToonDecoder()
        limitedDecoder.limits = ToonDecoder.Limits(
            maxInputSize: 5, maxDepth: 32, maxObjectKeys: 1000, maxArrayLength: 1000
        )
        let bigInput = "x: hello world this is too long"
        #expect(throws: ToonDecodingError.self) {
            _ = try limitedDecoder.decode([String: String].self, from: bigInput.data(using: .utf8)!)
        }
    }

    // MARK: - Foundation Types

    @Test("Date decodes from ISO 8601 string")
    func dateDecoding() throws {
        struct Event: Codable { let at: Date }
        let customEncoder = ToonEncoder()
        let now = Date(timeIntervalSince1970: 1_000_000)
        let encoded = try customEncoder.encode(Event(at: now))
        let decoded = try decoder.decode(Event.self, from: encoded)
        #expect(abs(decoded.at.timeIntervalSince1970 - now.timeIntervalSince1970) < 1)
    }

    @Test("URL decodes from absolute string")
    func urlDecoding() throws {
        struct Link: Codable { let href: URL }
        let customEncoder = ToonEncoder()
        let url = URL(string: "https://example.com")!
        let encoded = try customEncoder.encode(Link(href: url))
        let decoded = try decoder.decode(Link.self, from: encoded)
        #expect(decoded.href == url)
    }

    @Test("Data decodes from Base64 string")
    func dataDecoding() throws {
        struct Blob: Codable { let raw: Data }
        let customEncoder = ToonEncoder()
        let bytes = Data([0x01, 0x02, 0x03])
        let encoded = try customEncoder.encode(Blob(raw: bytes))
        let decoded = try decoder.decode(Blob.self, from: encoded)
        #expect(decoded.raw == bytes)
    }

    // MARK: - Helpers

    private func toon<T: Decodable>(_ input: String, as type: T.Type = String.self) throws -> T {
        try decoder.decode(T.self, from: input.data(using: .utf8)!)
    }
}
