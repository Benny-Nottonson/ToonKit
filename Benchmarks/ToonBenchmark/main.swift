import Foundation
import Toon

struct BenchmarkCase {
    let name: String
    let iterations: Int
    let operation: () throws -> Void
}

struct BenchmarkResult {
    let name: String
    let iterations: Int
    let totalDuration: Duration

    var totalMilliseconds: Double {
        Double(totalDuration.components.seconds) * 1_000
            + Double(totalDuration.components.attoseconds) / 1_000_000_000_000_000
    }

    var averageMicroseconds: Double {
        (totalMilliseconds * 1_000) / Double(iterations)
    }

    var operationsPerSecond: Double {
        let totalSeconds = totalMilliseconds / 1_000
        guard totalSeconds > 0 else { return .infinity }
        return Double(iterations) / totalSeconds
    }
}

struct BenchmarkComparison {
    let name: String
    let withoutAcceleration: BenchmarkResult
    let withDynamicAcceleration: BenchmarkResult
    let withForcedAcceleration: BenchmarkResult

    var dynamicSpeedup: Double {
        withoutAcceleration.totalMilliseconds / withDynamicAcceleration.totalMilliseconds
    }

    var forcedSpeedup: Double {
        withoutAcceleration.totalMilliseconds / withForcedAcceleration.totalMilliseconds
    }
}

struct BenchmarkAddress: Codable {
    let street: String
    let city: String
    let country: String
}

struct BenchmarkLineItem: Codable {
    let sku: String
    let quantity: Int
    let price: Double
}

struct BenchmarkPayload: Codable {
    let id: Int
    let name: String
    let active: Bool
    let tags: [String]
    let address: BenchmarkAddress
    let items: [BenchmarkLineItem]
}

struct ExchangeRateEntry: Codable {
    let date: String
    let base: String
    let quote: String
    let rate: Double
    let source: String
    let market: String
    let session: String
    let isProvisional: Bool
    let unit: Int
}

struct ExchangeRateFeed: Codable {
    let provider: String
    let generatedAt: String
    let baseCurrency: String
    let disclaimer: String
    let tags: [String]
    let metadata: [String: String]
    let rates: [ExchangeRateEntry]
}

