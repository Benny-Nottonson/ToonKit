import Foundation
import Dispatch

enum ToonStringLiteralEncoder {
    private static let metalMinimumStringCount = 16
    private static let metalMinimumAverageStringBytes = 96
    private static let metalMinimumTotalBytes = 65_536
    private static let parallelFallbackMinimumStringCount = 512
    private static let parallelFallbackMinimumTotalBytes = 262_144

    static var isMetalAccelerationAvailable: Bool {
        ToonMetalStringAccelerator.shared.isAvailable
    }

    static var isMetalAccelerationEnabled: Bool {
        ToonMetalSpeedGate.shared.isEnabled
    }

    static func encode(
        _ stringValue: String,
        delimiter: String,
        acceleration: ToonEncoder.Acceleration
    ) -> String {
        _ = acceleration
        return stringValue.isSafeUnquoted(delimiter: delimiter)
            ? stringValue
            : "\"\(stringValue.toonEscaped)\""
    }

    static func encodeBatch(
        _ stringValues: [String],
        delimiter: String,
        acceleration: ToonEncoder.Acceleration
    ) -> [String]? {
        let deduplicatedBatch = deduplicateBatchIfBeneficial(stringValues)
        let candidateStringValues = deduplicatedBatch.uniqueValues
        let hasDeduplicatedMapping = deduplicatedBatch.originalToUniqueIndices != nil

        func encodeDeduplicatedOnCPU() -> [String] {
            let encodedUniqueValues = candidateStringValues.map {
                encode($0, delimiter: delimiter, acceleration: .disabled)
            }
            return deduplicatedBatch.expand(encodedUniqueValues: encodedUniqueValues)
        }

        let minimumStringByteCount: Int
        let usesAdaptiveGate: Bool
        let isForcedMetal: Bool

        switch acceleration {
        case .disabled:
            return nil
        case .metal(let configuredMinimumStringByteCount):
            minimumStringByteCount = configuredMinimumStringByteCount
            usesAdaptiveGate = true
            isForcedMetal = false
        case .metalForced(let configuredMinimumStringByteCount):
            minimumStringByteCount = configuredMinimumStringByteCount
            usesAdaptiveGate = false
            isForcedMetal = true
        }

        guard let delimiterByte = delimiter.utf8.first else {
            return nil
        }

        let estimatedTotalBytes = candidateStringValues.reduce(into: 0) { $0 += $1.utf8.count }
        let requiredTotalBytes = max(minimumStringByteCount, metalMinimumTotalBytes)

        if !isForcedMetal {
            guard candidateStringValues.count >= metalMinimumStringCount,
                  estimatedTotalBytes >= requiredTotalBytes
            else {
                if hasDeduplicatedMapping {
                    return encodeDeduplicatedOnCPU()
                }
                return nil
            }
        }

        if usesAdaptiveGate,
           !ToonMetalSpeedGate.shared.shouldUseMetal(
                minimumStringByteCount: minimumStringByteCount,
                     delimiter: delimiterByte,
                     stringCount: candidateStringValues.count,
                     estimatedTotalBytes: estimatedTotalBytes,
                     averageStringBytes: candidateStringValues.isEmpty ? 0 : (estimatedTotalBytes / candidateStringValues.count)
           )
        {
            guard let encodedCandidates = encodeBatchInParallelOnCPUIfBeneficial(
                candidateStringValues,
                delimiter: delimiter,
                estimatedTotalBytes: estimatedTotalBytes
            ) else {
                if hasDeduplicatedMapping {
                    return encodeDeduplicatedOnCPU()
                }
                return nil
            }

            return deduplicatedBatch.expand(encodedUniqueValues: encodedCandidates)
        }

        var asciiRanges: [ToonASCIIStringRange] = []
        asciiRanges.reserveCapacity(stringValues.count)

        var concatenatedBytes: [UInt8] = []
        concatenatedBytes.reserveCapacity(stringValues.reduce(into: 0) { $0 += $1.utf8.count })

        var totalASCIIBytes = 0

        for (index, stringValue) in candidateStringValues.enumerated() {
            let startIndex = concatenatedBytes.count
            var isASCII = true

            let usedContiguousUTF8FastPath = stringValue.utf8.withContiguousStorageIfAvailable { contiguousUTF8 in
                for byte in contiguousUTF8 where byte > 127 {
                    return false
                }
                concatenatedBytes.append(contentsOf: contiguousUTF8)
                return true
            } ?? false

            if !usedContiguousUTF8FastPath {
                for byte in stringValue.utf8 {
                    if byte > 127 {
                        isASCII = false
                        break
                    }
                    concatenatedBytes.append(byte)
                }
            } else {
                isASCII = true
            }

            if isASCII {
                let endIndex = concatenatedBytes.count
                asciiRanges.append(
                    ToonASCIIStringRange(
                        originalIndex: index,
                        startIndex: startIndex,
                        endIndex: endIndex
                    )
                )
                totalASCIIBytes += endIndex - startIndex
            } else {
                concatenatedBytes.removeSubrange(startIndex..<concatenatedBytes.count)
            }
        }

                let averageStringBytes = asciiRanges.isEmpty ? 0 : (totalASCIIBytes / asciiRanges.count)

                if isForcedMetal {
                    guard !asciiRanges.isEmpty,
                          totalASCIIBytes >= minimumStringByteCount
                    else {
                        return nil
                    }
                } else {
                    guard asciiRanges.count > 1,
                          asciiRanges.count >= metalMinimumStringCount,
                          averageStringBytes >= metalMinimumAverageStringBytes,
                          totalASCIIBytes >= minimumStringByteCount,
                          totalASCIIBytes >= requiredTotalBytes
                    else {
                        return encodeBatchInParallelOnCPUIfBeneficial(
                            stringValues,
                            delimiter: delimiter,
                            estimatedTotalBytes: estimatedTotalBytes
                        )
                    }
                }

        guard let encodedASCIIValues = ToonMetalStringAccelerator.shared.encodeASCIIStringLiterals(
                concatenatedBytes: concatenatedBytes,
                ranges: asciiRanges,
                originalStrings: candidateStringValues,
                delimiter: delimiterByte
              )
        else {
                    if isForcedMetal {
                        return nil
                    }
            guard let encodedCandidates = encodeBatchInParallelOnCPUIfBeneficial(
                candidateStringValues,
                delimiter: delimiter,
                estimatedTotalBytes: estimatedTotalBytes
            ) else {
                if hasDeduplicatedMapping {
                    return encodeDeduplicatedOnCPU()
                }
                return nil
            }
            return deduplicatedBatch.expand(encodedUniqueValues: encodedCandidates)
        }

                var encodedUniqueValues = Array(repeating: "", count: candidateStringValues.count)
                var encodedByAccelerator = Array(repeating: false, count: candidateStringValues.count)

        for (range, encodedValue) in zip(asciiRanges, encodedASCIIValues) {
            encodedUniqueValues[range.originalIndex] = encodedValue
                    encodedByAccelerator[range.originalIndex] = true
                }

                for (index, stringValue) in candidateStringValues.enumerated() where !encodedByAccelerator[index] {
                    encodedUniqueValues[index] = encode(
                        stringValue,
                        delimiter: delimiter,
                        acceleration: .disabled
                    )
        }

        return deduplicatedBatch.expand(encodedUniqueValues: encodedUniqueValues)
    }

