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

    if (toon_requires_escape(value)) {
        flags |= toonFlagNeedsEscape;
    }

    if (toon_is_structural_or_delimiter(value, delimiter)) {
        flags |= toonFlagStructuralOrDelimiter;
    }

    if (value > 0x7F) {
        flags |= toonFlagNonASCII;
    }

    outputFlags[index] = flags;
}
