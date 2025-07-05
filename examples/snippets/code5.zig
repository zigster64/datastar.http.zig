== patchSignalsRemove handler ==

    // these are short lived updates so we close the request as soon as its done
    const stream = try res.startEventStreamSync();
    defer stream.close();

    var msg = datastar.patchSignals(stream);
    defer msg.end();

    // this will set the following signals
    var w = msg.writer();
    try w.writeAll("{ foo: null, bar: null }");
