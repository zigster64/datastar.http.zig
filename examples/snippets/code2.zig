== patchElementsOpts handler ==

    const opts = struct {
        morph: []const u8,
    };

    const signals = try datastar.readSignals(opts, req);
    // jump out if we didnt set anything
    if (signals.morph.len < 1) {
        return;
    }
    // these are short lived updates so we close the request as soon as its done
    const stream = try res.startEventStreamSync();
    defer stream.close();

    // read the signals to work out which options to set, checking the name of the
    // option vs the enum values, and add them relative to the mf-patch-opt item
    var patch_mode: datastar.PatchMode = .outer;
    for (std.enums.values(datastar.PatchMode)) |mt| {
        if (std.mem.eql(u8, @tagName(mt), signals.morph)) {
            patch_mode = mt;
            break; // can only have 1 patch type
        }
    }

    if (patch_mode == .outer or patch_mode == .inner) {
        return; // dont do morphs - its not relevant to this demo card
    }

    var msg = datastar.patchElementsOpt(stream, .{
        .selector = "#mf-patch-opts",
        .mode = patch_mode,
    });
    defer msg.end();

    var w = msg.writer();
    switch (patch_mode) {
        .replace => {
            try w.writeAll(
                \\<p id="mf-patch-opts" class="border-4 border-error">Complete Replacement of the OUTER HTML</p>
            );
        },
        else => {
            try w.print(
                \\<p>This is update number {d}</p>
            , .{getCountAndIncrement()});
        },
    }
