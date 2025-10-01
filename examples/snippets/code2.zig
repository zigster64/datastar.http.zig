== text/html handler ==

var sse = try datastar.NewSSE(req, res);
defer sse.close();

var w = sse.patchElements(.{});
try w.print(
    \\<p id="mf-patch">This is update number {d}</p>
, .{getCountAndIncrement()});
