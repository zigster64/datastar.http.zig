const std = @import("std");
const httpz = @import("httpz");
const logz = @import("logz");
const datastar = @import("datastar");
const Allocator = std.mem.Allocator;

const Cat = struct {
    id: u8,
    name: []const u8,
    img: []const u8,
    bid: usize = 0,
    ts: i128 = 0,

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
            \\      <input type="number" placeholder="Bid" class="grow" data-bind-bids.{[id]} />
            \\    </label>
            \\    <div class="justify-end card-actions">
            \\      <button class="btn btn-primary" data-on-click="@post('/bid/{[id]}')">Place Bid</button>
            \\    </div>
            \\  </div>
            \\</div>
        , .{
            .id = cat.id,
            .name = cat.name,
            .img = cat.img,
        });
    }
};

pub const Cats = std.ArrayList(Cat);

pub const SortType = enum {
    id,
    low,
    high,
    recent,

    pub fn fromString(s: []const u8) SortType {
        if (std.mem.eql(u8, s, "low")) return .low;
        if (std.mem.eql(u8, s, "high")) return .high;
        if (std.mem.eql(u8, s, "recent")) return .recent;
        return .id;
    }
};

pub const SessionPrefs = struct {
    sort: SortType = .id,
};

pub const App = struct {
    gpa: Allocator,
    cats: Cats,
    mutex: std.Thread.Mutex,
    next_session_id: usize = 1,
    subscribers: datastar.Subscribers(*App),
    sessions: std.StringHashMap(SessionPrefs),
    last_sort: SortType = .id,

    pub fn init(gpa: Allocator) !*App {
        const app = try gpa.create(App);
        app.* = .{
            .gpa = gpa,
            .mutex = .{},
            .cats = try createCats(gpa),
            .sessions = std.StringHashMap(SessionPrefs).init(gpa),
            .subscribers = try datastar.Subscribers(*App).init(gpa, app),
        };
        return app;
    }

    pub fn newSessionID(app: *App) !usize {
        app.mutex.lock();
        defer app.mutex.unlock();
        const s = app.next_session_id;
        app.next_session_id += 1;

        const session_id = try std.fmt.allocPrint(app.gpa, "{d}", .{s});
        try app.sessions.put(session_id, .{});

        std.debug.print("Sessions :\n", .{});
        var it = app.sessions.keyIterator();
        while (it.next()) |k| {
            std.debug.print("K {s}\n", .{k});
        }

        return s;
    }

    pub fn enableSubscriptions(app: *App) !void {
        app.subscribers = try datastar.Subscribers(*App).init(app.gpa, app);
    }

    pub fn deinit(app: *App) void {
        app.streams.deinit();
        app.cats.deinit();
        app.sessions.deinit();
        app.gpa.destroy(app);
    }

    fn catSortID(_: void, cat1: Cat, cat2: Cat) bool {
        return cat1.id < cat2.id;
    }

    fn catSortLow(_: void, cat1: Cat, cat2: Cat) bool {
        if (cat1.bid == cat2.bid) return cat1.id < cat2.id;
        return cat1.bid < cat2.bid;
    }

    fn catSortHigh(_: void, cat1: Cat, cat2: Cat) bool {
        if (cat1.bid == cat2.bid) return cat1.id < cat2.id;
        return cat1.bid > cat2.bid;
    }

    fn catSortRecent(_: void, cat1: Cat, cat2: Cat) bool {
        if (cat1.ts == cat2.ts) return cat1.id < cat2.id;
        return cat1.ts > cat2.ts;
    }

    pub fn sortCats(app: *App, sort: SortType) void {
        if (app.last_sort == sort) return;

        switch (sort) {
            .id => std.sort.block(Cat, app.cats.items, {}, catSortID),
            .low => std.sort.block(Cat, app.cats.items, {}, catSortLow),
            .high => std.sort.block(Cat, app.cats.items, {}, catSortHigh),
            .recent => std.sort.block(Cat, app.cats.items, {}, catSortRecent),
        }
        app.last_sort = sort;
    }

    // convenience function
    pub fn subscribe(app: *App, topic: []const u8, stream: std.net.Stream, callback: anytype) !void {
        try app.subscribers.subscribe(topic, stream, callback);
    }

    pub fn subscribeSession(app: *App, topic: []const u8, stream: std.net.Stream, callback: anytype, session: ?[]const u8) !void {
        try app.subscribers.subscribeSession(topic, stream, callback, session);
    }

    // convenience function
    pub fn publish(app: *App, topic: []const u8) !void {
        try app.subscribers.publish(topic);
    }

    pub fn publishSession(app: *App, topic: []const u8, session: []const u8) !void {
        try app.subscribers.publishSession(topic, session);
    }

    pub fn publishCatList(app: *App, stream: std.net.Stream, session: ?[]const u8) !void {
        const t1 = std.time.microTimestamp();
        defer {
            const t2 = std.time.microTimestamp();
            logz.info().string("event", "publishCatList").int("stream", stream.handle).string("session", session.?).int("elapsed (μs)", t2 - t1).log();
        }

        // Update the HTML in the correct order
        var msg = datastar.patchElementsOpt(stream, .{ .view_transition = true });
        defer msg.end();

        // TODO - this is uneccessarily ugly, but its still quick, so nobody is going to care
        // sort by id first to get all the bid signals correct
        app.sortCats(.id);
        var w = msg.writer();
        try w.print(
            \\<div id="cat-list" class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 mt-4 h-full" data-signals="{{ bids: [{d},{d},{d},{d},{d},{d}] }}">
        , .{
            app.cats.items[0].bid,
            app.cats.items[1].bid,
            app.cats.items[2].bid,
            app.cats.items[3].bid,
            app.cats.items[4].bid,
            app.cats.items[5].bid,
        });

        if (session) |s| {
            // then re-sort them if its different to id order to get the cards right
            if (app.sessions.get(s)) |session_prefs| {
                app.sortCats(session_prefs.sort);
            }
        }
        for (app.cats.items) |cat| {
            try cat.render(w);
        }
        try w.writeAll(
            \\</div>
        );
    }
};

