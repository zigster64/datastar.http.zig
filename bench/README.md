# Benchmarking Tools

This sub-dir holds a simple Zig, Go and Bun example that does a simple thing :

- expose a / endpoint
- Take a 100kb sample data file and output it through the SSE patchElements conversion
- Hit the endpoint with a browser, observe they all give the same output, and show time spend in the handler
- Hit it with a bench tool such as `wrk -t12 -c400 -d10s http://localhost:8090/` to test total throughput

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

# Makefile

You can use the Makefile to do 

`make` - will build binaries in the current dir for bench-zig, bench-go

`make clean` - will cleanup the env
