== mergeFragments  Handler ==

    // get the SSE stream
    const stream = try res.startEventStreamSync();
    defer stream.close();

    // create a MergeFragments writer
    var msg = datastar.mergeFragments(stream);
    defer msg.end();
    var w = msg.writer();

    // Update the #mf-merge element
    try w.print(
        "<p id='mf-merge'&gt;This is update number {d}></p>",
        .{getCountAndIncrement()});