    private struct DeduplicatedStringBatch {
        let uniqueValues: [String]
        let originalToUniqueIndices: [Int]?

        func expand(encodedUniqueValues: [String]) -> [String] {
            guard let originalToUniqueIndices else {
                return encodedUniqueValues
            }

            var expanded: [String] = []
            expanded.reserveCapacity(originalToUniqueIndices.count)
            for uniqueIndex in originalToUniqueIndices {
                expanded.append(encodedUniqueValues[uniqueIndex])
            }
            return expanded
        }
    }

    private static func deduplicateBatchIfBeneficial(_ stringValues: [String]) -> DeduplicatedStringBatch {
        guard stringValues.count >= 128 else {
            return DeduplicatedStringBatch(uniqueValues: stringValues, originalToUniqueIndices: nil)
        }

        var uniqueValues: [String] = []
        uniqueValues.reserveCapacity(stringValues.count)

        var originalToUniqueIndices: [Int] = []
        originalToUniqueIndices.reserveCapacity(stringValues.count)

        var uniqueIndexByValue: [String: Int] = [:]
        uniqueIndexByValue.reserveCapacity(stringValues.count)

        for value in stringValues {
            if let existingIndex = uniqueIndexByValue[value] {
                originalToUniqueIndices.append(existingIndex)
            } else {
                let newIndex = uniqueValues.count
                uniqueValues.append(value)
                uniqueIndexByValue[value] = newIndex
                originalToUniqueIndices.append(newIndex)
            }
        }

        let duplicateCount = stringValues.count - uniqueValues.count
        guard duplicateCount >= (stringValues.count / 8) else {
            return DeduplicatedStringBatch(uniqueValues: stringValues, originalToUniqueIndices: nil)
        }

        return DeduplicatedStringBatch(
            uniqueValues: uniqueValues,
            originalToUniqueIndices: originalToUniqueIndices
        )
    }

