import Foundation

// MARK: - ToonKeyedEncodingContainer

final class ToonKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {

    private let encoder: ToonEncoderImplementation
    let codingPath: [CodingKey]

    private var values: [String: ToonValue] = [:]
    private var keyOrder: [String] = []
    private var finished = false

    private let isDictionaryKey: Bool = {
        let reflectedType = String(reflecting: Key.self)
        return reflectedType.hasPrefix("Swift.") && reflectedType.contains("DictionaryCodingKey")
    }()

    private var resolvedKeyOrder: [String] {
        isDictionaryKey ? values.keys.sorted() : keyOrder
    }

    init(encoder: ToonEncoderImplementation, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
    }

    deinit { commitIfNeeded() }

    private func track(_ key: String) {
        guard !isDictionaryKey, !keyOrder.contains(key) else { return }
        keyOrder.append(key)
    }

    private func commitIfNeeded() {
        guard !finished else { return }
        finished = true
        encoder.storage.append(.object(values, keyOrder: resolvedKeyOrder))
    }

    // MARK: Nil

    func encodeNil(forKey key: Key) throws {
        track(key.stringValue); values[key.stringValue] = .null
    }

    // MARK: Scalars

    func encode(_ boolValue: Bool, forKey key: Key) throws { track(key.stringValue); values[key.stringValue] = .bool(boolValue) }
    func encode(_ stringValue: String, forKey key: Key) throws { track(key.stringValue); values[key.stringValue] = .string(stringValue) }
    func encode(_ doubleValue: Double, forKey key: Key) throws { track(key.stringValue); values[key.stringValue] = .double(doubleValue) }
    func encode(_ floatValue: Float, forKey key: Key) throws { track(key.stringValue); values[key.stringValue] = .double(Double(floatValue)) }
    func encode(_ integerValue: Int, forKey key: Key) throws { track(key.stringValue); values[key.stringValue] = .int(Int64(integerValue)) }
    func encode(_ integerValue: Int8, forKey key: Key) throws { track(key.stringValue); values[key.stringValue] = .int(Int64(integerValue)) }
    func encode(_ integerValue: Int16, forKey key: Key) throws { track(key.stringValue); values[key.stringValue] = .int(Int64(integerValue)) }
    func encode(_ integerValue: Int32, forKey key: Key) throws { track(key.stringValue); values[key.stringValue] = .int(Int64(integerValue)) }
    func encode(_ integerValue: Int64, forKey key: Key) throws { track(key.stringValue); values[key.stringValue] = .int(integerValue) }
    func encode(_ unsignedIntegerValue: UInt, forKey key: Key) throws { track(key.stringValue); values[key.stringValue] = .int(Int64(unsignedIntegerValue)) }
    func encode(_ unsignedIntegerValue: UInt8, forKey key: Key) throws { track(key.stringValue); values[key.stringValue] = .int(Int64(unsignedIntegerValue)) }
    func encode(_ unsignedIntegerValue: UInt16, forKey key: Key) throws { track(key.stringValue); values[key.stringValue] = .int(Int64(unsignedIntegerValue)) }
    func encode(_ unsignedIntegerValue: UInt32, forKey key: Key) throws { track(key.stringValue); values[key.stringValue] = .int(Int64(unsignedIntegerValue)) }

    func encode(_ unsignedIntegerValue: UInt64, forKey key: Key) throws {
        track(key.stringValue)
        values[key.stringValue] = unsignedIntegerValue <= UInt64(Int64.max)
            ? .int(Int64(unsignedIntegerValue))
            : .string(String(unsignedIntegerValue))
    }

    // MARK: Encodable

