import Foundation

final class ToonMetalSpeedGate {
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

            let delimiterString = String(decoding: [delimiter], as: UTF8.self)
            let cpuDuration = clock.measure {
                for _ in 0..<iterations {
                    _ = sampleBatch.map {
                        ToonStringLiteralEncoder.encode(
                            $0,
                            delimiter: delimiterString,
                            acceleration: .disabled
                        )
                    }
                }
            }

            let metalDuration = clock.measure {
                for _ in 0..<iterations {
                    _ = ToonStringLiteralEncoder.encodeBatch(
                        sampleBatch,
                        delimiter: delimiterString,
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
