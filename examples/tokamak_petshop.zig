const std = @import("std");
const tk = @import("tokamak");
const logz = @import("logz");
const datastar = @import("datastar");
const App = @import("tokamak_cats.zig").App;
const SortType = @import("tokamak_cats.zig").SortType;

const Allocator = std.mem.Allocator;

const PORT = 8182;

const Config = struct {
    logz: logz.Config = .{
        .level = .Info,
        .pool_size = 100,
        .buffer_size = 4096,
        .large_buffer_count = 8,
        .large_buffer_size = 16384,
        .output = .stdout,
        .encoding = .logfmt,
    },

    server: tk.ServerOptions = .{
        .listen = .{
            .port = PORT,
            .hostname = "0.0.0.0",
        },
    },

    datastar: datastar.Config = .{
        .buffer_size = 255,
    },
};

// This example demonstrates a simple auction site that uses
// SSE and pub/sub to have realtime updates of bids on a Cat auction
pub fn main() !void {
    try tk.app.run(tk.Server.start, &.{ Config, App });
}
