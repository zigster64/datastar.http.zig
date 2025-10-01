== patchSignalsOnlyIfMissing handler ==

var sse = try datastar.NewSSE(req, res);
defer sse.close();

var w = sse.patchSignals(.{ .only_if_missing = true });

// this will set the following signals
const foo = prng.random().intRangeAtMost(u8, 1, 100);
const bar = prng.random().intRangeAtMost(u8, 1, 100);
try w.print("{{ foo: {d}, bar: {d} }}", .{ foo, bar }); // first will update only
