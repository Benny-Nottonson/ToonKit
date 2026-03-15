#include <metal_stdlib>

using namespace metal;

// MARK: - Token kind constants

/// Written to outputKinds[i] by decode_token_ranges.
constant uchar toonDecodeKindNull                  = 0;
constant uchar toonDecodeKindBoolTrue              = 1;
constant uchar toonDecodeKindBoolFalse             = 2;
constant uchar toonDecodeKindStringUnquoted        = 3;  // use inputBytes[start..end]
constant uchar toonDecodeKindStringQuotedNoEscape  = 4;  // use inputBytes[start+1..end-1]
constant uchar toonDecodeKindStringQuotedEscaped   = 5;  // use outputBytes[offset..offset+length]
constant uchar toonDecodeKindInteger               = 6;  // parse inputBytes[start..end] as Int64
constant uchar toonDecodeKindDouble                = 7;  // parse inputBytes[start..end] as Double
constant uchar toonDecodeKindNonASCII              = 8;  // CPU fallback required
constant uchar toonDecodeKindInvalid               = 255;

// MARK: - Kernel

/// Each thread i processes token range [rangeStarts[i], rangeEnds[i]) from inputBytes.
///
/// Outputs:
///  - outputKinds[i]:   classification (see constants above)
///  - outputLengths[i]: length of unescaped bytes in outputBytes for kind == 5; zero otherwise
///  - outputBytes[outputOffsets[i] ..< outputOffsets[i]+outputLengths[i]]:
///                      unescaped content, only written when kind == 5
///
/// The caller pre-trims whitespace from each range; the shader also re-trims
/// defensively so standalone invocations remain correct.
kernel void decode_token_ranges(
    const device uchar *inputBytes    [[buffer(0)]],
    const device uint  *rangeStarts   [[buffer(1)]],
    const device uint  *rangeEnds     [[buffer(2)]],
    const device uint  *outputOffsets [[buffer(3)]],
    device       uchar *outputBytes   [[buffer(4)]],
    device       uint  *outputLengths [[buffer(5)]],
    device       uchar *outputKinds   [[buffer(6)]],
    uint index [[thread_position_in_grid]]
) {
    uint start = rangeStarts[index];
    uint end   = rangeEnds[index];

    // Trim leading ASCII whitespace
    while (start < end && toon_is_ascii_whitespace(inputBytes[start])) { ++start; }
    // Trim trailing ASCII whitespace
    while (end > start && toon_is_ascii_whitespace(inputBytes[end - 1])) { --end; }

    if (start >= end) {
        // Empty token → empty unquoted string
        outputKinds[index]   = toonDecodeKindStringUnquoted;
        outputLengths[index] = 0;
        return;
    }

    // -------------------------------------------------------------------------
    // Non-ASCII check (4-wide unrolled for throughput on Apple GPUs).
    // Any byte > 0x7F means the token needs CPU handling.
    // -------------------------------------------------------------------------
    {
        uint i      = start;
        uint vecEnd = end - ((end - start) % 4);
        for (; i < vecEnd; i += 4) {
            if (inputBytes[i]     > 0x7F || inputBytes[i + 1] > 0x7F ||
                inputBytes[i + 2] > 0x7F || inputBytes[i + 3] > 0x7F) {
                outputKinds[index]   = toonDecodeKindNonASCII;
                outputLengths[index] = 0;
                return;
            }
        }
        for (; i < end; ++i) {
            if (inputBytes[i] > 0x7F) {
                outputKinds[index]   = toonDecodeKindNonASCII;
                outputLengths[index] = 0;
                return;
            }
        }
    }

    uint length = end - start;

    // -------------------------------------------------------------------------
    // Quoted string: must start AND end with '"' and have length >= 2.
    // -------------------------------------------------------------------------
    if (length >= 2 && inputBytes[start] == '"' && inputBytes[end - 1] == '"') {
        uint innerStart = start + 1;
        uint innerEnd   = end - 1;

        // Scan inner content for backslash
        bool hasEscape = false;
        for (uint j = innerStart; j < innerEnd; ++j) {
            if (inputBytes[j] == '\\') { hasEscape = true; break; }
        }

        if (!hasEscape) {
            outputKinds[index]   = toonDecodeKindStringQuotedNoEscape;
            outputLengths[index] = 0;
            return;
        }

        // Unescape inner content into outputBytes[outputOffsets[index]...]
        uint outIdx = outputOffsets[index];
        uint inIdx  = innerStart;
        while (inIdx < innerEnd) {
            uchar b = inputBytes[inIdx++];
            if (b == '\\') {
                if (inIdx >= innerEnd) {
                    // Trailing backslash inside quotes — invalid
                    outputKinds[index]   = toonDecodeKindInvalid;
                    outputLengths[index] = 0;
                    return;
                }
                uchar next = inputBytes[inIdx++];
                switch (next) {
                    case '\\': outputBytes[outIdx++] = '\\'; break;
                    case '"':  outputBytes[outIdx++] = '"';  break;
                    case 'n':  outputBytes[outIdx++] = '\n'; break;
                    case 'r':  outputBytes[outIdx++] = '\r'; break;
                    case 't':  outputBytes[outIdx++] = '\t'; break;
                    default:
                        outputKinds[index]   = toonDecodeKindInvalid;
                        outputLengths[index] = 0;
                        return;
                }
            } else {
                outputBytes[outIdx++] = b;
            }
        }
        outputKinds[index]   = toonDecodeKindStringQuotedEscaped;
        outputLengths[index] = outIdx - outputOffsets[index];
        return;
    }

    // -------------------------------------------------------------------------
    // Reserved literals
    // -------------------------------------------------------------------------
    if (toon_bytes_equal_literal(inputBytes, start, end, toonNullLiteral, 4)) {
        outputKinds[index]   = toonDecodeKindNull;
        outputLengths[index] = 0;
        return;
    }
    if (toon_bytes_equal_literal(inputBytes, start, end, toonTrueLiteral, 4)) {
        outputKinds[index]   = toonDecodeKindBoolTrue;
        outputLengths[index] = 0;
        return;
    }
    if (toon_bytes_equal_literal(inputBytes, start, end, toonFalseLiteral, 5)) {
        outputKinds[index]   = toonDecodeKindBoolFalse;
        outputLengths[index] = 0;
        return;
    }

    // -------------------------------------------------------------------------
    // Numeric: integer vs floating-point
    // -------------------------------------------------------------------------
    if (toon_is_numeric_ascii(inputBytes, start, end)) {
        bool isDouble = false;
        for (uint j = start; j < end; ++j) {
            uchar ch = inputBytes[j];
            if (ch == '.' || ch == 'e' || ch == 'E') { isDouble = true; break; }
        }
        outputKinds[index]   = isDouble ? toonDecodeKindDouble : toonDecodeKindInteger;
        outputLengths[index] = 0;
        return;
    }

    // -------------------------------------------------------------------------
    // Unquoted plain string
    // -------------------------------------------------------------------------
    outputKinds[index]   = toonDecodeKindStringUnquoted;
    outputLengths[index] = 0;
}
