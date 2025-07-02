const std = @import("std");
const httpz = @import("httpz");
const logz = @import("logz");
const datastar = @import("datastar.httpz");
const Allocator = std.mem.Allocator;

const PORT = 8081;

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
    defer server.deinit();
    defer server.stop();

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

    std.debug.print("listening http://localhost:{d}/\n", .{PORT});
    try server.listen();
}

fn index(_: *httpz.Request, res: *httpz.Response) !void {
    res.body = @embedFile("01_index.html");
}

var update_count: usize = 1;

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
    var w = msg.writer();
    defer msg.end();
    try w.print(
        \\ <p id="mf-merge">This is update number {d}</p>
    , .{update_count});
    update_count += 1;

    const t2 = std.time.microTimestamp();
    logz.info().src(@src()).string("event", "mergeFragments").int("elapsed (μs)", t2 - t1).log();
}

// create a mergeFragments stream, which will write commands over the SSE connection
// to update parts of the DOM. It will look for the DOM with the matching ID in the default case
//
// Use a variety of merge options for this one
fn mergeFragmentsOpts(req: *httpz.Request, res: *httpz.Response) !void {
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
    // option vs the enum values, and add them relative to the mf-merge-opt item
    var opt: datastar.MergeFragmentsOptions = .{
        .selector = "#mf-merge-opts",
    };
    for (std.enums.values(datastar.MergeType)) |merge_type| {
        if (std.mem.eql(u8, @tagName(merge_type), signals.morph)) {
            std.debug.print("set mergeType option {}\n", .{merge_type});
            opt.merge_type = merge_type;
            break; // can only have 1 merge type
        }
    }

    if (opt.merge_type == .morph) {
        return;
    }

    var msg = datastar.mergeFragmentsOpt(stream, opt);
    var w = msg.writer();
    defer msg.end();

    switch (opt.merge_type) {
        .outer => {
            try w.writeAll(
                \\ <p id="mf-merge-opts" class="border-4 border-error">Complete Replacement of the OUTER HTML</p>
            );
        },
        else => {
            try w.print(
                \\ <p>This is update number {d}</p>
            , .{update_count});
            update_count += 1;
        },
    }

    const t2 = std.time.microTimestamp();
    logz.info().src(@src()).string("event", "mergeFragmentsOpts").int("elapsed (μs)", t2 - t1).log();
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
    var w = msg.writer();
    defer msg.end();

    try w.writeAll(@embedFile("01_index_opts.html"));

    const t2 = std.time.microTimestamp();
    logz.info().src(@src()).string("event", "mergeFragmentsOptsReset").int("elapsed (μs)", t2 - t1).log();
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
    var w = msg.writer();
    defer msg.end();

    try w.writeAll(
        \\  <button id="rm-restore" class="btn btn-warning" data-on-click="@get('/remove/restore')">Put the Ugly thing Back !</button>
    );
    const t2 = std.time.microTimestamp();
    logz.info().src(@src()).string("event", "removeFragments").int("elapsed (μs)", t2 - t1).log();
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
    var w = msg.writer();
    defer msg.end();

    try w.writeAll(
        \\ <div id="remove-me">
        \\   <p class="border-4 border-error">Lets get rid of this ugly DOM element</p>
        \\   <div class="justify-end card-actions">
        \\   <button class="btn btn-error" data-on-click="@get('/remove')">Remove It Again !</button>
        \\   </div>
        \\ </div>
    );
    const t2 = std.time.microTimestamp();
    logz.info().src(@src()).string("event", "removeFragmentsRestore").int("elapsed (μs)", t2 - t1).log();
}
