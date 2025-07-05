== executeScript handler ==

    const sample = req.param("sample").?;
    const sample_id = try std.fmt.parseInt(u8, sample, 10);

    const stream = try res.startEventStreamSync();
    defer stream.close();

    var msg = datastar.executeScript(stream);
    defer msg.end();

    const script_data = if (sample_id == 1) "console.log('Running from executescript!');" else "const parent = document.querySelector('#executescript-card');\n console.log(parent.outerHTML);";

    var w = msg.writer();
    try w.writeAll(script_data);
