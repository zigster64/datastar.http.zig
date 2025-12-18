== patchSignals handler ==


var sse = try datastar.NewSSE(req, res);

const foo = prng.random().intRangeAtMost(u8, 0, 255);
const bar = prng.random().intRangeAtMost(u8, 0, 255);

try sse.patchSignals(.{
    .foo = foo,
    .bar = bar,
}, .{}, .{});

res.body = sse.body();
