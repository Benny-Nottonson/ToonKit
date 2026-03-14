import Foundation

// MARK: - ToonKeyedDecodingContainer

final class ToonKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {

    let values: [String: ToonValue]
    let keyOrder: [String]
    let codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    init(
        values: [String: ToonValue],
        keyOrder: [String],
        codingPath: [CodingKey],
        userInfo: [CodingUserInfoKey: Any]
    ) {
        self.values = values
        self.keyOrder = keyOrder
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    var allKeys: [Key] { keyOrder.compactMap { Key(stringValue: $0) } }
    func contains(_ key: Key) -> Bool { values[key.stringValue] != nil }

    // MARK: Fetch Helper

    private func get(_ key: Key) throws -> ToonValue {
        guard let value = values[key.stringValue] else {
            throw ToonDecodingError.keyNotFound(key.stringValue)
        }
        return value
    }

    // MARK: Nil

    func decodeNil(forKey key: Key) throws -> Bool {
        try get(key).isNull
    }

    // MARK: Scalars

    func decode(_: Bool.Type,   forKey key: Key) throws -> Bool   {
        let value = try get(key)
        guard let boolValue = value.boolValue else { throw ToonDecodingError.typeMismatch(expected: "bool", actual: value.typeName)}
        return boolValue
    }
    func decode(_: String.Type, forKey key: Key) throws -> String {
        let value = try get(key)
        guard let stringValue = value.stringValue else { throw ToonDecodingError.typeMismatch(expected: "string", actual: value.typeName) }
        return stringValue
    }
    func decode(_: Double.Type, forKey key: Key) throws -> Double {
        let value = try get(key)
        guard let doubleValue = value.doubleValue else { throw ToonDecodingError.typeMismatch(expected: "double", actual: value.typeName) }
        return doubleValue
    }
    func decode(_: Float.Type, forKey key: Key) throws -> Float {
        let value = try get(key)
        guard let doubleValue = value.doubleValue else { throw ToonDecodingError.typeMismatch(expected: "float", actual: value.typeName) }
        return Float(doubleValue)
    }
    func decode(_: Int.Type,    forKey key: Key) throws -> Int    { try decodeInt(from: get(key)) }
    func decode(_: Int8.Type,   forKey key: Key) throws -> Int8   { try decodeInt8(from: get(key)) }
    func decode(_: Int16.Type,  forKey key: Key) throws -> Int16  { try decodeInt16(from: get(key)) }
    func decode(_: Int32.Type,  forKey key: Key) throws -> Int32  { try decodeInt32(from: get(key)) }
    func decode(_: Int64.Type,  forKey key: Key) throws -> Int64  { try decodeInt64(from: get(key)) }
    func decode(_: UInt.Type,   forKey key: Key) throws -> UInt   { try decodeUInt(from: get(key)) }
    func decode(_: UInt8.Type,  forKey key: Key) throws -> UInt8  { try decodeUInt8(from: get(key)) }
    func decode(_: UInt16.Type, forKey key: Key) throws -> UInt16 { try decodeUInt16(from: get(key)) }
    func decode(_: UInt32.Type, forKey key: Key) throws -> UInt32 { try decodeUInt32(from: get(key)) }
    func decode(_: UInt64.Type, forKey key: Key) throws -> UInt64 { try decodeUInt64(from: get(key)) }

    // MARK: Decodable

    func decode<T: Decodable>(_: T.Type, forKey key: Key) throws -> T {
        let value = try get(key)
        if T.self == Date.self { return try decodeDate(from: value) as! T }
        if T.self == URL.self  { return try decodeURL(from: value) as! T  }
        if T.self == Data.self { return try decodeData(from: value) as! T }
        let implementation = ToonDecoderImplementation(value: value, codingPath: codingPath + [key], userInfo: userInfo)
        return try T(from: implementation)
    }

    // MARK: Nested Containers

    func nestedContainer<K: CodingKey>(keyedBy type: K.Type, forKey key: Key) throws
        -> KeyedDecodingContainer<K>
    {
        let value = try get(key)
        guard let (values, keyOrder) = value.objectValue else {
            throw ToonDecodingError.typeMismatch(expected: "object", actual: value.typeName)
        }
        return KeyedDecodingContainer(
            ToonKeyedDecodingContainer<K>(
                values: values, keyOrder: keyOrder,
                codingPath: codingPath + [key], userInfo: userInfo
            )
        )
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        let value = try get(key)
        guard let array = value.arrayValue else {
            throw ToonDecodingError.typeMismatch(expected: "array", actual: value.typeName)
        }
        return ToonUnkeyedDecodingContainer(
            values: array, codingPath: codingPath + [key], userInfo: userInfo
        )
    }

    func superDecoder() throws -> Decoder {
        ToonDecoderImplementation(
            value: values["super"] ?? .null,
            codingPath: codingPath, userInfo: userInfo
        )
    }

    func superDecoder(forKey key: Key) throws -> Decoder {
        ToonDecoderImplementation(
            value: try get(key), codingPath: codingPath + [key], userInfo: userInfo
        )
    }
}

// MARK: - ToonUnkeyedDecodingContainer

final class ToonUnkeyedDecodingContainer: UnkeyedDecodingContainer {