struct ToonBenchmarkCommand {
    static func main() throws {
        let benchmarkMode = ProcessInfo.processInfo.environment["TOON_BENCHMARK_MODE"] ?? "all"

        let payload = BenchmarkPayload(
            id: 42,
            name: "Ada Lovelace",
            active: true,
            tags: ["math", "analysis", "programming", "history"],
            address: BenchmarkAddress(
                street: "1 Analytical Engine Way",
                city: "London",
                country: "GB"
            ),
            items: [
                BenchmarkLineItem(sku: "ABC-1", quantity: 2, price: 9.99),
                BenchmarkLineItem(sku: "DEF-2", quantity: 1, price: 24.5),
                BenchmarkLineItem(sku: "GHI-3", quantity: 5, price: 1.49),
            ]
        )

        let withoutAccelerationEncoder = ToonEncoder()
        withoutAccelerationEncoder.acceleration = .disabled

        let withDynamicAccelerationEncoder = ToonEncoder()
        withDynamicAccelerationEncoder.acceleration = .metal(minimumStringByteCount: 1)

        let withForcedAccelerationEncoder = ToonEncoder()
        withForcedAccelerationEncoder.acceleration = .metalForced(minimumStringByteCount: 1)

        let decoder = ToonDecoder()
        let dynamicDecoder = ToonDecoder()
        dynamicDecoder.acceleration = .metal(minimumCellCount: 1)
        let forcedDecoder = ToonDecoder()
        forcedDecoder.acceleration = .metalForced
        let jsonDecoder = JSONDecoder()
        let jsonEncoder = JSONEncoder()
        let exchangeRateFeed = makeExchangeRateFeed()
        let encodedData = try withoutAccelerationEncoder.encode(payload)
        let encodedExchangeRateFeed = try withoutAccelerationEncoder.encode(exchangeRateFeed)
        let largeEscapedString = String(repeating: "value,with:\"quotes\"\\slashes\\nand\\ttabs|", count: 128)
        let toonEncodedEscapedStringData = try withoutAccelerationEncoder.encode(largeEscapedString)
        let jsonEncodedEscapedStringData = try jsonEncoder.encode(largeEscapedString)
        let largeEscapedStringArray = Array(repeating: largeEscapedString, count: 2_048)
        let largeSafeASCIIString = String(repeating: "abcdefghijklmnopqrstuvwxyz0123456789", count: 256)
        let largeSafeASCIIStringArray = Array(repeating: largeSafeASCIIString, count: 2_048)

        _ = try withDynamicAccelerationEncoder.encode(largeEscapedStringArray)
        _ = try withForcedAccelerationEncoder.encode(largeEscapedStringArray)
        _ = try withDynamicAccelerationEncoder.encode(largeSafeASCIIStringArray)
        _ = try withForcedAccelerationEncoder.encode(largeSafeASCIIStringArray)
        _ = try withDynamicAccelerationEncoder.encode(exchangeRateFeed)
        _ = try withForcedAccelerationEncoder.encode(exchangeRateFeed)
        _ = try decoder.decode(String.self, from: toonEncodedEscapedStringData)
        _ = try jsonDecoder.decode(String.self, from: jsonEncodedEscapedStringData)

        print("Toon Benchmark")
        print("=============")
        print("Swift: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("Metal acceleration available: \(ToonEncoder.isMetalAccelerationAvailable)")
        print("Metal adaptive gate enabled: \(ToonEncoder.isMetalAccelerationEnabled)")
        print("Metal decode available: \(ToonDecoder.isMetalAccelerationAvailable)")
        print("")

        if benchmarkMode == "all" || benchmarkMode == "encode" {
            try runComparison(
                name: "Encode structured payload",
                iterations: 8_000,
                withoutAccelerationOperation: {
                    _ = try withoutAccelerationEncoder.encode(payload)
                },
                withDynamicAccelerationOperation: {
                    _ = try withDynamicAccelerationEncoder.encode(payload)
                },
                withForcedAccelerationOperation: {
                    _ = try withForcedAccelerationEncoder.encode(payload)
                }
            )

            try runComparison(
                name: "Round-trip structured payload",
                iterations: 4_000,
                withoutAccelerationOperation: {
                    let roundTripData = try withoutAccelerationEncoder.encode(payload)
                    _ = try decoder.decode(BenchmarkPayload.self, from: roundTripData)
                },
                withDynamicAccelerationOperation: {
                    let roundTripData = try withDynamicAccelerationEncoder.encode(payload)
                    _ = try decoder.decode(BenchmarkPayload.self, from: roundTripData)
                },
                withForcedAccelerationOperation: {
                    let roundTripData = try withForcedAccelerationEncoder.encode(payload)
                    _ = try decoder.decode(BenchmarkPayload.self, from: roundTripData)
                }
            )

            try runComparison(
                name: "Encode primitive array",
                iterations: 16_000,
                withoutAccelerationOperation: {
                    _ = try withoutAccelerationEncoder.encode(["alpha", "beta", "gamma", "delta", "epsilon"])
                },
                withDynamicAccelerationOperation: {
                    _ = try withDynamicAccelerationEncoder.encode(["alpha", "beta", "gamma", "delta", "epsilon"])
                },
                withForcedAccelerationOperation: {
                    _ = try withForcedAccelerationEncoder.encode(["alpha", "beta", "gamma", "delta", "epsilon"])
                }
            )

            try runComparison(
                name: "Encode large escaped string array",
                iterations: 3,
                withoutAccelerationOperation: {
                    _ = try withoutAccelerationEncoder.encode(largeEscapedStringArray)
                },
                withDynamicAccelerationOperation: {
                    _ = try withDynamicAccelerationEncoder.encode(largeEscapedStringArray)
                },
                withForcedAccelerationOperation: {
                    _ = try withForcedAccelerationEncoder.encode(largeEscapedStringArray)
                }
            )

            try runComparison(
                name: "Encode large safe ASCII string array",
                iterations: 3,
                withoutAccelerationOperation: {
                    _ = try withoutAccelerationEncoder.encode(largeSafeASCIIStringArray)
                },
                withDynamicAccelerationOperation: {
                    _ = try withDynamicAccelerationEncoder.encode(largeSafeASCIIStringArray)
                },
                withForcedAccelerationOperation: {
                    _ = try withForcedAccelerationEncoder.encode(largeSafeASCIIStringArray)
                }
            )

            try runComparison(
                name: "Encode realistic exchange-rate feed",
                iterations: 200,
                withoutAccelerationOperation: {
                    _ = try withoutAccelerationEncoder.encode(exchangeRateFeed)
                },
                withDynamicAccelerationOperation: {
                    _ = try withDynamicAccelerationEncoder.encode(exchangeRateFeed)
                },
                withForcedAccelerationOperation: {
                    _ = try withForcedAccelerationEncoder.encode(exchangeRateFeed)
                }
            )
        }

        if benchmarkMode == "encode-feed" {
            try runComparison(
                name: "Encode realistic exchange-rate feed",
                iterations: 20,
                withoutAccelerationOperation: {
                    _ = try withoutAccelerationEncoder.encode(exchangeRateFeed)
                },
                withDynamicAccelerationOperation: {
                    _ = try withDynamicAccelerationEncoder.encode(exchangeRateFeed)
                },
                withForcedAccelerationOperation: {
                    _ = try withForcedAccelerationEncoder.encode(exchangeRateFeed)
                }
            )
        }

        if benchmarkMode == "all" || benchmarkMode == "decode" || benchmarkMode == "decode-structured" {
            try runComparison(
                name: "Decode structured payload (control)",
                iterations: 8_000,
                withoutAccelerationOperation: {
                    _ = try decoder.decode(BenchmarkPayload.self, from: encodedData)
                },
                withDynamicAccelerationOperation: {
                    _ = try dynamicDecoder.decode(BenchmarkPayload.self, from: encodedData)
                },
                withForcedAccelerationOperation: {
                    _ = try forcedDecoder.decode(BenchmarkPayload.self, from: encodedData)
                }
            )

        }

        if benchmarkMode == "all" || benchmarkMode == "decode" || benchmarkMode == "decode-feed" {
            try runComparison(
                name: "Decode realistic exchange-rate feed",
                iterations: benchmarkMode == "all" ? 200 : 20,
                withoutAccelerationOperation: {
                    _ = try decoder.decode(ExchangeRateFeed.self, from: encodedExchangeRateFeed)
                },
                withDynamicAccelerationOperation: {
                    _ = try dynamicDecoder.decode(ExchangeRateFeed.self, from: encodedExchangeRateFeed)
                },
                withForcedAccelerationOperation: {
                    _ = try forcedDecoder.decode(ExchangeRateFeed.self, from: encodedExchangeRateFeed)
                }
            )

        }

        if benchmarkMode == "all" || benchmarkMode == "decode" || benchmarkMode == "decode-headtohead" {
            try runHeadToHeadComparison(
                name: "Decode large escaped string",
                firstLabel: "ToonDecoder",
                secondLabel: "JSONDecoder",
                iterations: benchmarkMode == "all" ? 80_000 : 20_000,
                firstOperation: {
                    _ = try decoder.decode(String.self, from: toonEncodedEscapedStringData)
                },
                secondOperation: {
                    _ = try jsonDecoder.decode(String.self, from: jsonEncodedEscapedStringData)
                }
            )
        }
    }

    private static func runComparison(
        name: String,
        iterations: Int,
        withoutAccelerationOperation: @escaping () throws -> Void,
        withDynamicAccelerationOperation: @escaping () throws -> Void,
        withForcedAccelerationOperation: @escaping () throws -> Void
    ) throws {
        let withoutAccelerationResult = try run(
            BenchmarkCase(name: "\(name) (WITHOUT acceleration)", iterations: iterations, operation: withoutAccelerationOperation)
        )
        let withDynamicAccelerationResult = try run(
            BenchmarkCase(name: "\(name) (WITH dynamic acceleration)", iterations: iterations, operation: withDynamicAccelerationOperation)
        )
        let withForcedAccelerationResult = try run(
            BenchmarkCase(name: "\(name) (WITH forced acceleration)", iterations: iterations, operation: withForcedAccelerationOperation)
        )

        let comparison = BenchmarkComparison(
            name: name,
            withoutAcceleration: withoutAccelerationResult,
            withDynamicAcceleration: withDynamicAccelerationResult,
            withForcedAcceleration: withForcedAccelerationResult
        )

        print(resultLine(for: withoutAccelerationResult))
        print(resultLine(for: withDynamicAccelerationResult))
        print(resultLine(for: withForcedAccelerationResult))
        print(dynamicComparisonLine(for: comparison))
        print(forcedComparisonLine(for: comparison))
        print("")
    }

    private static func runHeadToHeadComparison(
        name: String,
        firstLabel: String,
        secondLabel: String,
        iterations: Int,
        firstOperation: @escaping () throws -> Void,
        secondOperation: @escaping () throws -> Void
    ) throws {
        let firstResult = try run(
            BenchmarkCase(name: "\(name) (\(firstLabel))", iterations: iterations, operation: firstOperation)
        )
        let secondResult = try run(
            BenchmarkCase(name: "\(name) (\(secondLabel))", iterations: iterations, operation: secondOperation)
        )

        print(resultLine(for: firstResult))
        print(resultLine(for: secondResult))

        let speedup = secondResult.totalMilliseconds / firstResult.totalMilliseconds
        let speedupText = String(format: "%.2fx", speedup)
        print("\(name) \(firstLabel) vs \(secondLabel) speedup: \(speedupText)")
        print("")
    }

    private static func run(_ benchmarkCase: BenchmarkCase) throws -> BenchmarkResult {
        let clock = ContinuousClock()
        let totalDuration = try clock.measure {
            for _ in 0..<benchmarkCase.iterations {
                try benchmarkCase.operation()
            }
        }

        return BenchmarkResult(
            name: benchmarkCase.name,
            iterations: benchmarkCase.iterations,
            totalDuration: totalDuration
        )
    }

    private static func resultLine(for result: BenchmarkResult) -> String {
        let totalMilliseconds = String(format: "%.2f", result.totalMilliseconds)
        let averageMicroseconds = String(format: "%.2f", result.averageMicroseconds)
        let operationsPerSecond = String(format: "%.0f", result.operationsPerSecond)

        return "\(result.name): total=\(totalMilliseconds) ms, average=\(averageMicroseconds) µs, throughput=\(operationsPerSecond) ops/s"
    }

    private static func dynamicComparisonLine(for comparison: BenchmarkComparison) -> String {
        let speedup = String(format: "%.2fx", comparison.dynamicSpeedup)
        return "\(comparison.name) WITH dynamic acceleration vs WITHOUT acceleration speedup: \(speedup)"
    }

    private static func forcedComparisonLine(for comparison: BenchmarkComparison) -> String {
        let speedup = String(format: "%.2fx", comparison.forcedSpeedup)
        return "\(comparison.name) WITH forced acceleration vs WITHOUT acceleration speedup: \(speedup)"
    }

    private static func makeExchangeRateFeed() -> ExchangeRateFeed {
        let quoteCurrencies = [
            "USD", "EUR", "JPY", "GBP", "AUD", "CAD", "CHF", "CNY", "INR", "MXN",
            "BRL", "SGD", "NOK", "SEK", "NZD", "ZAR", "PLN", "TRY", "HKD", "KRW",
        ]

        var entries: [ExchangeRateEntry] = []
        entries.reserveCapacity(2_000)

        for dayOffset in 0..<100 {
            let day = 1 + (dayOffset % 28)
            let date = String(format: "2026-02-%02d", day)

            for (quoteIndex, quote) in quoteCurrencies.enumerated() {
                let deterministicSeed = Double((dayOffset * 29 + quoteIndex * 97) % 10_000)
                let rate = 0.45 + (deterministicSeed / 10_000.0)

                entries.append(
                    ExchangeRateEntry(
                        date: date,
                        base: "USD",
                        quote: quote,
                        rate: rate,
                        source: "aggregated_interbank",
                        market: "spot",
                        session: "close",
                        isProvisional: (dayOffset % 7 == 0),
                        unit: 1
                    )
                )
            }
        }

        return ExchangeRateFeed(
            provider: "GlobalRates Reference Service",
            generatedAt: "2026-03-14T12:00:00Z",
            baseCurrency: "USD",
            disclaimer: "Illustrative reference rates for operational analytics and reporting.",
            tags: ["fx", "daily-close", "reference", "analytics"],
            metadata: [
                "schema": "v2",
                "region": "global",
                "timezone": "UTC",
                "license": "internal-use",
            ],
            rates: entries
        )
    }
}

@main
enum ToonBenchmarkMain {
    static func main() throws {
        try ToonBenchmarkCommand.main()
    }
}
