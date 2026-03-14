// MARK: - Integer Decoding Helpers

func decodeInt(from value: ToonValue) throws -> Int {
    guard let integerValue = value.intValue else {
        throw ToonDecodingError.typeMismatch(expected: "int", actual: value.typeName)
    }
    guard let result = Int(exactly: integerValue) else {
        throw ToonDecodingError.dataCorrupted("\(integerValue) does not fit in Int")
    }
    return result
}

func decodeInt8(from value: ToonValue) throws -> Int8 {
    guard let integerValue = value.intValue else {
        throw ToonDecodingError.typeMismatch(expected: "int8", actual: value.typeName)
    }
    guard let result = Int8(exactly: integerValue) else {
        throw ToonDecodingError.dataCorrupted("\(integerValue) does not fit in Int8")
    }
    return result
}

func decodeInt16(from value: ToonValue) throws -> Int16 {
    guard let integerValue = value.intValue else {
        throw ToonDecodingError.typeMismatch(expected: "int16", actual: value.typeName)
    }
    guard let result = Int16(exactly: integerValue) else {
        throw ToonDecodingError.dataCorrupted("\(integerValue) does not fit in Int16")
    }
    return result
}

func decodeInt32(from value: ToonValue) throws -> Int32 {
    guard let integerValue = value.intValue else {
        throw ToonDecodingError.typeMismatch(expected: "int32", actual: value.typeName)
    }
    guard let result = Int32(exactly: integerValue) else {
        throw ToonDecodingError.dataCorrupted("\(integerValue) does not fit in Int32")
    }
    return result
}

func decodeInt64(from value: ToonValue) throws -> Int64 {
    guard let integerValue = value.intValue else {
        throw ToonDecodingError.typeMismatch(expected: "int64", actual: value.typeName)
    }
    return integerValue
}

func decodeUInt(from value: ToonValue) throws -> UInt {
    guard let integerValue = value.intValue else {
        throw ToonDecodingError.typeMismatch(expected: "uint", actual: value.typeName)
    }
    guard let result = UInt(exactly: integerValue) else {
        throw ToonDecodingError.dataCorrupted("\(integerValue) does not fit in UInt")
    }
    return result
}

func decodeUInt8(from value: ToonValue) throws -> UInt8 {
    guard let integerValue = value.intValue else {
        throw ToonDecodingError.typeMismatch(expected: "uint8", actual: value.typeName)
    }
    guard let result = UInt8(exactly: integerValue) else {
        throw ToonDecodingError.dataCorrupted("\(integerValue) does not fit in UInt8")
    }
    return result
}

func decodeUInt16(from value: ToonValue) throws -> UInt16 {
    guard let integerValue = value.intValue else {
        throw ToonDecodingError.typeMismatch(expected: "uint16", actual: value.typeName)
    }
    guard let result = UInt16(exactly: integerValue) else {
        throw ToonDecodingError.dataCorrupted("\(integerValue) does not fit in UInt16")
    }
    return result
}

func decodeUInt32(from value: ToonValue) throws -> UInt32 {
    guard let integerValue = value.intValue else {
        throw ToonDecodingError.typeMismatch(expected: "uint32", actual: value.typeName)
    }
    guard let result = UInt32(exactly: integerValue) else {
        throw ToonDecodingError.dataCorrupted("\(integerValue) does not fit in UInt32")
    }
    return result
}

func decodeUInt64(from value: ToonValue) throws -> UInt64 {
    if let integerValue = value.intValue, let result = UInt64(exactly: integerValue) {
        return result
    }
    if let string = value.stringValue, let result = UInt64(string) {
        return result
    }
    throw ToonDecodingError.typeMismatch(expected: "uint64", actual: value.typeName)
}
