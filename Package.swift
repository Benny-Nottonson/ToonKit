// swift-tools-version: 5.9

import PackageDescription

/// The Toon package provides `ToonEncoder` and `ToonDecoder` for serializing and
/// deserializing Swift `Codable` types to the TOON format.
///
/// TOON (Token-Oriented Object Notation) is a compact, human-readable data format
/// designed for use in LLM contexts. It achieves 30–60% token reduction compared
/// to JSON by combining YAML-style indentation with CSV-style tabular arrays.
///
/// This implementation conforms to TOON specification version 3.0.
let package = Package(
    name: "Toon",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .watchOS(.v9),
        .tvOS(.v16),
        .visionOS(.v1),
    ],
    products: [
        /// The primary library product. Import as `import Toon`.
        .library(name: "Toon", targets: ["Toon"]),
        .executable(name: "ToonBenchmark", targets: ["ToonBenchmark"]),
    ],
    targets: [
        .target(
            name: "Toon",
            path: "Sources/Toon",
            resources: [
                .copy("Internal/Metal/Shaders/ToonStringClassifyKernels.metal"),
                .copy("Internal/Metal/Shaders/ToonStringEncodeKernels.metal"),
            ]
        ),
        .executableTarget(
            name: "ToonBenchmark",
            dependencies: ["Toon"],
            path: "Benchmarks/ToonBenchmark"
        ),
        .testTarget(
            name: "ToonTests",
            dependencies: ["Toon"],
            path: "Tests/ToonTests"
        ),
    ]
)
