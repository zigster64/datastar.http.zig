fn mergeFragments(
    _: *httpz.Request,
    res: *httpz.Response,
) !void {
    // get the SSE stream
    const stream = try res.startEventStreamSync();
    defer stream.close();

    // create a MergeFragments writer
    var msg = datastar.mergeFragments(stream);
    defer msg.end();
    var w = msg.writer();

    // Update the #mf-merge element by outputting to the writer
    try w.print("<p id='mf-merge'&gt;This is update number {d}></p>", .{update_count});

    // increment the Counter
    incUpdateCount();
}
