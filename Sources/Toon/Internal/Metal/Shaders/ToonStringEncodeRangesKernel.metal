#include <metal_stdlib>

using namespace metal;

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
    uint start = rangeStarts[rangeIndex];
    uint end = rangeEnds[rangeIndex];
    uint outputStart = outputOffsets[rangeIndex];

    if (end < start) {
        outputLengths[rangeIndex] = 0xFFFFFFFFu;
        outputModes[rangeIndex] = toonOutputModeInvalid;
        return;
    }

    uint length = end - start;
    if (length == 0) {
        outputLengths[rangeIndex] = 0;
        outputModes[rangeIndex] = toonOutputModeQuoteOriginal;
        return;
    }

    uchar firstByte = inputBytes[start];
    uchar lastByte = inputBytes[end - 1];
    bool startsWithListMarker = firstByte == '-';

    bool isReservedLiteral = toon_is_reserved_literal(inputBytes, start, end);
    bool isNumericLike = toon_is_numeric_ascii(inputBytes, start, end);

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
            outputModes[rangeIndex] = toonOutputModeInvalid;
            return;
        }

        hasEscape = hasEscape
            || toon_requires_escape(v0)
            || toon_requires_escape(v1)
            || toon_requires_escape(v2)
            || toon_requires_escape(v3);

        hasStructuralOrDelimiter = hasStructuralOrDelimiter
            || toon_is_structural_or_delimiter(v0, delimiter)
            || toon_is_structural_or_delimiter(v1, delimiter)
            || toon_is_structural_or_delimiter(v2, delimiter)
            || toon_is_structural_or_delimiter(v3, delimiter);
    }

    for (; i < end; ++i) {
        uchar value = inputBytes[i];
        if (value > 0x7F) {
            outputLengths[rangeIndex] = 0xFFFFFFFFu;
            outputModes[rangeIndex] = toonOutputModeInvalid;
            return;
        }

        if (toon_requires_escape(value)) {
            hasEscape = true;
        }
        if (toon_is_structural_or_delimiter(value, delimiter)) {
            hasStructuralOrDelimiter = true;
        }
    }

    bool requiresQuoting = toon_is_ascii_whitespace(firstByte)
        || toon_is_ascii_whitespace(lastByte)
        || isReservedLiteral
        || isNumericLike
        || hasEscape
        || hasStructuralOrDelimiter
        || startsWithListMarker;

    if (!requiresQuoting) {
        outputLengths[rangeIndex] = 0;
        outputModes[rangeIndex] = toonOutputModeUseOriginal;
        return;
    }

    if (!hasEscape) {
        outputLengths[rangeIndex] = 0;
        outputModes[rangeIndex] = toonOutputModeQuoteOriginal;
        return;
    }

    uint outputIndex = outputStart;
    outputBytes[outputIndex++] = '"';

    for (uint i = start; i < end; ++i) {
        outputIndex = toon_write_escaped_ascii_byte(outputBytes, outputIndex, inputBytes[i]);
    }

    outputBytes[outputIndex++] = '"';
    outputLengths[rangeIndex] = outputIndex - outputStart;
    outputModes[rangeIndex] = toonOutputModeUseEncodedBytes;
}