    let values: [ToonValue]
    let codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    var count: Int? { values.count }
    var isAtEnd: Bool { currentIndex >= values.count }
    private(set) var currentIndex: Int = 0

    init(values: [ToonValue], codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.values = values
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    private func next() throws -> ToonValue {
        guard !isAtEnd else {
            throw ToonDecodingError.dataCorrupted("No more values in array")
        }
        defer { currentIndex += 1 }
        return values[currentIndex]
    }

    // MARK: Nil

    func decodeNil() throws -> Bool {
        guard !isAtEnd else { throw ToonDecodingError.dataCorrupted("No more values in array") }
        if values[currentIndex].isNull { currentIndex += 1; return true }
        return false
    }

    // MARK: Scalars

    func decode(_: Bool.Type)   throws -> Bool   {
        let value = try next()
        guard let boolValue = value.boolValue else { throw ToonDecodingError.typeMismatch(expected: "bool", actual: value.typeName) }
        return boolValue
    }
    func decode(_: String.Type) throws -> String {
        let value = try next()
        guard let stringValue = value.stringValue else { throw ToonDecodingError.typeMismatch(expected: "string", actual: value.typeName) }
        return stringValue
    }
    func decode(_: Double.Type) throws -> Double {
        let value = try next()
        guard let doubleValue = value.doubleValue else { throw ToonDecodingError.typeMismatch(expected: "double", actual: value.typeName) }
        return doubleValue
    }
    func decode(_: Float.Type) throws -> Float {
        let value = try next()
        guard let doubleValue = value.doubleValue else { throw ToonDecodingError.typeMismatch(expected: "float", actual: value.typeName) }
        return Float(doubleValue)
    }
    func decode(_: Int.Type)    throws -> Int    { try decodeInt(from: next()) }
    func decode(_: Int8.Type)   throws -> Int8   { try decodeInt8(from: next()) }
    func decode(_: Int16.Type)  throws -> Int16  { try decodeInt16(from: next()) }
    func decode(_: Int32.Type)  throws -> Int32  { try decodeInt32(from: next()) }
    func decode(_: Int64.Type)  throws -> Int64  { try decodeInt64(from: next()) }
    func decode(_: UInt.Type)   throws -> UInt   { try decodeUInt(from: next()) }
    func decode(_: UInt8.Type)  throws -> UInt8  { try decodeUInt8(from: next()) }
    func decode(_: UInt16.Type) throws -> UInt16 { try decodeUInt16(from: next()) }
    func decode(_: UInt32.Type) throws -> UInt32 { try decodeUInt32(from: next()) }
    func decode(_: UInt64.Type) throws -> UInt64 { try decodeUInt64(from: next()) }

    // MARK: Decodable

    func decode<T: Decodable>(_: T.Type) throws -> T {
        let value = try next()
        if T.self == Date.self { return try decodeDate(from: value) as! T }
        if T.self == URL.self  { return try decodeURL(from: value) as! T  }
        if T.self == Data.self { return try decodeData(from: value) as! T }
        let implementation = ToonDecoderImplementation(
            value: value,
            codingPath: codingPath + [IndexedCodingKey(currentIndex - 1)],
            userInfo: userInfo
        )
        return try T(from: implementation)
    }

    // MARK: Nested Containers

    func nestedContainer<K: CodingKey>(keyedBy type: K.Type) throws -> KeyedDecodingContainer<K> {
        let value = try next()
        guard let (values, keyOrder) = value.objectValue else {
            throw ToonDecodingError.typeMismatch(expected: "object", actual: value.typeName)
        }
        return KeyedDecodingContainer(
            ToonKeyedDecodingContainer<K>(
                values: values, keyOrder: keyOrder,
                codingPath: codingPath + [IndexedCodingKey(currentIndex - 1)],
                userInfo: userInfo
            )
        )
    }

    func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let value = try next()
        guard let array = value.arrayValue else {
            throw ToonDecodingError.typeMismatch(expected: "array", actual: value.typeName)
        }
        return ToonUnkeyedDecodingContainer(
            values: array,
            codingPath: codingPath + [IndexedCodingKey(currentIndex - 1)],
            userInfo: userInfo
        )
    }

