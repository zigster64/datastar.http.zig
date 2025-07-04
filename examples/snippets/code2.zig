== mergeFragmentsOpts handler ==

    const opts = struct {
        morph: []const u8,
    };

    const signals = try datastar.readSignals(opts, req);
    // jump out if we didnt set anything
    if (signals.morph.len < 1) {
        return;
    }
    const stream = try res.startEventStreamSync();
    defer stream.close();

    // work out which option we selected
    var merge_type: datastar.MergeType = .morph;
    for (std.enums.values(datastar.MergeType)) |mt| {
        if (std.mem.eql(u8, @tagName(mt), signals.morph)) {
            merge_type = mt;
            break; // can only have 1 merge type
        }
    }

    if (merge_type == .morph) {
        return; // dont do morphs
    }

    var msg = datastar.mergeFragmentsOpt(stream, .{
        .selector = "#mf-merge-opts",
        .merge_type = merge_type,
    });
    defer msg.end();

    var w = msg.writer();
    switch (merge_type) {
        .outer => {
            try w.writeAll(
                \\<p id="mf-merge-opts" class="border-4 border-error">Complete Replacement of the OUTER HTML</p>
            );
        },
        else => {
            try w.print(
                \\<p>This is update number {d}</p>
            , .{getCountAndIncrement()});
        },
    }

