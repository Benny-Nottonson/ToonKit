// MARK: - ToonDecoderImplementation

final class ToonDecoderImplementation: Decoder {

    let value: ToonValue
    let codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    init(value: ToonValue, codingPath: [CodingKey], userInfo: [CodingUserInfoKey: Any]) {
        self.value = value
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    // MARK: Decoder Protocol

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard let (values, keyOrder) = value.objectValue else {
            throw ToonDecodingError.typeMismatch(expected: "object", actual: value.typeName)
        }
        return KeyedDecodingContainer(
            ToonKeyedDecodingContainer<Key>(
                values: values,
                keyOrder: keyOrder,
                codingPath: codingPath,
                userInfo: userInfo
            )
        )
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard let array = value.arrayValue else {
            throw ToonDecodingError.typeMismatch(expected: "array", actual: value.typeName)
        }
        return ToonUnkeyedDecodingContainer(
            values: array, codingPath: codingPath, userInfo: userInfo
        )
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer {
        ToonSingleValueDecodingContainer(
            value: value, codingPath: codingPath, userInfo: userInfo
        )
    }
}
