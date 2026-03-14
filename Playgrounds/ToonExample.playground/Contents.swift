import Foundation
import Toon

// MARK: - 1. Simple Struct

print("=== Simple Struct ===\n")

struct Config: Codable, Equatable {
    let host: String
    let port: Int
    let debug: Bool
}

let config = Config(host: "api.example.com", port: 8080, debug: false)
let encoder = ToonEncoder()

let data = try encoder.encode(config)
let toonString = String(data: data, encoding: .utf8)!
print(toonString)

let decoder = ToonDecoder()
let decoded = try decoder.decode(Config.self, from: data)
assert(decoded == config)
print("Round-trip ✓\n")

// MARK: - 2. Primitive Arrays (inline format)

print("=== Primitive Arrays ===\n")

struct Tags: Codable {
    let service: String
    let tags: [String]
    let ports: [Int]
}

let tagged = Tags(service: "nginx", tags: ["http", "proxy", "balancer"], ports: [80, 443])
let tagData = try encoder.encode(tagged)
print(String(data: tagData, encoding: .utf8)!)

// MARK: - 3. Tabular Arrays (object arrays encoded as CSV-like)

print("=== Tabular Arrays ===\n")

struct Product: Codable {
    let sku: String
    let qty: Int
    let price: Double
}

struct Cart: Codable {
    let currency: String
    let items: [Product]
}

let cart = Cart(
    currency: "USD",
    items: [
        Product(sku: "ABC-1", qty: 2, price: 9.99),
        Product(sku: "DEF-2", qty: 1, price: 24.00),
        Product(sku: "GHI-3", qty: 5, price: 1.49),
    ]
)

let cartData = try encoder.encode(cart)
print(String(data: cartData, encoding: .utf8)!)

let decodedCart = try decoder.decode(Cart.self, from: cartData)
print("Cart round-trip ✓ — \(decodedCart.items.count) items\n")

// MARK: - 4. Nested Objects

print("=== Nested Objects ===\n")

struct Address: Codable {
    let street: String
    let city: String
    let country: String
}

struct User: Codable {
    let id: Int
    let name: String
    let address: Address
}

let user = User(id: 42, name: "Ada Lovelace", address: Address(street: "1 Math Lane", city: "London", country: "GB"))
let userData = try encoder.encode(user)
print(String(data: userData, encoding: .utf8)!)

// MARK: - 5. Key Folding (collapses single-child chains)

print("=== Key Folding ===\n")

let foldingEncoder = ToonEncoder()
foldingEncoder.keyFolding = .safe

let foldingDecoder = ToonDecoder()
foldingDecoder.expandPaths = .safe

let foldedData = try foldingEncoder.encode(user)
print(String(data: foldedData, encoding: .utf8)!)

let unfoldedUser = try foldingDecoder.decode(User.self, from: foldedData)
print("Key-folded round-trip ✓ — \(unfoldedUser.name)\n")

// MARK: - 6. Custom Delimiter (tabs for tabular data)

print("=== Tab Delimiter ===\n")

let tabEncoder = ToonEncoder()
tabEncoder.delimiter = .tab

let tabData = try tabEncoder.encode(cart)
print(String(data: tabData, encoding: .utf8)!)

// MARK: - 7. Foundation Types (Date, URL, Data)

print("=== Foundation Types ===\n")

struct Asset: Codable {
    let name: String
    let url: URL
    let createdAt: Date
    let thumbnail: Data
}

let asset = Asset(
    name: "logo.png",
    url: URL(string: "https://cdn.example.com/logo.png")!,
    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
    thumbnail: Data([0xFF, 0xD8, 0xFF, 0xE0])
)

let assetData = try encoder.encode(asset)
print(String(data: assetData, encoding: .utf8)!)

let decodedAsset = try decoder.decode(Asset.self, from: assetData)
print("Asset round-trip ✓ — \(decodedAsset.name)\n")

// MARK: - 8. Non-Finite Float Strategies

print("=== Non-Finite Float Strategies ===\n")

struct Measurement: Codable {
    let value: Double
}

let nullEncoder = ToonEncoder()
nullEncoder.nonFiniteFloatStrategy = .null
let nullStrategyData = try nullEncoder.encode(Measurement(value: .nan))
print("null strategy:", String(data: nullStrategyData, encoding: .utf8)!)

let stringEncoder = ToonEncoder()
stringEncoder.nonFiniteFloatStrategy = .convertToString(
    positiveInfinity: "Infinity",
    negativeInfinity: "-Infinity",
    nan: "NaN"
)
let stringStrategyData = try stringEncoder.encode(Measurement(value: .infinity))
print("string strategy:", String(data: stringStrategyData, encoding: .utf8)!)

print("\nDone! 🎉")
