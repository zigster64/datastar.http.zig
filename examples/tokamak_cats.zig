const std = @import("std");
const tk = @import("tokamak");
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
            \\      <input type="number" placeholder="Bid" class="grow" data-bind:bids.{[id]} />
            \\    </label>
            \\    <div class="justify-end card-actions">
            \\      <button class="btn btn-primary" data-on:click="@post('/bid/{[id]}', {{filterSignals: {{include: '^bids$'}}}})">Place Bid</button>
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
    server: tk.Server,
    routes: []const tk.Route = &.{
        .get("/", index),
        .get("/cats", catsList),
        .post("/bid/:id", postBid),
        .post("/sort", postSort),
    },
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

    pub fn configure(bundle: *tk.Bundle) void {
        bundle.addInitHook(logz.setup);
        bundle.addDeinitHook(logz.deinit);
        bundle.addInitHook(datastar.configure);
        bundle.addInitHook(printAddress);
    }

    fn printAddress(server: *tk.Server) void {
        std.debug.print("listening http://localhost:{d}/\n", .{server.http.config.port.?});
        std.debug.print("... or any other IP address pointing to this machine\n", .{});
    }

    pub fn newSessionID(app: *App) !usize {
        app.mutex.lock();
        defer app.mutex.unlock();
        const s = app.next_session_id;
        app.next_session_id += 1;

        const session_id = try std.fmt.allocPrint(app.gpa, "{d}", .{s});
        try app.sessions.put(session_id, .{});

        std.debug.print("App Sessions after adding a new session ID:\n", .{});
        var it = app.sessions.keyIterator();
        while (it.next()) |k| {
            std.debug.print("- {s}\n", .{k.*});
        }

        return s;
    }

    pub fn ensureSession(app: *App, session_id: []const u8) !void {
        app.mutex.lock();
        defer app.mutex.unlock();

        if (app.sessions.get(session_id) == null) {
            try app.sessions.put(try app.gpa.dupe(u8, session_id), .{});
            std.debug.print("Had to add session {s} to my sessions list, because the client says its there, but I dont know about it\n", .{session_id});
        }
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
            logz.info().string("event", "publishCatList").int("stream", stream.handle).string("session", session orelse "null").int("elapsed (μs)", t2 - t1).log();
        }

        var buffer: [1024]u8 = undefined;
        var sse = datastar.NewSSEFromStream(stream, &buffer);

        // Update the HTML in the correct order
        var w = sse.patchElementsWriter(.{ .view_transition = true });

        // TODO - this is uneccessarily ugly, but its still quick, so nobody is going to care
        // sort by id first to get all the bid signals correct
        app.sortCats(.id);
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

        try sse.flush();
    }

    pub fn publishPrefs(app: *App, stream: std.net.Stream, session: ?[]const u8) !void {
        const t1 = std.time.microTimestamp();
        defer {
            const t2 = std.time.microTimestamp();
            logz.info().string("event", "publishPrefs").int("stream", stream.handle).string("session", session orelse "null").int("elapsed (μs)", t2 - t1).log();
        }

        // just get the session prefs for the given session, and broadcast them to all
        // clients sharing this same session ID, to keep them in sync
        if (session) |s| {
            if (app.sessions.get(s)) |prefs| {
                var buffer: [32]u8 = undefined;
                var sse = datastar.NewSSEFromStream(stream, &buffer);

                try sse.patchSignals(.{
                    .sort = @tagName(prefs.sort),
                }, .{}, .{});
            }
        }
    }
};