    func superDecoder() throws -> Decoder {
        ToonDecoderImplementation(
            value: try next(),
            codingPath: codingPath + [IndexedCodingKey(currentIndex - 1)],
            userInfo: userInfo
        )
    }
}

// MARK: - ToonSingleValueDecodingContainer

final class ToonSingleValueDecodingContainer: SingleValueDecodingContainer {

    let value: ToonValue
    let codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    init(value: ToonValue, codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.value = value
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    func decodeNil() -> Bool { value.isNull }

    func decode(_: Bool.Type)   throws -> Bool   {
        guard let boolValue = value.boolValue else { throw ToonDecodingError.typeMismatch(expected: "bool", actual: value.typeName) }
        return boolValue
    }
    func decode(_: String.Type) throws -> String {
        guard let stringValue = value.stringValue else { throw ToonDecodingError.typeMismatch(expected: "string", actual: value.typeName) }
        return stringValue
    }
    func decode(_: Double.Type) throws -> Double {
        guard let doubleValue = value.doubleValue else { throw ToonDecodingError.typeMismatch(expected: "double", actual: value.typeName) }
        return doubleValue
    }
    func decode(_: Float.Type) throws -> Float {
        guard let doubleValue = value.doubleValue else { throw ToonDecodingError.typeMismatch(expected: "float", actual: value.typeName) }
        return Float(doubleValue)
    }
    func decode(_: Int.Type)    throws -> Int    { try decodeInt(from: value) }
    func decode(_: Int8.Type)   throws -> Int8   { try decodeInt8(from: value) }
    func decode(_: Int16.Type)  throws -> Int16  { try decodeInt16(from: value) }
    func decode(_: Int32.Type)  throws -> Int32  { try decodeInt32(from: value) }
    func decode(_: Int64.Type)  throws -> Int64  { try decodeInt64(from: value) }
    func decode(_: UInt.Type)   throws -> UInt   { try decodeUInt(from: value) }
    func decode(_: UInt8.Type)  throws -> UInt8  { try decodeUInt8(from: value) }
    func decode(_: UInt16.Type) throws -> UInt16 { try decodeUInt16(from: value) }
    func decode(_: UInt32.Type) throws -> UInt32 { try decodeUInt32(from: value) }
    func decode(_: UInt64.Type) throws -> UInt64 { try decodeUInt64(from: value) }

    func decode<T: Decodable>(_: T.Type) throws -> T {
        if T.self == Date.self { return try decodeDate(from: value) as! T }
        if T.self == URL.self  { return try decodeURL(from: value) as! T  }
        if T.self == Data.self { return try decodeData(from: value) as! T }
        let implementation = ToonDecoderImplementation(value: value, codingPath: codingPath, userInfo: userInfo)
        return try T(from: implementation)
    }
}
