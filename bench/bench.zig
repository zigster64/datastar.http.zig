const std = @import("std");
const httpz = @import("httpz");
const datastar = @import("datastar");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;
var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

pub fn main() !void {
    const gpa, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    var server = try httpz.Server(void).init(gpa, .{
        .address = "0.0.0.0",
        .port = 8090,
        .thread_pool = .{ .count = 32, .backlog = 255 },
        .workers = .{ .count = 32, .max_conn = 2000 },
    }, {});
    var router = try server.router(.{});
    router.get("/", handler, .{});
    std.debug.print("Zig Datastar SSE Server running at http://localhost:8090\n", .{});
    return server.listen();
}

pub fn handler(req: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();
    var sse = try datastar.NewSSE(req, res);
    defer sse.close();

    try sse.patchElements(@embedFile("index.html"), .{});
    std.debug.print("handler took {} microseconds\n", .{std.time.microTimestamp() - t1});
}
