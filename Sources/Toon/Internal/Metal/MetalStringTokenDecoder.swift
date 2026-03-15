import Foundation

/// Orchestrates Metal-accelerated batch decoding of TOON tabular-array rows.
///
/// The entry point is ``decodeTabular(rowContents:fields:delimiter:acceleration:)``.
/// The caller passes pre-collected row content strings (already indentation-trimmed)
/// and this type handles:
///
/// 1. Splitting each row into cells by the declared delimiter (respecting quoted strings).
/// 2. Concatenating all cell bytes into a single contiguous buffer.
/// 3. Delegating classification + unescaping to ``ToonMetalStringAccelerator``.
/// 4. Reassembling one `ToonValue` per row.
///
/// Returns `nil` when Metal is unavailable, the batch is below threshold, or any
/// error occurs — in every nil case the caller falls back to the CPU path.
enum ToonMetalTokenDecoder {

    // MARK: - Public interface

    static func decodeTabular(
        rowContents: [Substring],
        fields: [String],
        delimiter: String,
        acceleration: ToonDecoder.Acceleration
    ) -> [ToonValue]? {
        guard let delimByte = delimiter.utf8.first,
              delimiter.utf8.count == 1,
              !fields.isEmpty,
              !rowContents.isEmpty
        else { return nil }

        let fieldCount = fields.count

        // ── Phase 1: Scan rows, split into cell ranges ────────────────────────
        var allBytes: [UInt8] = []
        allBytes.reserveCapacity(rowContents.count * fieldCount * 16)

        var rangeStarts: [UInt32] = []
        var rangeEnds:   [UInt32] = []
        rangeStarts.reserveCapacity(rowContents.count * fieldCount)
        rangeEnds.reserveCapacity(rowContents.count * fieldCount)

        for rowContent in rowContents {
            let baseOffset = allBytes.count

            let appended = rowContent.utf8.withContiguousStorageIfAvailable { buf -> Bool in
                allBytes.append(contentsOf: buf)
                return true
            } ?? false

            if !appended {
                allBytes.append(contentsOf: rowContent.utf8)
            }

            let rowEnd = allBytes.count
            let cellCount = splitRowIntoRanges(
                bytes: allBytes,
                from: baseOffset,
                to: rowEnd,
                delimiter: delimByte,
                rangeStarts: &rangeStarts,
                rangeEnds: &rangeEnds
            )

            guard cellCount == fieldCount else {
                // Field count mismatch — let CPU raise the error
                return nil
            }
        }

        let totalCells   = rangeStarts.count
        let totalBytes   = allBytes.count

        // ── Phase 2: Threshold check ──────────────────────────────────────────
        guard MetalStringDecodingPolicy.shouldUseMetal(
            cellCount: totalCells,
            estimatedTotalBytes: totalBytes,
            acceleration: acceleration
        ) else { return nil }

        // ── Phase 3: Metal batch decode ───────────────────────────────────────
        guard let metalValues = ToonMetalStringAccelerator.shared.decodeTokenRanges(
            concatenatedBytes: allBytes,
            rangeStarts: rangeStarts,
            rangeEnds: rangeEnds
        ) else { return nil }

        guard metalValues.count == totalCells else { return nil }

        // ── Phase 4: Reassemble ToonValue rows ────────────────────────────────
        var rows: [ToonValue] = []
        rows.reserveCapacity(rowContents.count)

        var cellIdx = 0
        for _ in rowContents {
            var object: [String: ToonValue] = Dictionary(minimumCapacity: fieldCount)
            for field in fields {
                guard cellIdx < metalValues.count else { return nil }
                // nil means non-ASCII or unrecognised escape → fall back to CPU
                guard let value = metalValues[cellIdx] else { return nil }
                object[field] = value
                cellIdx += 1
            }
            rows.append(.object(object, keyOrder: fields))
        }

        return rows
    }

    // MARK: - Private helpers

    /// Scans `bytes[from..<to]` for unquoted occurrences of `delimiter` and records
    /// each cell as a trimmed `(start, end)` range pair.
    ///
    /// Backslash-escaped characters inside quoted cells are treated as opaque so that
    /// `\","` (escaped quote followed by comma) does not end the cell prematurely.
    ///
    /// Returns the number of cells found.
    @discardableResult
    private static func splitRowIntoRanges(
        bytes: [UInt8],
        from: Int,
        to: Int,
        delimiter: UInt8,
        rangeStarts: inout [UInt32],
        rangeEnds:   inout [UInt32]
    ) -> Int {
        var cellCount  = 0
        var cellStart  = from
        var inQuotes   = false
        var escaped    = false
        var i          = from

        while i < to {
            let b = bytes[i]
            if escaped {
                escaped = false
            } else if b == 92 { // backslash
                escaped = true
            } else if b == 34 { // double-quote
                inQuotes.toggle()
            } else if b == delimiter, !inQuotes {
                appendTrimmed(
                    bytes: bytes, start: cellStart, end: i,
                    rangeStarts: &rangeStarts, rangeEnds: &rangeEnds
                )
                cellStart = i + 1
                cellCount += 1
            }
            i += 1
        }

        // Append the final cell
        appendTrimmed(
            bytes: bytes, start: cellStart, end: to,
            rangeStarts: &rangeStarts, rangeEnds: &rangeEnds
        )
        cellCount += 1

        return cellCount
    }

    /// Records byte `[start, end)` trimmed of ASCII whitespace.
    @inline(__always)
    private static func appendTrimmed(
        bytes: [UInt8],
        start: Int,
        end: Int,
        rangeStarts: inout [UInt32],
        rangeEnds:   inout [UInt32]
    ) {
        var s = start
        var e = end
        while s < e, isASCIIWS(bytes[s])   { s += 1 }
        while e > s, isASCIIWS(bytes[e-1]) { e -= 1 }
        guard s <= Int(UInt32.max), e <= Int(UInt32.max) else { return }
        rangeStarts.append(UInt32(s))
        rangeEnds.append(UInt32(e))
    }

    @inline(__always)
    private static func isASCIIWS(_ b: UInt8) -> Bool {
        b == 32 || b == 9 || b == 10 || b == 13 || b == 11 || b == 12
    }
}
