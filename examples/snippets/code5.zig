== patchSignals handler ==

var sse = try datastar.NewSSE(req, res);
defer sse.close();

var w = sse.patchSignals(.{});

// this will set the following signals
const foo = prng.random().intRangeAtMost(u8, 0, 255);
const bar = prng.random().intRangeAtMost(u8, 0, 255);
try w.print("{{ foo: {d}, bar: {d} }}", .{ foo, bar });
