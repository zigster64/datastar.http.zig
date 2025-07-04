== removeFragments handler ===

    const stream = try res.startEventStreamSync();
    defer stream.close();

    try datastar.removeFragments(stream, "#remove-me");
