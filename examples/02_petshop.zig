const std = @import("std");
const httpz = @import("httpz");
const logz = @import("logz");
const zts = @import("zts");
const datastar = @import("datastar.httpz");
const Allocator = std.mem.Allocator;

const PORT = 8082;

const Cat = struct {
    id: u8,
    name: []const u8,
    img: []const u8,
    bid: usize = 0,

    pub fn render(cat: Cat, w: anytype) !void {
        try w.print(
            \\<div class="card w-8/12 bg-slate-300 card-lg shadow-sm m-auto mt-4">
            \\  <div class="card-body" id="cat-{[id]}">
            \\    <h2 class="card-title">{[name]s}</h2>
            \\  <div class="avatar">
            \\    <div class="w-48 h-48 rounded-full">
            \\      <img src="{[img]s}">
            \\    </div>
            \\  </div>
            \\  <input type="number" placeholder="Bid" class="input" data-bind-bid-{[id]} value="{[bid]}" />
            \\  <div class="justify-end card-actions">
            \\    <button class="btn btn-primary" data-on-click="@post('/bid')">Place Bid</button>
            \\  </div>
            \\  </div>
            \\</div>
        , cat);
    }
};

const App = struct {
    gpa: Allocator,
    cats: std.ArrayList(Cat),
    mutex: std.Thread.Mutex,

    pub fn init(gpa: Allocator) !App {
        var cats = std.ArrayList(Cat).init(gpa);

        try cats.append(.{
            .id = 1,
            .name = "Harry",
            .img = "https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8Mnx8Y2F0fGVufDB8fDB8fHww",
        });
        try cats.append(.{
            .id = 2,
            .name = "Meghan",
            .img = "https://images.unsplash.com/photo-1574144611937-0df059b5ef3e?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MTR8fGNhdHxlbnwwfHwwfHx8MA%3D%3D",
        });
        try cats.append(.{
            .id = 3,
            .name = "Prince",
            .img = "https://images.unsplash.com/photo-1574158622682-e40e69881006?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MjB8fGNhdHxlbnwwfHwwfHx8MA%3D%3D",
        });
        try cats.append(.{
            .id = 4,
            .name = "Fluffy",
            .img = "https://plus.unsplash.com/premium_photo-1664299749481-ac8dc8b49754?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8OXx8Y2F0fGVufDB8fDB8fHww",
        });
        try cats.append(.{
            .id = 5,
            .name = "Princessa",
            .img = "https://images.unsplash.com/photo-1472491235688-bdc81a63246e?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8Nnx8Y2F0fGVufDB8fDB8fHww",
        });
        try cats.append(.{
            .id = 6,
            .name = "Tiger",
            .img = "https://plus.unsplash.com/premium_photo-1673967770669-91b5c2f2d0ce?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8NXx8a2l0dGVufGVufDB8fDB8fHww",
        });
        const app = App{
            .gpa = gpa,
            .mutex = .{},
            .cats = cats,
        };
        return app;
    }
};

// This example demonstrates basic DataStar operations
// PatchElements / PatchSignals

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    const allocator = gpa.allocator();

    var app = try App.init(allocator);

    var server = try httpz.Server(*App).init(allocator, .{
        .port = PORT,
        .address = "0.0.0.0",
    }, &app);
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

    std.debug.print("listening http://localhost:{d}/\n", .{PORT});
    std.debug.print("... or any other IP address pointing to this machine\n", .{});
    try server.listen();
}

fn index(app: *App, _: *httpz.Request, res: *httpz.Response) !void {
    res.content_type = .HTML;
    const w = res.writer();
    const tmpl = @embedFile("02_index.html");
    try zts.writeHeader(tmpl, w);

    for (app.cats.items) |cat| {
        try cat.render(w);
    }
    try zts.write(tmpl, "cats", w);
}
