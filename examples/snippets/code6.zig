== mergeSignalsIfMissing handler ==

    const stream = try res.startEventStreamSync();
    defer stream.close();

    var msg = datastar.mergeSignalsIfMissing(stream);
    defer msg.end();


    // this willtry to set the following signals
    // but only if they are not already set
    const foo2 = prng.random().intRangeAtMost(u8, 1, 100);
    const bar2 = prng.random().intRangeAtMost(u8, 1, 100);

    var w = msg.writer();
    try w.print("{{ foo2: {d}, bar2: {d} }}", .{ foo2, bar2 });
