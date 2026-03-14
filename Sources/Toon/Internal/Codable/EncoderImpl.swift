// MARK: - ToonEncoderImplementation

final class ToonEncoderImplementation: Encoder {

    let codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any]

    var storage: [ToonValue] = []

    init(
        codingPath: [CodingKey] = [],
        userInfo: [CodingUserInfoKey: Any] = [:]
    ) {
        self.codingPath = codingPath
        self.userInfo = userInfo
    }

    var result: ToonValue {
        storage.last ?? .null
    }

    // MARK: Encoder Protocol

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        let container = ToonKeyedEncodingContainer<Key>(encoder: self, codingPath: codingPath)
        return KeyedEncodingContainer(container)
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        ToonUnkeyedEncodingContainer(encoder: self, codingPath: codingPath)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        ToonSingleValueEncodingContainer(encoder: self, codingPath: codingPath)
    }
}
