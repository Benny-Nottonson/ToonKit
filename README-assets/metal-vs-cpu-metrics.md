Benchmarks below were collected on 2026-03-15 from the current macOS workspace environment.
The benchmark binary reported `ToonEncoder.isMetalAccelerationAvailable == true` and `ToonDecoder.isMetalAccelerationAvailable == true` during these runs.

| Benchmark | WITHOUT acceleration (ops/s) | WITH dynamic acceleration (ops/s) | WITH forced acceleration (ops/s) | Dynamic speedup | Forced speedup |
|---|---:|---:|---:|---:|---:|
| Encode structured payload | 17,149 | 17,218 | 2,664 | 1.00x | 0.16x |
| Round-trip structured payload | 7,574 | 7,545 | 2,082 | 1.00x | 0.27x |
| Encode primitive array | 71,640 | 71,919 | 5,882 | 1.00x | 0.08x |
| Encode large escaped string array | 1 | 127 | 87 | 107.98x | 73.89x |
| Encode large safe ASCII string array | 3 | 93 | 57 | 29.10x | 17.92x |
| Encode realistic exchange-rate feed | 28 | 32 | 29 | 1.17x | 1.05x |
| Decode structured payload (control) | 13,934 | 13,983 | 4,303 | 1.00x | 0.31x |
| Decode realistic exchange-rate feed | 33 | 42 | 42 | 1.27x | 1.27x |

Head-to-head decode reference:

| Benchmark | Toon ops/s | JSON ops/s | Toon vs JSON |
|---|---:|---:|---:|
| Decode large escaped string | 69,937 | 29,918 | 2.34x |
| Decode large safe ASCII string | 29,638 | 171,360 | 0.17x |

Graph:

![Metal vs CPU speedup graph](metal-vs-cpu-speedup.svg)
