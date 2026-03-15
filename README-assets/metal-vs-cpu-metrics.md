Benchmarks below were collected on 2026-03-15 from the current macOS workspace environment after fixing the runtime Metal shader compilation regression.
The benchmark binary reported `ToonEncoder.isMetalAccelerationAvailable == true` and `ToonDecoder.isMetalAccelerationAvailable == true` during these runs.

| Benchmark | WITHOUT acceleration (ops/s) | WITH dynamic acceleration (ops/s) | WITH forced acceleration (ops/s) | Dynamic speedup | Forced speedup |
|---|---:|---:|---:|---:|---:|
| Encode structured payload | 17,066 | 16,748 | 2,376 | 0.98x | 0.14x |
| Round-trip structured payload | 7,214 | 7,130 | 2,036 | 0.99x | 0.28x |
| Encode primitive array | 70,131 | 69,282 | 5,504 | 0.99x | 0.08x |
| Encode large escaped string array | 1 | 128 | 82 | 103.94x | 67.01x |
| Encode large safe ASCII string array | 3 | 89 | 61 | 28.14x | 19.42x |
| Encode realistic exchange-rate feed | 28 | 32 | 27 | 1.16x | 0.98x |
| Decode structured payload (control) | 13,739 | 13,739 | 4,138 | 1.00x | 0.30x |
| Decode realistic exchange-rate feed | 30 | 42 | 42 | 1.40x | 1.41x |

Head-to-head decode reference:

| Benchmark | Toon ops/s | JSON ops/s | Toon vs JSON |
|---|---:|---:|---:|
| Decode large escaped string | 2,291 | 28,921 | 0.08x |

Graph:

![Metal vs CPU speedup graph](metal-vs-cpu-speedup.svg)
