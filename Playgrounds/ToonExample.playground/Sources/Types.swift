import Foundation

public struct Config: Codable, Equatable {
    public let host: String
    public let port: Int
    public let debug: Bool

    public init(host: String, port: Int, debug: Bool) {
        self.host = host
        self.port = port
        self.debug = debug
    }
}

public struct Tags: Codable {
    public let service: String
    public let tags: [String]
    public let ports: [Int]

    public init(service: String, tags: [String], ports: [Int]) {
        self.service = service
        self.tags = tags
        self.ports = ports
    }
}

public struct Product: Codable {
    public let sku: String
    public let qty: Int
    public let price: Double

    public init(sku: String, qty: Int, price: Double) {
        self.sku = sku
        self.qty = qty
        self.price = price
    }
}

public struct Cart: Codable {
    public let currency: String
    public let items: [Product]

    public init(currency: String, items: [Product]) {
        self.currency = currency
        self.items = items
    }
}

public struct Address: Codable {
    public let street: String
    public let city: String
    public let country: String

    public init(street: String, city: String, country: String) {
        self.street = street
        self.city = city
        self.country = country
    }
}

public struct User: Codable {
    public let id: Int
    public let name: String
    public let address: Address

    public init(id: Int, name: String, address: Address) {
        self.id = id
        self.name = name
        self.address = address
    }
}

public struct Asset: Codable {
    public let name: String
    public let url: URL
    public let createdAt: Date
    public let thumbnail: Data

    public init(name: String, url: URL, createdAt: Date, thumbnail: Data) {
        self.name = name
        self.url = url
        self.createdAt = createdAt
        self.thumbnail = thumbnail
    }
}

public struct ToonMeasurement: Codable {
    public let value: Double

    public init(value: Double) {
        self.value = value
    }
}
