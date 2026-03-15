import Foundation
import Dispatch

enum ToonStringLiteralEncoder {
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
        let estimatedTotalBytes = candidateStringValues.reduce(into: 0) { $0 += $1.utf8.count }

        func encodeDeduplicatedOnCPUOnSingleThread() -> [String] {
            let encodedUniqueValues = candidateStringValues.map {
                encode($0, delimiter: delimiter, acceleration: .disabled)
            }
            return deduplicatedBatch.expand(encodedUniqueValues: encodedUniqueValues)
        }

        func fallback() -> [String]? {
            if let encodedCandidates = encodeBatchInParallelOnCPUIfBeneficial(
                candidateStringValues,
                delimiter: delimiter,
                estimatedTotalBytes: estimatedTotalBytes
            ) {
                return deduplicatedBatch.expand(encodedUniqueValues: encodedCandidates)
            }

            if hasDeduplicatedMapping {
                return encodeDeduplicatedOnCPUOnSingleThread()
            }

            return nil
        }

        guard let request = ToonStringAccelerationPolicy.request(for: acceleration) else {
            return nil
        }

        guard let delimiterByte = delimiter.utf8.first else {
            return nil
        }

        guard ToonStringAccelerationPolicy.canAttemptMetalBeforeASCIIScan(
            candidateCount: candidateStringValues.count,
            estimatedTotalBytes: estimatedTotalBytes,
            request: request
        ) else {
            return fallback()
        }

        if request.usesAdaptiveGate,
           !ToonMetalSpeedGate.shared.shouldUseMetal(
                minimumStringByteCount: request.minimumStringByteCount,
                delimiter: delimiterByte,
                stringCount: candidateStringValues.count,
                estimatedTotalBytes: estimatedTotalBytes,
                averageStringBytes: candidateStringValues.isEmpty ? 0 : (estimatedTotalBytes / candidateStringValues.count)
           )
        {
            return fallback()
        }

        var asciiRanges: [ToonASCIIStringRange] = []
        asciiRanges.reserveCapacity(candidateStringValues.count)

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

        guard ToonStringAccelerationPolicy.canAttemptMetalAfterASCIIScan(
            asciiStringCount: asciiRanges.count,
            totalASCIIBytes: totalASCIIBytes,
            request: request
        ) else {
            return request.isForcedMetal ? nil : fallback()
        }

        guard let encodedASCIIValues = ToonMetalStringAccelerator.shared.encodeASCIIStringLiterals(
                concatenatedBytes: concatenatedBytes,
                ranges: asciiRanges,
                originalStrings: candidateStringValues,
                delimiter: delimiterByte
              )
        else {
            return request.isForcedMetal ? nil : fallback()
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
        guard ToonStringAccelerationPolicy.shouldAttemptParallelCPU(
            stringCount: stringValues.count,
            estimatedTotalBytes: estimatedTotalBytes
        )
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