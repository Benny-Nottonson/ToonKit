import Foundation

/// Thresholds that govern when the Metal backend is used for decoding.
///
/// The Metal decode path is beneficial when there are enough tabular-array tokens
/// to amortise the GPU-dispatch overhead, and enough total byte volume to keep
/// the GPU busy.
enum MetalStringDecodingPolicy {

    /// Minimum total number of cells (rows × fields) before Metal dispatch is attempted.
    ///
    /// Below this count, CPU overhead is lower than Metal launch latency.
    static let metalMinimumCellCount = 512

    /// Minimum concatenated byte volume across all token ranges.
    ///
    /// Smaller payloads are not memory-bandwidth-bound so Metal gains nothing.
    static let metalMinimumTotalBytes = 32_768   // 32 KB

    /// Decides whether Metal should be used for a given tabular batch.
    ///
    /// - Parameters:
    ///   - cellCount:           Total number of cells (rows × fields).
    ///   - estimatedTotalBytes: Approximate byte count of the concatenated token buffer.
    ///   - acceleration:        The caller-provided acceleration preference.
    static func shouldUseMetal(
        cellCount: Int,
        estimatedTotalBytes: Int,
        acceleration: ToonDecoder.Acceleration
    ) -> Bool {
        switch acceleration {
        case .disabled:
            return false

        case .metalForced:
            return ToonMetalStringAccelerator.shared.isAvailable && cellCount > 0

        case .metal(let minimumCellCount):
            guard ToonMetalStringAccelerator.shared.isAvailable else { return false }
            return cellCount >= max(minimumCellCount, metalMinimumCellCount)
                && estimatedTotalBytes >= metalMinimumTotalBytes
        }
    }
}
