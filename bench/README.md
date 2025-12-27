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
Runs a Rust/Axum server on 8093

# Makefile

You can use the Makefile to do 

`make` - will build binaries in the current dir for bench-zig, bench-go

`make clean` - will cleanup the env

# Results

### Benchmark Results

Tests were run using `wrk` with 12 threads and 400 connections for 20 seconds.

payloads are 100k of lorem HTML

Endpoints
/ = show 100k index page
/log = show 100k index page, and log each request
/sse = convert 100k index page to SSE stream on the fly, and log each request

Note that for Rust and Zig, adding logging to the handler has no measurable effect, but its included here for both Go and Bun, because they both have a bit of overhead in printing to logs for each handler.

RAM size = peak RAM usage according to Activity Monitor, at the end of the SSE test

Note the Zig 0.16 Numbers are from the https://github.com/zigster64/datastar.zig SDK repo,
which uses a much simpler HTTP server based on the current stdlib, and Io.Threaded implementation.

Would expect the Io.Evented stdlib server to eventually be a bit better than this.

| Language | Test Case | Requests/sec | Latency (Avg) | Transfer/sec | Binary/RAM Size |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Zig** | Plain HTML | 39,654 | 5.50ms | **5.61 GB** | 533,672 |
| **Zig** | **Datastar SSE** 100k payload | **23,777** | **15.99ms** | 4.12 GB | 12.7 MB  |
| **Zig** | SSE % performance | |  | 73 % | |
| | | | | | |
| **Zig 0.16** | Plain HTML | 39,654 | 5.50ms | **5.61 GB** | 533,672 |
| **Zig 0.16** | **Datastar SSE** 100k payload | **23,777** | **15.99ms** | 4.12 GB | 12.7 MB  |
| **Zig 0.16** | **Datastar SSE** 20k payload | **72,756** | **4.26ms** | 1.73 GB | 12.7 MB  |
| **Zig 0.16** | SSE % performance | |  | 73 % | |
| | | | | | |
| **Rust** | Plain HTML | 38,201 | 5.13ms | **5.41 GB** | 1,845,936 |
| **Rust** | **Datastar SSE** 100k payload | **20,943** | **11.43ms** | 3.63 GB | 40.2 MB |
| **Rust** | SSE % performance | |  | 67 % | |
| | | | | | |
| **Go** | Plain HTML (no log)| 30,484 | 8.76ms | 4.32 GB | 7,995,922 |
| **Go** | Plain HTML | 23,730 | 11.89ms | 3.36 GB | 7,995,922 |
| **Go** | Datastar SSE 100k payload | 9,758 | 33.72ms | 1.69 GB | 43.8 MB |
| **Go** | SSE % performance | |  | 50 % | |
| | | | | | |
| **Bun** | Plain HTML (no Log) | 28,667 | 8.30ms | 4.06 GB | n/a |
| **Bun** | Plain HTML | 12,664 | 18.81ms | 1.79 GB | n/a |
| **Bun** | Datastar SSE (100k w/ Log) | 3,733 | 63.7ms | 662.85 MB | 32.3 MB |
| **Bun** | SSE % performance | |  | 36 % | |