fn createCats(gpa: Allocator) !Cats {
    var cats: Cats = .empty;
    errdefer cats.deinit(gpa);
    try cats.append(gpa, .{
        .id = 0,
        .name = "Harry",
        .img = "https://images.unsplash.com/photo-1514888286974-6c03e2ca1dba?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8Mnx8Y2F0fGVufDB8fDB8fHww",
    });
    try cats.append(gpa, .{
        .id = 1,
        .name = "Meghan",
        .img = "https://images.unsplash.com/photo-1574144611937-0df059b5ef3e?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MTR8fGNhdHxlbnwwfHwwfHx8MA%3D%3D",
    });
    try cats.append(gpa, .{
        .id = 2,
        .name = "Prince",
        .img = "https://images.unsplash.com/photo-1574158622682-e40e69881006?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MjB8fGNhdHxlbnwwfHwwfHx8MA%3D%3D",
    });
    try cats.append(gpa, .{
        .id = 3,
        .name = "Fluffy",
        .img = "https://plus.unsplash.com/premium_photo-1664299749481-ac8dc8b49754?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8OXx8Y2F0fGVufDB8fDB8fHww",
    });
    try cats.append(gpa, .{
        .id = 4,
        .name = "Princessa",
        .img = "https://images.unsplash.com/photo-1472491235688-bdc81a63246e?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8Nnx8Y2F0fGVufDB8fDB8fHww",
    });
    try cats.append(gpa, .{
        .id = 5,
        .name = "Tiger",
        .img = "https://plus.unsplash.com/premium_photo-1673967770669-91b5c2f2d0ce?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.1.0&ixid=M3wxMjA3fDB8MHxzZWFyY2h8NXx8a2l0dGVufGVufDB8fDB8fHww",
    });
    return cats;
}