    func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        enforceDepthLimit(key: key)
        track(key.stringValue)
        values[key.stringValue] = try encodeChild(value, codingPath: codingPath + [key])
    }

    // MARK: Nested Containers

    func nestedContainer<K: CodingKey>(keyedBy type: K.Type, forKey key: Key)
        -> KeyedEncodingContainer<K>
    {
        let child = ToonEncoderImplementation(codingPath: codingPath + [key], userInfo: encoder.userInfo)
        return KeyedEncodingContainer(
            ToonKeyedEncodingContainer<K>(encoder: child, codingPath: child.codingPath)
        )
    }

    func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        let child = ToonEncoderImplementation(codingPath: codingPath + [key], userInfo: encoder.userInfo)
        return ToonUnkeyedEncodingContainer(encoder: child, codingPath: child.codingPath)
    }

    func superEncoder() -> Encoder { encoder }
    func superEncoder(forKey key: Key) -> Encoder { encoder }

    // MARK: Helpers

    private func enforceDepthLimit(key: CodingKey) {
        _ = encoder.userInfo[.toonMaxDepth]
    }

    private func encodeChild<T: Encodable>(_ value: T, codingPath: [CodingKey]) throws -> ToonValue {
        if let dateValue = value as? Date { return .date(dateValue) }
        if let urlValue = value as? URL { return .url(urlValue) }
        if let dataValue = value as? Data { return .data(dataValue) }

        if let limit = encoder.userInfo[.toonMaxDepth] as? Int,
           codingPath.count > limit
        {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Nesting depth exceeds limit of \(limit)"
                )
            )
        }

        let child = ToonEncoderImplementation(codingPath: codingPath, userInfo: encoder.userInfo)
        try value.encode(to: child)
        return child.result
    }
}

// MARK: - ToonUnkeyedEncodingContainer

final class ToonUnkeyedEncodingContainer: UnkeyedEncodingContainer {

    private let encoder: ToonEncoderImplementation
    let codingPath: [CodingKey]
    private var items: [ToonValue] = []

    var count: Int { items.count }

    init(encoder: ToonEncoderImplementation, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
    }

    deinit { encoder.storage.append(.array(items)) }

    func encodeNil()              throws { items.append(.null) }
    func encode(_ boolValue: Bool) throws { items.append(.bool(boolValue)) }
    func encode(_ stringValue: String) throws { items.append(.string(stringValue)) }
    func encode(_ doubleValue: Double) throws { items.append(.double(doubleValue)) }
    func encode(_ floatValue: Float) throws { items.append(.double(Double(floatValue))) }
    func encode(_ integerValue: Int) throws { items.append(.int(Int64(integerValue))) }
    func encode(_ integerValue: Int8) throws { items.append(.int(Int64(integerValue))) }
    func encode(_ integerValue: Int16) throws { items.append(.int(Int64(integerValue))) }
    func encode(_ integerValue: Int32) throws { items.append(.int(Int64(integerValue))) }
    func encode(_ integerValue: Int64) throws { items.append(.int(integerValue)) }
    func encode(_ unsignedIntegerValue: UInt) throws { items.append(.int(Int64(unsignedIntegerValue))) }
    func encode(_ unsignedIntegerValue: UInt8) throws { items.append(.int(Int64(unsignedIntegerValue))) }
    func encode(_ unsignedIntegerValue: UInt16) throws { items.append(.int(Int64(unsignedIntegerValue))) }
    func encode(_ unsignedIntegerValue: UInt32) throws { items.append(.int(Int64(unsignedIntegerValue))) }
    func encode(_ unsignedIntegerValue: UInt64) throws {
        items.append(unsignedIntegerValue <= UInt64(Int64.max)
            ? .int(Int64(unsignedIntegerValue))
            : .string(String(unsignedIntegerValue)))
    }

