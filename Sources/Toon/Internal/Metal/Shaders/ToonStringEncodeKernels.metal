#include <metal_stdlib>

using namespace metal;

static inline bool is_ascii_digit(uchar value) {
    return value >= '0' && value <= '9';
}

static inline bool is_ascii_whitespace(uchar value) {
    return value == ' ' || value == '\t' || value == '\n' || value == '\r' || value == 11 || value == 12;
}

static inline bool is_numeric_ascii(const device uchar *bytes, uint start, uint end) {
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
    while (index < end && is_ascii_digit(bytes[index])) {
        ++index;
    }
    if (index == integerStart) {
        return false;
    }

    if (index < end && bytes[index] == '.') {
        ++index;
        uint fractionalStart = index;
        while (index < end && is_ascii_digit(bytes[index])) {
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
        while (index < end && is_ascii_digit(bytes[index])) {
            ++index;
        }
        if (index == exponentStart) {
            return false;
        }
    }

    return index == end;
}

kernel void encode_ascii_string_ranges(
    const device uchar *inputBytes [[buffer(0)]],
    constant uchar &delimiter [[buffer(1)]],
    const device uint *rangeStarts [[buffer(2)]],
    const device uint *rangeEnds [[buffer(3)]],
    const device uint *outputOffsets [[buffer(4)]],
    device uchar *outputBytes [[buffer(5)]],
    device uint *outputLengths [[buffer(6)]],
    device uchar *outputModes [[buffer(7)]],
    uint rangeIndex [[thread_position_in_grid]]
) {
    constexpr uchar outputModeUseOriginal = 0;
    constexpr uchar outputModeQuoteOriginal = 1;
    constexpr uchar outputModeUseEncodedBytes = 2;
    constexpr uchar outputModeInvalid = 0xFF;

    uint start = rangeStarts[rangeIndex];
    uint end = rangeEnds[rangeIndex];
    uint outputStart = outputOffsets[rangeIndex];

    if (end < start) {
        outputLengths[rangeIndex] = 0xFFFFFFFFu;
        outputModes[rangeIndex] = outputModeInvalid;
        return;
    }

    uint length = end - start;
    if (length == 0) {
        outputLengths[rangeIndex] = 0;
        outputModes[rangeIndex] = outputModeQuoteOriginal;
        return;
    }

    uchar firstByte = inputBytes[start];
    uchar lastByte = inputBytes[end - 1];
    bool startsWithListMarker = firstByte == '-';

    bool isReservedLiteral =
        (length == 4 &&
         inputBytes[start] == 't' && inputBytes[start + 1] == 'r' && inputBytes[start + 2] == 'u' && inputBytes[start + 3] == 'e')
        ||
        (length == 5 &&
         inputBytes[start] == 'f' && inputBytes[start + 1] == 'a' && inputBytes[start + 2] == 'l' && inputBytes[start + 3] == 's' && inputBytes[start + 4] == 'e')
        ||
        (length == 4 &&
         inputBytes[start] == 'n' && inputBytes[start + 1] == 'u' && inputBytes[start + 2] == 'l' && inputBytes[start + 3] == 'l');
    bool isNumericLike = is_numeric_ascii(inputBytes, start, end);

    bool hasEscape = false;
    bool hasStructuralOrDelimiter = false;
    uint i = start;
    uint vectorizedEnd = end - ((end - start) % 4);

    for (; i < vectorizedEnd; i += 4) {
        uchar v0 = inputBytes[i];
        uchar v1 = inputBytes[i + 1];
        uchar v2 = inputBytes[i + 2];
        uchar v3 = inputBytes[i + 3];

        if (v0 > 0x7F || v1 > 0x7F || v2 > 0x7F || v3 > 0x7F) {
            outputLengths[rangeIndex] = 0xFFFFFFFFu;
            outputModes[rangeIndex] = outputModeInvalid;
            return;
        }

        hasEscape = hasEscape
            || (v0 == '\\' || v0 == '"' || v0 == '\n' || v0 == '\r' || v0 == '\t')
            || (v1 == '\\' || v1 == '"' || v1 == '\n' || v1 == '\r' || v1 == '\t')
            || (v2 == '\\' || v2 == '"' || v2 == '\n' || v2 == '\r' || v2 == '\t')
            || (v3 == '\\' || v3 == '"' || v3 == '\n' || v3 == '\r' || v3 == '\t');

        hasStructuralOrDelimiter = hasStructuralOrDelimiter
            || (v0 == ':' || v0 == '[' || v0 == ']' || v0 == '{' || v0 == '}' || v0 == delimiter)
            || (v1 == ':' || v1 == '[' || v1 == ']' || v1 == '{' || v1 == '}' || v1 == delimiter)
            || (v2 == ':' || v2 == '[' || v2 == ']' || v2 == '{' || v2 == '}' || v2 == delimiter)
            || (v3 == ':' || v3 == '[' || v3 == ']' || v3 == '{' || v3 == '}' || v3 == delimiter);
    }

    for (; i < end; ++i) {
        uchar value = inputBytes[i];
        if (value > 0x7F) {
            outputLengths[rangeIndex] = 0xFFFFFFFFu;
            outputModes[rangeIndex] = outputModeInvalid;
            return;
        }

        if (value == '\\' || value == '"' || value == '\n' || value == '\r' || value == '\t') {
            hasEscape = true;
        }
        if (value == ':' || value == '[' || value == ']' || value == '{' || value == '}' || value == delimiter) {
            hasStructuralOrDelimiter = true;
        }
    }

    bool requiresQuoting = is_ascii_whitespace(firstByte)
        || is_ascii_whitespace(lastByte)
        || isReservedLiteral
        || isNumericLike
        || hasEscape
        || hasStructuralOrDelimiter
        || startsWithListMarker;

    if (!requiresQuoting) {
        outputLengths[rangeIndex] = 0;
        outputModes[rangeIndex] = outputModeUseOriginal;
        return;
    }

    if (!hasEscape) {
        outputLengths[rangeIndex] = 0;
        outputModes[rangeIndex] = outputModeQuoteOriginal;
        return;
    }

    uint outputIndex = outputStart;
    outputBytes[outputIndex++] = '"';

    for (uint i = start; i < end; ++i) {
        uchar value = inputBytes[i];
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
    }

    outputBytes[outputIndex++] = '"';
    outputLengths[rangeIndex] = outputIndex - outputStart;
    outputModes[rangeIndex] = outputModeUseEncodedBytes;
}
