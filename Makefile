build:
	zig build -freference-trace=11

clean:
	rm -rf .zig-cache zig-out
