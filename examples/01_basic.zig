const std = @import("std");
const httpz = @import("httpz");
const logz = @import("logz");
const datastar = @import("datastar.httpz");
const Allocator = std.mem.Allocator;

const PORT = 8081;

var update_count: usize = 1;
var update_mutex: std.Thread.Mutex = .{};

var prng = std.Random.DefaultPrng.init(0);

fn getCountAndIncrement() usize {
    update_mutex.lock();
    defer {
        update_count += 1;
        update_mutex.unlock();
    }
    return update_count;
}

// This example demonstrates basic DataStar operations
// MergeFragments / RemoveFragments
// MergeSignals / RemoveSignals
// ExecuteScript

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var server = try httpz.Server(void).init(allocator, .{
        .port = PORT,
        .address = "0.0.0.0",
    }, {});
    defer {
        // clean shutdown
        server.stop();
        server.deinit();
    }

    // initialize a logging pool
    try logz.setup(allocator, .{
        .level = .Info,
        .pool_size = 100,
        .buffer_size = 4096,
        .large_buffer_count = 8,
        .large_buffer_size = 16384,
        .output = .stdout,
        .encoding = .logfmt,
    });
    defer logz.deinit();

    var router = try server.router(.{});

    router.get("/", index, .{});
    router.get("/merge", mergeFragments, .{});
    router.get("/merge/opts", mergeFragmentsOpts, .{});
    router.get("/merge/opts/reset", mergeFragmentsOptsReset, .{});
    router.get("/remove", removeFragments, .{});
    router.get("/remove/restore", removeFragmentsRestore, .{});
    router.get("/upsert/attributes", upsertAttributes, .{});
    router.get("/merge/signals", mergeSignals, .{});
    router.get("/merge/signals/onlymissing", mergeSignalsOnlyIfMissing, .{});
    router.get("/merge/signals/remove", removeSignals, .{});

    router.get("/code/:snip", code, .{});

    std.debug.print("listening http://localhost:{d}/\n", .{PORT});
    std.debug.print("... or any other IP address pointing to this machine\n", .{});
    try server.listen();
}

fn index(_: *httpz.Request, res: *httpz.Response) !void {
    res.body = @embedFile("01_index.html");
}

// create a mergeFragments stream, which will write commands over the SSE connection
// to update parts of the DOM. It will look for the DOM with the matching ID in the default case
//
// NOTE - once we have created a DataStar 'Message' of whatever type, we then get a writer
// from it, and from there we can freely print to to.  The writer will auto-inject all the
// protocol parts to split it into lines and describe each fragment by magic.
fn mergeFragments(_: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();

    // these are short lived updates so we close the request as soon as its done
    const stream = try res.startEventStreamSync();
    defer stream.close();

    var msg = datastar.mergeFragments(stream);
    defer msg.end();

    var w = msg.writer();
    try w.print(
        \\<p id="mf-merge">This is update number {d}</p>
    , .{getCountAndIncrement()});

    const t2 = std.time.microTimestamp();
    logz.info().string("event", "mergeFragments").int("elapsed (μs)", t2 - t1).log();
}

