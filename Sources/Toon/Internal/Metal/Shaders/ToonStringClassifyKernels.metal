#include <metal_stdlib>

using namespace metal;

kernel void classify_ascii_string_characters(
    const device uchar *inputBytes [[buffer(0)]],
    const device uchar *delimiterBytes [[buffer(1)]],
    device uchar *outputFlags [[buffer(2)]],
    uint index [[thread_position_in_grid]]
) {
    uchar value = inputBytes[index];
    uchar delimiter = delimiterBytes[0];
    uchar flags = 0;

    if (value == '\\' || value == '"' || value == '\n' || value == '\r' || value == '\t') {
        flags |= (1 << 0);
    }

    if (value == ':' || value == '[' || value == ']' || value == '{' || value == '}' || value == delimiter) {
        flags |= (1 << 1);
    }

    if (value > 0x7F) {
        flags |= (1 << 7);
    }

    outputFlags[index] = flags;
}

kernel void classify_ascii_string_characters_alternative(
    const device uchar *inputBytes [[buffer(0)]],
    const device uchar *delimiterBytes [[buffer(1)]],
    device uchar *outputFlags [[buffer(2)]],
    uint index [[thread_position_in_grid]]
) {
    uchar value = inputBytes[index];
    uchar delimiter = delimiterBytes[0];
    uchar flags = 0;

    bool requiresEscape = (value == '\\') || (value == '"') || (value == '\n') || (value == '\r') || (value == '\t');
    bool isStructural = (value == ':') || (value == '[') || (value == ']') || (value == '{') || (value == '}') || (value == delimiter);
    bool isNonASCII = value > 0x7F;

    if (requiresEscape) {
        flags |= (1 << 0);
    }
    if (isStructural) {
        flags |= (1 << 1);
    }
    if (isNonASCII) {
        flags |= (1 << 7);
    }

    outputFlags[index] = flags;
}