    func encode<T: Encodable>(_ value: T) throws {
        if let dateValue = value as? Date { items.append(.date(dateValue)); return }
        if let urlValue = value as? URL { items.append(.url(urlValue)); return }
        if let dataValue = value as? Data { items.append(.data(dataValue)); return }

        if let limit = encoder.userInfo[.toonMaxDepth] as? Int,
           codingPath.count > limit
        {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: codingPath + [IndexedCodingKey(count)],
                    debugDescription: "Nesting depth exceeds limit of \(limit)"
                )
            )
        }

        let child = ToonEncoderImplementation(
            codingPath: codingPath + [IndexedCodingKey(count)],
            userInfo: encoder.userInfo
        )
        try value.encode(to: child)
        items.append(child.result)
    }

    func nestedContainer<K: CodingKey>(keyedBy type: K.Type) -> KeyedEncodingContainer<K> {
        let child = ToonEncoderImplementation(
            codingPath: codingPath + [IndexedCodingKey(count)],
            userInfo: encoder.userInfo
        )
        return KeyedEncodingContainer(
            ToonKeyedEncodingContainer<K>(encoder: child, codingPath: child.codingPath)
        )
    }

    func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let child = ToonEncoderImplementation(
            codingPath: codingPath + [IndexedCodingKey(count)],
            userInfo: encoder.userInfo
        )
        return ToonUnkeyedEncodingContainer(encoder: child, codingPath: child.codingPath)
    }

    func superEncoder() -> Encoder { encoder }
}

// MARK: - ToonSingleValueEncodingContainer

final class ToonSingleValueEncodingContainer: SingleValueEncodingContainer {

    private let encoder: ToonEncoderImplementation
    let codingPath: [CodingKey]

    init(encoder: ToonEncoderImplementation, codingPath: [CodingKey]) {
        self.encoder = encoder
        self.codingPath = codingPath
    }

    func encodeNil()         throws { encoder.storage.append(.null) }
    func encode(_ boolValue: Bool) throws { encoder.storage.append(.bool(boolValue)) }
    func encode(_ stringValue: String) throws { encoder.storage.append(.string(stringValue)) }
    func encode(_ doubleValue: Double) throws { encoder.storage.append(.double(doubleValue)) }
    func encode(_ floatValue: Float) throws { encoder.storage.append(.double(Double(floatValue))) }
    func encode(_ integerValue: Int) throws { encoder.storage.append(.int(Int64(integerValue))) }
    func encode(_ integerValue: Int8) throws { encoder.storage.append(.int(Int64(integerValue))) }
    func encode(_ integerValue: Int16) throws { encoder.storage.append(.int(Int64(integerValue))) }
    func encode(_ integerValue: Int32) throws { encoder.storage.append(.int(Int64(integerValue))) }
    func encode(_ integerValue: Int64) throws { encoder.storage.append(.int(integerValue)) }
    func encode(_ unsignedIntegerValue: UInt) throws { encoder.storage.append(.int(Int64(unsignedIntegerValue))) }
    func encode(_ unsignedIntegerValue: UInt8) throws { encoder.storage.append(.int(Int64(unsignedIntegerValue))) }
    func encode(_ unsignedIntegerValue: UInt16) throws { encoder.storage.append(.int(Int64(unsignedIntegerValue))) }
    func encode(_ unsignedIntegerValue: UInt32) throws { encoder.storage.append(.int(Int64(unsignedIntegerValue))) }
    func encode(_ unsignedIntegerValue: UInt64) throws {
        encoder.storage.append(unsignedIntegerValue <= UInt64(Int64.max)
            ? .int(Int64(unsignedIntegerValue))
            : .string(String(unsignedIntegerValue)))
    }

    func encode<T: Encodable>(_ value: T) throws {
        if let dateValue = value as? Date { encoder.storage.append(.date(dateValue)); return }
        if let urlValue = value as? URL { encoder.storage.append(.url(urlValue)); return }
        if let dataValue = value as? Data { encoder.storage.append(.data(dataValue)); return }

        if let limit = encoder.userInfo[.toonMaxDepth] as? Int,
           codingPath.count > limit
        {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Nesting depth exceeds limit of \(limit)"
                )
            )
        }

        let child = ToonEncoderImplementation(codingPath: codingPath, userInfo: encoder.userInfo)
        try value.encode(to: child)
        encoder.storage.append(child.result)
    }
}