// create a mergeFragments stream, which will write commands over the SSE connection
// to update parts of the DOM. It will look for the DOM with the matching ID in the default case
//
// Use a variety of merge options for this one
fn mergeFragmentsOpts(req: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();

    const opts = struct {
        morph: []const u8,
        foo1: []const u8,
        bar1: []const u8,
        foo2: []const u8,
        bar2: []const u8,
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
    // option vs the enum values, and add them relative to the mf-merge-opt item
    var merge_type: datastar.MergeType = .morph;
    for (std.enums.values(datastar.MergeType)) |mt| {
        if (std.mem.eql(u8, @tagName(mt), signals.morph)) {
            merge_type = mt;
            break; // can only have 1 merge type
        }
    }

    if (merge_type == .morph) {
        return; // dont do morphs - its not relevant to this demo card
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

    const t2 = std.time.microTimestamp();
    logz.info().string("event", "mergeFragmentsOpts").int("elapsed (μs)", t2 - t1).log();
}

// Just reset the options form if it gets ugly
fn mergeFragmentsOptsReset(_: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();

    // these are short lived updates so we close the request as soon as its done
    const stream = try res.startEventStreamSync();
    defer stream.close();

    // read the signals to work out which options to set, checking the name of the
    // option vs the enum values, and add them relative to the mf-merge-opt item
    var msg = datastar.mergeFragmentsOpt(stream, .{
        .selector = "#merge-fragment-card",
    });
    defer msg.end();

    var w = msg.writer();
    try w.writeAll(@embedFile("01_index_opts.html"));

    const t2 = std.time.microTimestamp();
    logz.info().string("event", "mergeFragmentsOptsReset").int("elapsed (μs)", t2 - t1).log();
}

fn removeFragments(_: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();

    // these are short lived updates so we close the request as soon as its done
    const stream = try res.startEventStreamSync();
    defer stream.close();

    try datastar.removeFragments(stream, "#remove-me");

    // thats all we need to delete an element
    // now some fancy code to let up reset the form

    var msg = datastar.mergeFragmentsOpt(stream, .{
        .selector = "#rm-card",
        .merge_type = .append,
    });
    defer msg.end();

    var w = msg.writer();
    try w.writeAll(
        \\<button id="rm-restore" class="btn btn-warning" data-on-click="@get('/remove/restore')">Put the Ugly thing Back !</button>
    );
    const t2 = std.time.microTimestamp();
    logz.info().string("event", "removeFragments").int("elapsed (μs)", t2 - t1).log();
}

fn removeFragmentsRestore(_: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();

    // these are short lived updates so we close the request as soon as its done
    const stream = try res.startEventStreamSync();
    defer stream.close();

    try datastar.removeFragments(stream, "#rm-restore");
    var msg = datastar.mergeFragmentsOpt(stream, .{
        .selector = "#rm-text",
        .merge_type = .after,
    });
    defer msg.end();

    var w = msg.writer();
    try w.writeAll(
        \\<div id="remove-me">
        \\  <p class="border-4 border-error">Lets get rid of this ugly DOM element</p>
        \\  <div class="justify-end card-actions">
        \\  <button class="btn btn-error" data-on-click="@get('/remove')">Remove It Again !</button>
        \\  </div>
        \\</div>
    );
    const t2 = std.time.microTimestamp();
    logz.info().string("event", "removeFragmentsRestore").int("elapsed (μs)", t2 - t1).log();
}

fn upsertAttributes(_: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();

    // these are short lived updates so we close the request as soon as its done
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

    const t2 = std.time.microTimestamp();
    logz.info().string("event", "upsertAttributes").int("violet-", color).int("elapsed (μs)", t2 - t1).log();
}

fn mergeSignals(_: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();

    // these are short lived updates so we close the request as soon as its done
    const stream = try res.startEventStreamSync();
    defer stream.close();

    var msg = datastar.mergeSignals(stream);
    defer msg.end();

    // create a random color

    var w = msg.writer();

    // this will set the following signals
    const foo = prng.random().intRangeAtMost(u8, 0, 255);
    const bar = prng.random().intRangeAtMost(u8, 0, 255);
    try w.print("{{ foo1: {d}, bar1: {d} }}", .{ foo, bar });

    const t2 = std.time.microTimestamp();
    logz.info().string("event", "mergeSignals").int("foo", foo).int("bar", bar).int("elapsed (μs)", t2 - t1).log();
}

fn mergeSignalsOnlyIfMissing(_: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();

    // these are short lived updates so we close the request as soon as its done
    const stream = try res.startEventStreamSync();
    defer stream.close();

    var msg = datastar.mergeSignalsIfMissing(stream);
    defer msg.end();

    // create a random color

    var w = msg.writer();

    // this will set the following signals
    const foo2 = prng.random().intRangeAtMost(u8, 1, 100);
    const bar2 = prng.random().intRangeAtMost(u8, 1, 100);
    try w.print("{{ foo2: {d}, bar2: {d} }}", .{ foo2, bar2 }); // first will update only

    const t2 = std.time.microTimestamp();
    logz.info().string("event", "mergeSignals").int("foo2", foo2).int("bar2", bar2).int("elapsed (μs)", t2 - t1).log();
}

fn removeSignals(_: *httpz.Request, _: *httpz.Response) !void {}

const snippets = [_][]const u8{
    @embedFile("snippets/code1.zig"),
    @embedFile("snippets/code2.zig"),
    @embedFile("snippets/code3.zig"),
    @embedFile("snippets/code4.zig"),
    @embedFile("snippets/code5.zig"),
    @embedFile("snippets/code6.zig"),
    @embedFile("snippets/code7.zig"),
};

fn code(req: *httpz.Request, res: *httpz.Response) !void {
    const snip = req.param("snip").?;
    const snip_id = try std.fmt.parseInt(u8, snip, 10);

    if (snip_id < 1 or snip_id > snippets.len) {
        return error.InvalidCodeSnippet;
    }

    const data = snippets[snip_id - 1];
    const stream = try res.startEventStreamSync();
    defer stream.close();

    var buf: [1024]u8 = undefined;
    const selector = try std.fmt.bufPrint(&buf, "#code-{s}", .{snip});
    var msg = datastar.mergeFragmentsOpt(stream, .{
        .selector = selector,
        .merge_type = .append,
    });
    defer msg.end();

    var w = msg.writer();

    var it = std.mem.splitAny(u8, data, "\n");
    while (it.next()) |line| {
        try w.writeAll("<pre><code>");
        for (line) |c| {
            switch (c) {
                '<' => try w.writeAll("&lt;"),
                '>' => try w.writeAll("&gt;"),
                else => try w.writeByte(c),
            }
        }
        try w.writeAll("</code></pre>\n");
    }
}
