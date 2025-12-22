== svgMorph handler ==

const SVGMorphOptions = struct {
    svgMorph: usize = 1,
};
const opt = blk: {
    break :blk datastar.readSignals(SVGMorphOptions, req) catch break :blk SVGMorphOptions{ .svgMorph = 5 };
};
var sse = try datastar.NewSSESync(req, res);
defer sse.close(res);

for (1..opt.svgMorph + 1) |_| {
    try sse.patchElementsFmt(
        \\<svg id="svg-stage" class="w-full h-full" viewBox="0 0 200 200" xmlns="http://www.w3.org/2000/svg">
        \\  <circle id="svg-circle" cx="{}" cy="{}" r="{}" class="fill-red-500 transition-all duration-200" />
        \\  <rect id="svg-square" x="{}" y="{}" width="{}" height="80" class="fill-green-500 transition-all duration-200" />
        \\  <polygon id="svg-triangle" points="{},{} {},{} {},{}" class="fill-blue-500 transition-all duration-200" />
        \\</svg>
    ,
        .{
            // cicrle x y r
            prng.random().intRangeAtMost(u8, 10, 100),
            prng.random().intRangeAtMost(u8, 10, 100),
            prng.random().intRangeAtMost(u8, 10, 80),
            // rectangle x y width
            prng.random().intRangeAtMost(u8, 10, 100),
            prng.random().intRangeAtMost(u8, 10, 100),
            prng.random().intRangeAtMost(u8, 10, 80),
            // triangle random points
            prng.random().intRangeAtMost(u16, 50, 300),
            prng.random().intRangeAtMost(u16, 50, 300),
            prng.random().intRangeAtMost(u16, 50, 300),
            prng.random().intRangeAtMost(u16, 50, 300),
            prng.random().intRangeAtMost(u16, 50, 300),
            prng.random().intRangeAtMost(u16, 50, 300),
        },
        .{ .namespace = .svg },
    );
    try sse.writeAll();
    std.Thread.sleep(std.time.ns_per_ms * 100);
}
