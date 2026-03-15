#include <metal_stdlib>

using namespace metal;

constant uchar toonFlagNeedsEscape = (1 << 0);
constant uchar toonFlagStructuralOrDelimiter = (1 << 1);
constant uchar toonFlagNonASCII = (1 << 7);

constant uchar toonOutputModeUseOriginal = 0;
constant uchar toonOutputModeQuoteOriginal = 1;
constant uchar toonOutputModeUseEncodedBytes = 2;
constant uchar toonOutputModeInvalid = 0xFF;

constant uchar toonTrueLiteral[] = { 't', 'r', 'u', 'e' };
constant uchar toonFalseLiteral[] = { 'f', 'a', 'l', 's', 'e' };
constant uchar toonNullLiteral[] = { 'n', 'u', 'l', 'l' };

static inline bool toon_is_ascii_digit(uchar value) {
    return value >= '0' && value <= '9';
}

static inline bool toon_is_ascii_whitespace(uchar value) {
    return value == ' ' || value == '\t' || value == '\n' || value == '\r' || value == 11 || value == 12;
}

static inline bool toon_requires_escape(uchar value) {
    return value == '\\' || value == '"' || value == '\n' || value == '\r' || value == '\t';
}

static inline bool toon_is_structural_or_delimiter(uchar value, uchar delimiter) {
    return value == ':' || value == '[' || value == ']' || value == '{' || value == '}' || value == delimiter;
}

static inline bool toon_bytes_equal_literal(
    const device uchar *bytes,
    uint start,
    uint end,
    constant uchar *literal,
    uint literalLength
) {
    if ((end - start) != literalLength) {
        return false;
    }

    for (uint offset = 0; offset < literalLength; ++offset) {
        if (bytes[start + offset] != literal[offset]) {
            return false;
        }
    }

    return true;
}

static inline bool toon_is_reserved_literal(const device uchar *bytes, uint start, uint end) {
    return toon_bytes_equal_literal(bytes, start, end, toonTrueLiteral, 4)
        || toon_bytes_equal_literal(bytes, start, end, toonFalseLiteral, 5)
        || toon_bytes_equal_literal(bytes, start, end, toonNullLiteral, 4);
}

static inline bool toon_is_numeric_ascii(const device uchar *bytes, uint start, uint end) {
    if (start >= end) {
        return false;
    }

    uint index = start;
    if (bytes[index] == '-') {
        ++index;
        if (index >= end) {
            return false;
        }
    }

    uint integerStart = index;
    while (index < end && toon_is_ascii_digit(bytes[index])) {
        ++index;
    }
    if (index == integerStart) {
        return false;
    }

    if (index < end && bytes[index] == '.') {
        ++index;
        uint fractionalStart = index;
        while (index < end && toon_is_ascii_digit(bytes[index])) {
            ++index;
        }
        if (index == fractionalStart) {
            return false;
        }
    }

    if (index < end && (bytes[index] == 'e' || bytes[index] == 'E')) {
        ++index;
        if (index < end && (bytes[index] == '+' || bytes[index] == '-')) {
            ++index;
        }
        uint exponentStart = index;
        while (index < end && toon_is_ascii_digit(bytes[index])) {
            ++index;
        }
        if (index == exponentStart) {
            return false;
        }
    }

    return index == end;
}

static inline uint toon_write_escaped_ascii_byte(
    device uchar *outputBytes,
    uint outputIndex,
    uchar value
) {
    switch (value) {
        case '\\':
            outputBytes[outputIndex++] = '\\';
            outputBytes[outputIndex++] = '\\';
            break;
        case '"':
            outputBytes[outputIndex++] = '\\';
            outputBytes[outputIndex++] = '"';
            break;
        case '\n':
            outputBytes[outputIndex++] = '\\';
            outputBytes[outputIndex++] = 'n';
            break;
        case '\r':
            outputBytes[outputIndex++] = '\\';
            outputBytes[outputIndex++] = 'r';
            break;
        case '\t':
            outputBytes[outputIndex++] = '\\';
            outputBytes[outputIndex++] = 't';
            break;
        default:
            outputBytes[outputIndex++] = value;
            break;
    }

    return outputIndex;
}
