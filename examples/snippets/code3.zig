== patchSignals handler ==

    // these are short lived updates so we close the request as soon as its done
    const stream = try res.startEventStreamSync();
    defer stream.close();

    var msg = datastar.patchSignals(stream);
    defer msg.end();

    // create a random color

    var w = msg.writer();

    // this will set the following signals
    const foo = prng.random().intRangeAtMost(u8, 0, 255);
    const bar = prng.random().intRangeAtMost(u8, 0, 255);
    try w.print("{{ foo: {d}, bar: {d} }}", .{ foo, bar });