    private static func encodeBatchInParallelOnCPUIfBeneficial(
        _ stringValues: [String],
        delimiter: String,
        estimatedTotalBytes: Int
    ) -> [String]? {
        guard stringValues.count >= parallelFallbackMinimumStringCount,
              estimatedTotalBytes >= parallelFallbackMinimumTotalBytes
        else {
            return nil
        }

        let cpuCount = ProcessInfo.processInfo.activeProcessorCount
        let workerCount = min(max(cpuCount, 1), stringValues.count)
        guard workerCount > 1 else {
            return nil
        }

        var encodedValues = Array(repeating: "", count: stringValues.count)

        encodedValues.withUnsafeMutableBufferPointer { outputBuffer in
            DispatchQueue.concurrentPerform(iterations: workerCount) { worker in
                let startIndex = worker * stringValues.count / workerCount
                let endIndex = (worker + 1) * stringValues.count / workerCount
                guard startIndex < endIndex else { return }

                for index in startIndex..<endIndex {
                    outputBuffer[index] = encode(
                        stringValues[index],
                        delimiter: delimiter,
                        acceleration: .disabled
                    )
                }
            }
        }

        return encodedValues
    }
}

private final class ToonMetalSpeedGate {
    static let shared = ToonMetalSpeedGate()

    var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cachedBenchmarkDecision == true
    }

    private let lock = NSLock()
    private var cachedBenchmarkDecision: Bool?
    private var cachedMinimumStringByteCount = 0
    private var cachedDelimiter: UInt8 = 0

    private init() {}

    func shouldUseMetal(
        minimumStringByteCount: Int,
        delimiter: UInt8,
        stringCount: Int,
        estimatedTotalBytes: Int,
        averageStringBytes: Int
    ) -> Bool {
        guard ToonMetalStringAccelerator.shared.isAvailable else { return false }

        if estimatedTotalBytes >= 1_048_576 {
            return true
        }

        if stringCount >= 256,
           estimatedTotalBytes >= 262_144,
           averageStringBytes >= 64
        {
            return true
        }

        if stringCount < 192 || estimatedTotalBytes < 131_072 {
            return false
        }

        lock.lock()
        if let cachedBenchmarkDecision,
           minimumStringByteCount == cachedMinimumStringByteCount,
           delimiter == cachedDelimiter
        {
            lock.unlock()
            return cachedBenchmarkDecision
        }
        lock.unlock()

        let decision = benchmark(minimumStringByteCount: minimumStringByteCount, delimiter: delimiter)

        lock.lock()
        cachedBenchmarkDecision = decision
        cachedMinimumStringByteCount = minimumStringByteCount
        cachedDelimiter = delimiter
        lock.unlock()

        return decision
    }

    private func benchmark(minimumStringByteCount: Int, delimiter: UInt8) -> Bool {
        guard ToonMetalStringAccelerator.shared.isAvailable else { return false }

        let longEscapedBase = String(repeating: "value,with:\"quotes\"\\slashes\\nand\\ttabs|", count: 1_024)
        let longEscapedBatch = (0..<256).map { "\(longEscapedBase)\($0)" }

        let shortStructuredBatch = (0..<8_192).map {
            "code_\($0)_market_spot_session_close_rate_ref"
        }

        let iterations = 3
        let clock = ContinuousClock()

        func measureSpeedup(sampleBatch: [String]) -> Double {
            let totalSampleBytes = sampleBatch.reduce(into: 0) { $0 += $1.utf8.count }
            guard totalSampleBytes >= minimumStringByteCount else { return 0 }

            let cpuDuration = clock.measure {
                for _ in 0..<iterations {
                    _ = sampleBatch.map {
                        ToonStringLiteralEncoder.encode(
                            $0,
                            delimiter: String(decoding: [delimiter], as: UTF8.self),
                            acceleration: .disabled
                        )
                    }
                }
            }

            let metalDuration = clock.measure {
                for _ in 0..<iterations {
                    _ = ToonStringLiteralEncoder.encodeBatch(
                        sampleBatch,
                        delimiter: String(decoding: [delimiter], as: UTF8.self),
                        acceleration: .metalForced(minimumStringByteCount: minimumStringByteCount)
                    )
                }
            }

            let cpuAttoseconds = Double(cpuDuration.components.seconds) * 1_000_000_000_000_000_000
                + Double(cpuDuration.components.attoseconds)
            let metalAttoseconds = Double(metalDuration.components.seconds) * 1_000_000_000_000_000_000
                + Double(metalDuration.components.attoseconds)

            guard metalAttoseconds > 0 else { return 0 }
            return cpuAttoseconds / metalAttoseconds
        }

        let longEscapedSpeedup = measureSpeedup(sampleBatch: longEscapedBatch)
        let shortStructuredSpeedup = measureSpeedup(sampleBatch: shortStructuredBatch)

        return max(longEscapedSpeedup, shortStructuredSpeedup) >= 1.15
    }
}