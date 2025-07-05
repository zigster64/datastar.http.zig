== patchElements handler ==

    // these are short lived updates so we close the request as soon as its done
    const stream = try res.startEventStreamSync();
    defer stream.close();

    var msg = datastar.patchElements(stream);
    defer msg.end();

    var w = msg.writer();
    try w.print(
        \\<p id="mf-patch">This is update number {d}</p>
    , .{getCountAndIncrement()});
