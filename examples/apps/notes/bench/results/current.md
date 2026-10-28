# Notes loopback benchmark

Machine: macOS-15.7.9-arm64-arm-64bit-Mach-O
64 keep-alive clients, 10 s, median of 5 runs.

| Server | Requests/s | p50 us | p99 us | x2c/server |
| --- | ---: | ---: | ---: | ---: |
| x2c | 42455.1 | 1472.0 | 5502.0 | 1.000 |
| c | 203584.8 | 312.0 | 434.0 | 0.209 |

C and Go return fixed JSON. x2c performs note lookup, copies, and JSON encoding.
The ratios compare these workloads, not equivalent implementations.

Go baseline pending: Go toolchain is not installed on the measurement host.
