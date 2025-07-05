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
// PatchElements / PatchSignals

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
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
    router.get("/patch", patchElements, .{});
    router.get("/patch/opts", patchElementsOpts, .{});
    router.get("/patch/opts/reset", patchElementsOptsReset, .{});
    router.get("/patch/signals", patchSignals, .{});
    router.get("/patch/signals/onlymissing", patchSignalsOnlyIfMissing, .{});
    router.get("/patch/signals/remove", removeSignals, .{});
    router.get("/executescript/:sample", executeScript, .{});

    router.get("/code/:snip", code, .{});

    std.debug.print("listening http://localhost:{d}/\n", .{PORT});
    std.debug.print("... or any other IP address pointing to this machine\n", .{});
    try server.listen();
}

fn index(_: *httpz.Request, res: *httpz.Response) !void {
    res.body = @embedFile("01_index.html");
}

// create a patchElements stream, which will write commands over the SSE connection
// to update parts of the DOM. It will look for the DOM with the matching ID in the default case
//
// NOTE - once we have created a DataStar 'Message' of whatever type, we then get a writer
// from it, and from there we can freely print to to.  The writer will auto-inject all the
// protocol parts to split it into lines and describe each element by magic.
fn patchElements(_: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();

    // these are short lived updates so we close the request as soon as its done
    const stream = try res.startEventStreamSync();
    defer stream.close();

    var msg = datastar.patchElements(stream);
    defer msg.end();

    var w = msg.writer();
    try w.print(
        \\<p id="mf-patch">This is update number {d}</p>
    , .{getCountAndIncrement()});

    const t2 = std.time.microTimestamp();
    logz.info().string("event", "patchElements").int("elapsed (μs)", t2 - t1).log();
}

// create a patchElements stream, which will write commands over the SSE connection
// to update parts of the DOM. It will look for the DOM with the matching ID in the default case
//
// Use a variety of patch options for this one
fn patchElementsOpts(req: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();

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

    const t2 = std.time.microTimestamp();
    logz.info().string("event", "patchElementsOpts").int("elapsed (μs)", t2 - t1).log();
}

// Just reset the options form if it gets ugly
fn patchElementsOptsReset(_: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();

    // these are short lived updates so we close the request as soon as its done
    const stream = try res.startEventStreamSync();
    defer stream.close();

    // read the signals to work out which options to set, checking the name of the
    // option vs the enum values, and add them relative to the mf-patch-opt item
    var msg = datastar.patchElementsOpt(stream, .{
        .selector = "#patch-element-card",
    });
    defer msg.end();

    var w = msg.writer();
    try w.writeAll(@embedFile("01_index_opts.html"));

    const t2 = std.time.microTimestamp();
    logz.info().string("event", "patchElementsOptsReset").int("elapsed (μs)", t2 - t1).log();
}

fn removeElements(_: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();

    // these are short lived updates so we close the request as soon as its done
    const stream = try res.startEventStreamSync();
    defer stream.close();

    try datastar.removeElements(stream, "#remove-me");

    // thats all we need to delete an element
    // now some fancy code to let up reset the form

    var msg = datastar.patchElementsOpt(stream, .{
        .selector = "#rm-card",
        .mode = .append,
    });
    defer msg.end();

    var w = msg.writer();
    try w.writeAll(
        \\<button id="rm-restore" class="btn btn-warning" data-on-click="@get('/remove/restore')">Put the Ugly thing Back !</button>
    );
    const t2 = std.time.microTimestamp();
    logz.info().string("event", "removeElements").int("elapsed (μs)", t2 - t1).log();
}

fn removeElementsRestore(_: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();

    // these are short lived updates so we close the request as soon as its done
    const stream = try res.startEventStreamSync();
    defer stream.close();

    try datastar.removeElements(stream, "#rm-restore");
    var msg = datastar.patchElementsOpt(stream, .{
        .selector = "#rm-text",
        .mode = .after,
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
    logz.info().string("event", "removeElementsRestore").int("elapsed (μs)", t2 - t1).log();
}

fn patchSignals(_: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();

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
    try w.print("{{ foo1: {d}, bar1: {d} }}", .{ foo, bar });

    const t2 = std.time.microTimestamp();
    logz.info().string("event", "patchSignals").int("foo", foo).int("bar", bar).int("elapsed (μs)", t2 - t1).log();
}

fn patchSignalsOnlyIfMissing(_: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();

    // these are short lived updates so we close the request as soon as its done
    const stream = try res.startEventStreamSync();
    defer stream.close();

    var msg = datastar.patchSignalsIfMissing(stream);
    defer msg.end();

    // create a random color

    var w = msg.writer();

    // this will set the following signals
    const foo2 = prng.random().intRangeAtMost(u8, 1, 100);
    const bar2 = prng.random().intRangeAtMost(u8, 1, 100);
    try w.print("{{ foo2: {d}, bar2: {d} }}", .{ foo2, bar2 }); // first will update only

    const t2 = std.time.microTimestamp();
    logz.info().string("event", "patchSignals").int("foo2", foo2).int("bar2", bar2).int("elapsed (μs)", t2 - t1).log();
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
    @embedFile("snippets/code8.zig"),
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
    var msg = datastar.patchElementsOpt(stream, .{
        .selector = selector,
        .mode = .append,
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

fn executeScript(req: *httpz.Request, res: *httpz.Response) !void {
    const sample = req.param("sample").?;
    const sample_id = try std.fmt.parseInt(u8, sample, 10);

    const stream = try res.startEventStreamSync();
    defer stream.close();

    var msg = datastar.executeScript(stream);
    defer msg.end();

    const script_data = if (sample_id == 1)
        "console.log('Running from executescript!');"
    else
        \\parent = document.querySelector('#executescript-card');
        \\console.log(parent.outerHTML);
    ;

    var w = msg.writer();
    try w.writeAll(script_data);
}
