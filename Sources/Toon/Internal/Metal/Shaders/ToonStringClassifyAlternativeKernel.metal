#include <metal_stdlib>

using namespace metal;

kernel void classify_ascii_string_characters_alternative(
    const device uchar *inputBytes [[buffer(0)]],
    const device uchar *delimiterBytes [[buffer(1)]],
    device uchar *outputFlags [[buffer(2)]],
    uint index [[thread_position_in_grid]]
) {
    uchar value = inputBytes[index];
    uchar delimiter = delimiterBytes[0];
    uchar flags = 0;

    bool requiresEscape = toon_requires_escape(value);
    bool isStructural = toon_is_structural_or_delimiter(value, delimiter);
    bool isNonASCII = value > 0x7F;

    if (requiresEscape) {
        flags |= toonFlagNeedsEscape;
    }
    if (isStructural) {
        flags |= toonFlagStructuralOrDelimiter;
    }
    if (isNonASCII) {
        flags |= toonFlagNonASCII;
    }

    outputFlags[index] = flags;
}
