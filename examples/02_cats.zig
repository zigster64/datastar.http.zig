const std = @import("std");
const httpz = @import("httpz");
const logz = @import("logz");
const zts = @import("zts");
const datastar = @import("datastar.httpz");
const Allocator = std.mem.Allocator;

const Cat = struct {
    id: u8,
    name: []const u8,
    img: []const u8,
    bid: usize = 0,

    pub fn render(cat: Cat, w: anytype) !void {
        try w.print(
            \\<div class="card w-8/12 bg-slate-300 card-lg shadow-sm m-auto mt-4">
            \\  <div class="card-body" id="cat-{[id]}">
            \\    <h2 class="card-title">#{[id]} {[name]s}</h2>
            \\    <div class="avatar">
            \\      <div class="w-48 h-48 rounded-full">
            \\        <img src="{[img]s}">
            \\      </div>
            \\    </div>
            \\    <label class="input">$ 
            \\      <input type="number" placeholder="Bid" class="grow" data-bind-bids.{[id]} value="{[bid]}" />
            \\    </label>
            \\    <div class="justify-end card-actions">
            \\      <button class="btn btn-primary" data-on-click="@post('/bid/{[id]}')">Place Bid</button>
            \\    </div>
            \\  </div>
            \\</div>
        , cat);
    }
};

pub const Cats = std.ArrayList(Cat);

pub const App = struct {
    gpa: Allocator,
    cats: Cats,
    mutex: std.Thread.Mutex,
    subscribers: ?datastar.Subscribers(*App) = null,

    pub fn init(gpa: Allocator) !App {
        return .{
            .gpa = gpa,
            .mutex = .{},
            .cats = try createCats(gpa),
        };
    }

    pub fn deinit(app: *App) void {
        app.streams.deinit();
        app.cats.deinit();
    }

    pub fn subscribe(app: *App, topic: []const u8, stream: std.net.Stream) !void {
        if (app.subscribers == null) {
            app.subscribers = try datastar.Subscribers(*App).init(app.gpa, app);
        }
        try app.subscribers.subscribe(topic, stream);
    }

    pub fn publish(app: *App, topic: []const u8) !void {
        if (app.subscribers) |s| {
            return s.publish(topic);
        }
    }

    pub fn publishBids(_: *App, _: std.net.Stream) !void {
        const t1 = std.time.microTimestamp();
        defer {
            const t2 = std.time.microTimestamp();
            logz.info().string("event", "updateBids").int("elapsed (μs)", t2 - t1).log();
        }
    }

    pub fn publishCatList(app: *App, _: std.net.Stream) !void {
        const t1 = std.time.microTimestamp();
        defer {
            const t2 = std.time.microTimestamp();
            logz.info().string("event", "publishCatList").int("elapsed (μs)", t2 - t1).log();
        }

        for (app.cats.items) |cat| {
            std.debug.print("TODO publish Cat {[id]} {[name]s} has bid {[bid]}\n", .{
                .id = cat.id,
                .name = cat.name,
                .bid = cat.bid,
            });
        }
    }
};

fn createCats(gpa: Allocator) !Cats {
    var cats = Cats.init(gpa);
    try cats.append(.{
        .id = 0,
        .name = "Harry",
        .img = "https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8Mnx8Y2F0fGVufDB8fDB8fHww",
    });
    try cats.append(.{
        .id = 1,
        .name = "Meghan",
        .img = "https://images.unsplash.com/photo-1574144611937-0df059b5ef3e?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MTR8fGNhdHxlbnwwfHwwfHx8MA%3D%3D",
    });
    try cats.append(.{
        .id = 2,
        .name = "Prince",
        .img = "https://images.unsplash.com/photo-1574158622682-e40e69881006?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MjB8fGNhdHxlbnwwfHwwfHx8MA%3D%3D",
    });
    try cats.append(.{
        .id = 3,
        .name = "Fluffy",
        .img = "https://plus.unsplash.com/premium_photo-1664299749481-ac8dc8b49754?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8OXx8Y2F0fGVufDB8fDB8fHww",
    });
    try cats.append(.{
        .id = 4,
        .name = "Princessa",
        .img = "https://images.unsplash.com/photo-1472491235688-bdc81a63246e?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8Nnx8Y2F0fGVufDB8fDB8fHww",
    });
    try cats.append(.{
        .id = 5,
        .name = "Tiger",
        .img = "https://plus.unsplash.com/premium_photo-1673967770669-91b5c2f2d0ce?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8NXx8a2l0dGVufGVufDB8fDB8fHww",
    });
    return cats;
}
