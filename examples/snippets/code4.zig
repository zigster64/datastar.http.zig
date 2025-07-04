== upsertAttributes handler ==

    const stream = try res.startEventStreamSync();
    defer stream.close();

    var msg = datastar.upsertAttributes(stream, "#color-change");
    defer msg.end();

    // create a random color
    var w = msg.writer();
    const color = prng.random().intRangeAtMost(u8, 0, 9);
    const border = prng.random().intRangeAtMost(u8, 1, 3);

    try w.print(
        \\<div class="bg-violet-{d}00 border-{d} border-yellow-{d}00">
    , .{ color, std.math.pow(u8, 2, border), 9 - color });
