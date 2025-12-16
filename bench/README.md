# Benchmarking Tools

This sub-dir holds a simple Zig, Go and Bun example that does a simple thing :

- expose a / endpoint that outputs a sample 100k file
- expose a /sse endpoint that outputs a sample 20k file, but passes it through SSE / Datastar conversion
- Hit the endpoint with a browser, observe they all give the same output, and show time spend in the handler
- Hit it with a bench tool such as `wrk -t12 -c400 -d10s http://localhost:8090/sse` to test total throughput

# Zig Test

```
zig build -Doptimize=ReleaseFast
./zig-out/bin/bench
```
Runs a Zig test server on 8090

# Go Test

```
go build .
./bench
```
Runs a Go test server on 8091

# Bun Test

```
bun bench.ts
```
Runs a TS test server on 8092

# Rust / Axum Test

```
cargo build --release
./target/release/bench-rust
```

# Makefile

You can use the Makefile to do 

`make` - will build binaries in the current dir for bench-zig, bench-go

`make clean` - will cleanup the env

# Results

### Benchmark Results

Tests were run using `wrk` with 12 threads and 400 connections for 20 seconds.

Plain HTML payloads are 100k of lorem HTML

SSE payloads are 20k of lorem HTML, converted to SSE event streams

RAM size = peak RAM usage according to Activity Monitor, at the end of the SSE test

| Language | Test Case | Requests/sec | Latency (Avg) | Transfer/sec | Binary/RAM Size |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Zig** | Plain HTML | 39,654 | 5.50ms | **5.61 GB** | 533,672 |
| **Zig** | **Datastar SSE** | **72,756** | **4.26ms** | 1.73 GB | 12.7 MB  |
| | | | | | |
| **Rust** | Plain HTML | 39,040 | 5.35ms | **5.53 GB** | 1,845,888 |
| **Rust** | **Datastar SSE** | **74,327** | **3.19** | 1.57 GB | 14.2 MB |
| | | | | | |
| **Go** | Plain HTML | 23,730 | 11.89ms | 3.36 GB | 7,995,922 |
| **Go** | Datastar SSE | 27,788 | 11.49ms | 678.12 MB | 28.3 MB |
| | | | | | |
| **Bun** | Plain HTML | 28,667 | 8.30ms | 4.06 GB | n/a |
| **Bun** | Datastar SSE | 20,828 | 11.44ms | 508.25 MB | 58.4 MB |
| | | | | | |
| **Bun** | Plain HTML (w/ Log) | 12,664 | 18.81ms | 1.79 GB | n/a |
| **Bun** | Datastar SSE (w/ Log) | 9,221 | 25.81ms | 225.01 MB | 58.6 MB |
