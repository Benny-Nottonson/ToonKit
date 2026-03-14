| Benchmark | WITHOUT acceleration (ops/s) | WITH dynamic acceleration (ops/s) | WITH forced acceleration (ops/s) | Dynamic speedup | Forced speedup |
|---|---:|---:|---:|---:|---:|
| Encode structured payload | 15,904 | 16,765 | 2,529 | 1.05x | 0.16x |
| Round-trip structured payload | 7,503 | 6,788 | 2,092 | 0.90x | 0.28x |
| Encode primitive array | 72,452 | 70,315 | 5,743 | 0.97x | 0.08x |
| Encode large escaped string array | 1 | 126 | 81 | 104.11x | 67.03x |
| Encode large safe ASCII string array | 3 | 89 | 66 | 28.12x | 20.93x |
| Encode realistic exchange-rate feed | 27 | 32 | 26 | 1.15x | 0.94x |
| Decode structured payload (control) | 14,342 | 14,365 | 14,284 | 1.00x | 1.00x |
