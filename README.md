# ToonKit

A Swift implementation of the [TOON](https://github.com/toon-format/spec) (Token-Oriented Object Notation) format, designed for use in iOS, macOS, watchOS, tvOS, and visionOS apps.

TOON reduces token usage by **30–60% compared to JSON**, making it ideal for LLM context windows. It uses YAML-style indentation for structure, inline arrays with declared lengths, and CSV-like tabular rows for uniform arrays of objects.

## Installation

Add ToonKit to your project via Swift Package Manager:

```swift
// In Package.swift:
.package(url: "https://github.com/Benny-Nottonson/ToonKit.git", from: "1.0.0")
```

Or in Xcode: **File → Add Packages…** and enter the repository URL.

## Quick Start

```swift
import Toon

struct User: Codable, Equatable {
    let id: Int
    let name: String
    let tags: [String]
}

let user = User(id: 1, name: "Ada Lovelace", tags: ["coding", "maths"])

// Encode to TOON
let encoder = ToonEncoder()
let data = try encoder.encode(user)
// id: 1
// name: Ada Lovelace
// tags[2]: coding,maths

// Decode from TOON
let decoder = ToonDecoder()
let decoded = try decoder.decode(User.self, from: data)
assert(decoded == user)
```

## Format at a Glance

```toon
# Scalar key-value pairs
name: Ada Lovelace
age: 36
active: true
score: 9.8
email: null

# Primitive arrays (inline, with count header)
tags[3]: coding,maths,logic

# Nested objects (indentation = structure)
address:
  street: 1 Math Lane
  city: London

# Tabular arrays – uniform arrays of objects (like CSV)
orders[2]{id,amount,status}:
  1001,49.99,shipped
  1002,12.50,pending
```

## Encoder Configuration

```swift
let encoder = ToonEncoder()

// Indentation size (spaces). Default: 2
encoder.indent = 4

// Delimiter for arrays and tabular rows. Default: .comma
encoder.delimiter = .tab    // or .comma, .pipe

// How to handle -0.0. Default: .normalize
encoder.negativeZeroStrategy = .preserve   // keep -0; or .normalize (encode as 0)

// How to handle nan, inf, -inf. Default: .null
encoder.nonFiniteFloatStrategy = .null
// or: .throw
// or: .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")

// Collapse single-child nested objects into dotted keys. Default: .disabled
encoder.keyFolding = .safe
// {a: {b: {c: 1}}} → "a.b.c: 1"

// Encoding limits
encoder.limits = ToonEncoder.Limits(maxDepth: 64)

// Optional Metal backend (off by default)
encoder.acceleration = .metal(minimumStringByteCount: 16_384)

// Force Metal for explicit A/B benchmarking
encoder.acceleration = .metalForced(minimumStringByteCount: 1)

// Runtime visibility
print(ToonEncoder.isMetalAccelerationAvailable) // Metal pipeline can be created
print(ToonEncoder.isMetalAccelerationEnabled)   // Adaptive gate decided it is faster
```

### Metal Backend Behavior

- Metal acceleration is **optional** and **disabled by default**.
- ToonKit uses an adaptive speed gate and enables Metal only when it measures a significant speedup.
- If Metal is slower on the current machine/workload, ToonKit automatically keeps the CPU path.
- When acceleration is enabled but Metal is not selected, ToonKit uses a large-batch parallel CPU fallback to preserve throughput on heavy string workloads.
- `metalForced` mode bypasses adaptive gating for explicit WITH-vs-WITHOUT benchmark comparisons.
- Current accelerated scope is batched string serialization workloads.

## Decoder Configuration

```swift
let decoder = ToonDecoder()

// Dotted-key path expansion. Default: .automatic
decoder.expandPaths = .automatic   // expand where unambiguous; keep literal otherwise
// or: .safe      – expand and throw on collision
// or: .disabled  – never expand; treat dots as literal key characters

// Decoding limits (protects against malicious or malformed input)
decoder.limits = ToonDecoder.Limits(
    maxInputSize: 10 * 1024 * 1024,   // 10 MB
    maxDepth: 32,
    maxObjectKeys: 10_000,
    maxArrayLength: 100_000
)
```

## Foundation Types

`Date`, `URL`, and `Data` are handled transparently:

| Swift type | TOON representation              |
|------------|----------------------------------|
| `Date`     | ISO 8601 string (`2023-11-14T22:13:20Z`) |
| `URL`      | Bare URL string (unquoted if safe) |
| `Data`     | Base64-encoded string            |

```swift
struct Asset: Codable {
    let url: URL
    let createdAt: Date
    let thumbnail: Data
}
```

## Error Handling

Decoding errors are represented by `ToonDecodingError`:

```swift
do {
    let value = try decoder.decode(MyType.self, from: data)
} catch let error as ToonDecodingError {
    switch error {
    case .invalidFormat(let msg):         print("Parse error:", msg)
    case .typeMismatch(let exp, let got): print("Expected \(exp), got \(got)")
    case .keyNotFound(let key):           print("Missing key:", key)
    case .inputTooLarge(let size, let limit): print("Input too large")
    default: print("Decoding error:", error)
    }
}
```

## Package Structure

```
Sources/Toon/
├── Toon.swift                          # Module namespace + spec version
├── Value.swift                         # Internal intermediate representation
├── Errors.swift                        # Public ToonDecodingError
├── Encoder.swift                       # Public ToonEncoder
├── Decoder.swift                       # Public ToonDecoder
└── Internal/
    ├── Shared/
    │   ├── StringHelpers.swift         # String escaping and quoting utilities
    │   ├── NumericDecoding.swift       # Integer bounds-checking helpers
    │   ├── FoundationTypes.swift       # Date/URL/Data encode + decode
    │   └── CodingKeyHelpers.swift      # IndexedCodingKey and related types
    ├── Metal/
    │   ├── MetalStringLiteralEncoder.swift # Metal backend selection + adaptive gate
    │   ├── MetalStringAccelerator.swift    # Metal pipeline + GPU dispatch
    │   ├── MetalStringAnalyzer.swift       # CPU-side analysis of GPU flags
    │   └── Shaders/
    │       ├── ToonStringClassifyKernels.metal # Character classification kernels
    │       └── ToonStringEncodeKernels.metal   # Range encoding kernels
    ├── Parsing/
    │   ├── Parser.swift                # Core TOON text parser
    │   ├── ArrayParsing.swift          # Array and tabular format parsing
    │   └── PathExpansion.swift         # Dotted key path expansion
    ├── Serialization/
    │   ├── Serializer.swift            # Core serializer + object encoding
    │   ├── ArraySerialization.swift    # Array format encoding
    │   └── PrimitiveSerialization.swift# Primitive encoding + number formatting
    └── Codable/
        ├── EncoderImpl.swift           # Swift.Encoder implementation
        ├── EncodingContainers.swift    # Keyed/Unkeyed/SingleValue encoding containers
        ├── DecoderImpl.swift           # Swift.Decoder implementation
        └── DecodingContainers.swift    # Keyed/Unkeyed/SingleValue decoding containers
```

## Benchmarks

Run the built-in benchmark executable:

```bash
swift run ToonBenchmark
```

The benchmark prints total time, average time, and throughput with explicit three-mode lines per workload:

- **WITHOUT acceleration**
- **WITH dynamic acceleration** (uses Metal only when measured faster)
- **WITH forced acceleration** (forces Metal path for explicit A/B examples)

### WITH Metal vs WITHOUT Metal Results

![WITH Metal vs WITHOUT Metal graph](README-assets/metal-vs-cpu-speedup.svg)

| Benchmark | WITHOUT acceleration (ops/s) | WITH dynamic acceleration (ops/s) | WITH forced acceleration (ops/s) | Dynamic speedup | Forced speedup |
|---|---:|---:|---:|---:|---:|
| Encode structured payload | 15,904 | 16,765 | 2,529 | 1.05x | 0.16x |
| Round-trip structured payload | 7,503 | 6,788 | 2,092 | 0.90x | 0.28x |
| Encode primitive array | 72,452 | 70,315 | 5,743 | 0.97x | 0.08x |
| Encode large escaped string array | 1 | 126 | 81 | 104.11x | 67.03x |
| Encode large safe ASCII string array | 3 | 89 | 66 | 28.12x | 20.93x |
| Encode realistic exchange-rate feed | 27 | 32 | 26 | 1.15x | 0.94x |
| Decode structured payload (control) | 14,342 | 14,365 | 14,284 | 1.00x | 1.00x |

Measured on macOS arm64 (`swift run ToonBenchmark`), March 14, 2026.

## Why This Is Useful Beyond TOON

ToonKit’s acceleration layer is also useful as a production-ready string serialization backend, independent of TOON-specific syntax savings:

- It provides an adaptive CPU/GPU execution model for high-volume ASCII string escaping and quoting workloads.
- It demonstrates practical Metal integration patterns for backend-style data pipelines on Apple Silicon.
- It improves throughput for large batched string emission, which is valuable for logging, event streams, model I/O staging, and wire-format preparation.
- It includes safe fallback behavior (dynamic gate + parallel CPU path) so workloads that do not benefit from GPU avoid unnecessary overhead.
- It offers forced acceleration mode for deterministic A/B measurement and tuning in CI/performance harnesses.

## Platform Requirements

| Platform   | Minimum Version |
|------------|----------------|
| iOS        | 16.0           |
| macOS      | 13.0           |
| watchOS    | 9.0            |
| tvOS       | 16.0           |
| visionOS   | 1.0            |

Swift 5.9+ required.

## Specification

Implements **TOON specification version 3.0** (2025-11-24).  
Full specification: https://github.com/toon-format/spec

## License

MIT — see [LICENSE](LICENSE) for details.
