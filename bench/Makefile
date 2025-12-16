all:
	@echo Timing of Building Binaries ...
	time zig build -Doptimize=ReleaseFast -freference-trace=6
	time go build
	@mv zig-out/bin/bench bench-zig
	@mv bench bench-go
	time cargo build --release
	@mv target/release/bench-rust .
	@echo
	@echo Results from build ...
	@ls -ltra bench-go bench-zig bench-rust bench.ts
	@echo
	@echo "To run Zig  : ./bench-zig"
	@echo "To run Rust : ./bench-rs"
	@echo "To run Go   : ./bench-go"
	@echo "To run Bun  : bun bench.ts"

clean:
	@echo Cleaning Up ...
	rm -rf zig-out .zig-cache bench-go bench-zig bench-rust target

