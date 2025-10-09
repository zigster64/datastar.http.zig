== patchElements handler ==

var sse = try datastar.NewSSE(req, res);
defer sse.close();

try sse.patchElementsFmt(
    \\<p id="mf-patch">This is update number {d}</p>
,
    .{getCountAndIncrement()},
    .{},
);
