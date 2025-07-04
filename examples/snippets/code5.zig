== mergeSignals handler ==

    const stream = try res.startEventStreamSync();
    defer stream.close();

    var msg = datastar.mergeSignals(stream);
    defer msg.end();

    // this will set the following signals
    const foo = prng.random().intRangeAtMost(u8, 0, 255);
    const bar = prng.random().intRangeAtMost(u8, 0, 255);

    var w = msg.writer();
    try w.print("{{ foo1: {d}, bar1: {d} }}", .{ foo, bar });
