== patchElements handler ==

var sse = try datastar.NewSSE(req, res);

try sse.patchElementsFmt(
    \\<p id="mf-patch">This is update number {d}</p>
,
    .{getCountAndIncrement()},
    .{},
);

res.body = sse.body();
