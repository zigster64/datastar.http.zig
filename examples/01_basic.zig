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

    std.debug.print("listening http://localhost:{d}/\n", .{PORT});
    try server.listen();
}

fn index(_: *httpz.Request, res: *httpz.Response) !void {
    res.body = @embedFile("01_index.html");
}

var update_count: usize = 1;

fn mergeFragments(_: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();

    // these are short lived updates so we close the request as soon as its done
    const stream = try res.startEventStreamSync();
    defer stream.close();

    // create a mergeFragments stream, which will write commands over the SSE connection
    // to update parts of the DOM. It will look for the DOM with the matching ID in the default case
    //
    // NOTE - once we have created a DataStar 'Message' of whatever type, we then get a writer
    // from it, and from there we can freely print to to.  The writer will auto-inject all the
    // protocol parts to split it into lines and describe each fragment by magic.

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
