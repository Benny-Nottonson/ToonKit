import Foundation
import Testing

@testable import Toon

// MARK: - Round-Trip Tests

@Suite("Round Trip")
struct RoundTripTests {

    let encoder = ToonEncoder()
    let decoder = ToonDecoder()

    // MARK: - Basic Types

    @Test("Int round-trips correctly")
    func roundTripInt() throws {
        try assertRoundTrip(42, as: Int.self)
        try assertRoundTrip(-7, as: Int.self)
        try assertRoundTrip(0, as: Int.self)
        try assertRoundTrip(Int64.max as Int64)
    }

    @Test("Double round-trips correctly")
    func roundTripDouble() throws {
        try assertRoundTrip(3.14)
        try assertRoundTrip(-0.001)
        try assertRoundTrip(1e15)
    }

    @Test("Bool round-trips correctly")
    func roundTripBool() throws {
        try assertRoundTrip(true)
        try assertRoundTrip(false)
    }

    @Test("String round-trips correctly")
    func roundTripString() throws {
        try assertRoundTrip("hello")
        try assertRoundTrip("")
        try assertRoundTrip("line1\nline2")
        try assertRoundTrip("quotes \"inside\"")
        try assertRoundTrip("🚀 emoji")
        try assertRoundTrip("你好")
    }

    // MARK: - Simple Struct

    @Test("Simple struct round-trips correctly")
    func roundTripSimpleStruct() throws {
        struct User: Codable, Equatable {
            let id: Int
            let name: String
            let active: Bool
        }
        try assertRoundTrip(User(id: 123, name: "Ada", active: true))
    }

    // MARK: - Arrays

    @Test("Primitive array round-trips correctly")
    func roundTripPrimitiveArray() throws {
        struct Tags: Codable, Equatable { let tags: [String]; let counts: [Int] }
        try assertRoundTrip(Tags(tags: ["reading", "coding"], counts: [1, 2, 3]))
    }

    @Test("Empty array round-trips correctly")
    func roundTripEmptyArray() throws {
        struct Empty: Codable, Equatable { let items: [String] }
        try assertRoundTrip(Empty(items: []))
    }

    @Test("Tabular array round-trips correctly")
    func roundTripTabularArray() throws {
        struct Item: Codable, Equatable {
            let sku: String
            let qty: Int
            let price: Double
        }
        struct Cart: Codable, Equatable { let items: [Item] }
        try assertRoundTrip(Cart(items: [
            Item(sku: "A1", qty: 2, price: 9.99),
            Item(sku: "B2", qty: 1, price: 14.5),
        ]))
    }

    // MARK: - Nested Objects

    @Test("Nested objects round-trip correctly")
    func roundTripNestedObjects() throws {
        struct Address: Codable, Equatable { let city: String; let zip: String }
        struct Person: Codable, Equatable { let name: String; let address: Address }
        try assertRoundTrip(
            Person(name: "Ada", address: Address(city: "London", zip: "EC1"))
        )
    }

    @Test("Deeply nested objects round-trip correctly")
    func roundTripDeepNesting() throws {
        struct LevelThree: Codable, Equatable { let value: Int }
        struct LevelTwo: Codable, Equatable { let levelThree: LevelThree }
        struct LevelOne: Codable, Equatable { let levelTwo: LevelTwo }
        try assertRoundTrip(LevelOne(levelTwo: LevelTwo(levelThree: LevelThree(value: 99))))
    }

    // MARK: - Optional Fields

    @Test("Optional present field round-trips correctly")
    func roundTripOptionalPresent() throws {
        struct Wrapper: Codable, Equatable { let value: String? }
        try assertRoundTrip(Wrapper(value: "hello"))
    }

    @Test("Optional nil field round-trips correctly")
    func roundTripOptionalNil() throws {
        struct Wrapper: Codable, Equatable { let value: String? }
        try assertRoundTrip(Wrapper(value: nil))
    }

    // MARK: - Foundation Types

    @Test("URL round-trips correctly")
    func roundTripURL() throws {
        struct Link: Codable, Equatable { let href: URL }
        try assertRoundTrip(Link(href: URL(string: "https://example.com/path?q=1")!))
    }

    @Test("Data round-trips correctly")
    func roundTripData() throws {
        struct Blob: Codable, Equatable { let raw: Data }
        try assertRoundTrip(Blob(raw: Data([0xDE, 0xAD, 0xBE, 0xEF])))
    }

    // MARK: - Key Folding + Path Expansion

    @Test("Key folding and path expansion are inverses")
    func roundTripKeyFoldingAndExpansion() throws {
        struct Inner: Codable, Equatable { let count: Int }
        struct Middle: Codable, Equatable { let branch: Inner }
        struct Root: Codable, Equatable { let account: Middle }

        let customEncoder = ToonEncoder()
        customEncoder.keyFolding = .safe
        let customDecoder = ToonDecoder()
        customDecoder.expandPaths = .safe

        let original = Root(account: Middle(branch: Inner(count: 42)))
        let data = try customEncoder.encode(original)
        let decoded = try customDecoder.decode(Root.self, from: data)
        #expect(original == decoded)
    }

    // MARK: - Complex Structure

    @Test("Complex structure round-trips correctly")
    func roundTripComplex() throws {
        struct Tag: Codable, Equatable { let name: String; let weight: Double }
        struct User: Codable, Equatable {
            let id: Int
            let name: String
            let tags: [String]
            let scores: [Int]
            let active: Bool
        }
        try assertRoundTrip(
            User(id: 1, name: "Ada", tags: ["a", "b"], scores: [10, 20, 30], active: true)
        )
    }

    // MARK: - Delimiters

    @Test("Tab delimiter round-trips correctly")
    func roundTripTabDelimiter() throws {
        let customEncoder = ToonEncoder()
        customEncoder.delimiter = .tab

        struct Row: Codable, Equatable { let label: String; let score: Int }
        struct Table: Codable, Equatable { let rows: [Row] }

        let original = Table(rows: [Row(label: "x", score: 1), Row(label: "y", score: 2)])
        let data = try customEncoder.encode(original)
        let decoded = try decoder.decode(Table.self, from: data)
        #expect(original == decoded)
    }

    @Test("Pipe delimiter round-trips correctly")
    func roundTripPipeDelimiter() throws {
        let customEncoder = ToonEncoder()
        customEncoder.delimiter = .pipe

        struct Row: Codable, Equatable { let name: String; let score: Int }
        struct Board: Codable, Equatable { let leaders: [Row] }

        let original = Board(leaders: [Row(name: "Alice", score: 100)])
        let data = try customEncoder.encode(original)
        let decoded = try decoder.decode(Board.self, from: data)
        #expect(original == decoded)
    }

    // MARK: - Helper

    private func assertRoundTrip<T: Codable & Equatable>(
        _ value: T,
        as _: T.Type = T.self,
        file _: StaticString = #filePath,
        line _: UInt = #line
    ) throws {
        let data = try encoder.encode(value)
        let decoded = try decoder.decode(T.self, from: data)
        #expect(value == decoded)
    }
}