fn index(app: *App, req: *tk.Request, res: *tk.Response) !void {
    const t1 = std.time.microTimestamp();
    defer {
        const t2 = std.time.microTimestamp();
        logz.info().string("event", "index").int("elapsed (μs)", t2 - t1).log();
    }

    // IF the new connection already has a session cookie, then use that, otherwise generate a brand new session
    var session_id: usize = 0;

    var cookies = req.cookies();
    if (cookies.get("session")) |session_cookie| {
        session_id = std.fmt.parseInt(usize, session_cookie, 10) catch 0;
        logz.info().string("existing session", session_cookie).int("numeric_value", session_id).log();

        try app.ensureSession(session_cookie);
    } else {
        session_id = try app.newSessionID();
        //
        // generate a Session ID and attach it to this user via a cookie
        try res.setCookie("session", try std.fmt.allocPrint(res.arena, "{d}", .{session_id}), .{
            .path = "/",
            // .domain = "localhost",
            // .max_age = 9001,
            // .secure = true,
            .http_only = true,
            // .partitioned = true,
            // .same_site = .none, // or .none, or .strict (or null to leave out)
        });
        logz.info().string("new session", "no initial cookie").int("numeric_value", session_id).log();
    }

    res.content_type = .HTML;
    res.body = @embedFile("022_index.html");
}

fn catsList(app: *App, req: *tk.Request, res: *tk.Response) !void {
    const t1 = std.time.microTimestamp();
    app.mutex.lock();
    defer {
        app.mutex.unlock();
        const t2 = std.time.microTimestamp();
        logz.info().string("event", "catsList").int("elapsed (μs)", t2 - t1).log();
    }

    var cookies = req.cookies();
    if (cookies.get("session")) |session| {
        // validated session
        const sse = try datastar.NewSSE(req, res);
        try app.subscribeSession("cats", sse.stream, App.publishCatList, session);
        try app.subscribeSession("prefs", sse.stream, App.publishPrefs, session);
    } else {
        std.debug.print("cant find session cookie - redirect to new login\n", .{});
        // no valid session - create a new one
        // redirect them to /
        var sse = try datastar.NewSSE(req, res);
        defer sse.close();
        try sse.executeScript("window.location='/'", .{});
    }
}

fn postBid(app: *App, req: *tk.Request) !void {
    const t1 = std.time.microTimestamp();
    app.mutex.lock();
    defer {
        app.mutex.unlock();
        const t2 = std.time.microTimestamp();
        logz.info().string("event", "postBid").int("elapsed (μs)", t2 - t1).log();
    }

    const id_param = req.param("id").?;
    const id = try std.fmt.parseInt(usize, id_param, 10);

    if (id < 0 or id >= app.cats.items.len) {
        return error.InvalidID;
    }

    app.sortCats(.id);

    const Bids = struct {
        bids: []usize,
    };
    const signals = try datastar.readSignals(Bids, req);
    // std.debug.print("bids {any}\n", .{signals.bids});
    const new_bid = signals.bids[id];
    // std.debug.print("new bid {}\n", .{new_bid});

    app.cats.items[id].bid = new_bid;
    app.cats.items[id].ts = std.time.nanoTimestamp();

    // update any screens subscribed to "cats"
    try app.publish("cats");
}

fn postSort(app: *App, req: *tk.Request, res: *tk.Response) !void {
    const t1 = std.time.microTimestamp();
    app.mutex.lock();
    defer {
        app.mutex.unlock();
        const t2 = std.time.microTimestamp();
        logz.info().string("event", "postSort").int("elapsed (μs)", t2 - t1).log();
    }

    // const x = req.body();
    // std.debug.print("request body for sort = {?s}\n", .{x});

    const params = struct {
        sort: []const u8,
    };
    if (try req.json(params)) |p| {
        const new_sort = SortType.fromString(p.sort);

        var cookies = req.cookies();
        if (cookies.get("session")) |session| {
            std.debug.print("postSort got session cookie {s}\n", .{session});
            if (app.sessions.getPtr(session)) |app_session| {
                std.debug.print("  PostSort for Session {s} changed prefs from {t} -> {t}\n", .{ session, app_session.sort, new_sort });
                app_session.sort = new_sort;
                try app.publishSession("cats", session);
                try app.publishSession("prefs", session);
                return;
            }
        }
    }
    std.debug.print("no cookie / no session - user must reconnect to get a new cookie", .{});
    res.status = 400;
    res.body = "No session";
    return;
}

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
