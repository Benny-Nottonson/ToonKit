import Foundation

enum ToonStringAccelerationPolicy {
    static let metalMinimumStringCount = 16
    static let metalMinimumAverageStringBytes = 96
    static let metalMinimumTotalBytes = 65_536
    static let parallelFallbackMinimumStringCount = 512
    static let parallelFallbackMinimumTotalBytes = 262_144

    static func request(for acceleration: ToonEncoder.Acceleration) -> Request? {
        switch acceleration {
        case .disabled:
            return nil
        case .metal(let minimumStringByteCount):
            return Request(
                minimumStringByteCount: minimumStringByteCount,
                usesAdaptiveGate: true,
                isForcedMetal: false
            )
        case .metalForced(let minimumStringByteCount):
            return Request(
                minimumStringByteCount: minimumStringByteCount,
                usesAdaptiveGate: false,
                isForcedMetal: true
            )
        }
    }

    static func requiredTotalBytes(for request: Request) -> Int {
        max(request.minimumStringByteCount, metalMinimumTotalBytes)
    }

    static func canAttemptMetalBeforeASCIIScan(
        candidateCount: Int,
        estimatedTotalBytes: Int,
        request: Request
    ) -> Bool {
        if request.isForcedMetal {
            return true
        }

        return candidateCount >= metalMinimumStringCount
            && estimatedTotalBytes >= requiredTotalBytes(for: request)
    }

    static func canAttemptMetalAfterASCIIScan(
        asciiStringCount: Int,
        totalASCIIBytes: Int,
        request: Request
    ) -> Bool {
        if request.isForcedMetal {
            return asciiStringCount > 0 && totalASCIIBytes >= request.minimumStringByteCount
        }

        let averageStringBytes = asciiStringCount == 0 ? 0 : (totalASCIIBytes / asciiStringCount)
        return asciiStringCount > 1
            && asciiStringCount >= metalMinimumStringCount
            && averageStringBytes >= metalMinimumAverageStringBytes
            && totalASCIIBytes >= request.minimumStringByteCount
            && totalASCIIBytes >= requiredTotalBytes(for: request)
    }

    static func shouldAttemptParallelCPU(stringCount: Int, estimatedTotalBytes: Int) -> Bool {
        stringCount >= parallelFallbackMinimumStringCount
            && estimatedTotalBytes >= parallelFallbackMinimumTotalBytes
    }

    struct Request {
        let minimumStringByteCount: Int
        let usesAdaptiveGate: Bool
        let isForcedMetal: Bool
    }
}
