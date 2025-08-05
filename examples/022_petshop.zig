const std = @import("std");
const httpz = @import("httpz");
const logz = @import("logz");
const datastar = @import("datastar");
const App = @import("022_cats.zig").App;
const SortType = @import("022_cats.zig").SortType;

const Allocator = std.mem.Allocator;

const PORT = 8082;

// This example demonstrates a simple auction site that uses
// SSE and pub/sub to have realtime updates of bids on a Cat auction
pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    const allocator = gpa.allocator();

    var app = try App.init(allocator);
    try app.enableSubscriptions();

    var server = try httpz.Server(*App).init(allocator, .{
        .port = PORT,
        .address = "0.0.0.0",
    }, app);
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
    router.get("/cats", catsList, .{});
    router.post("/bid/:id", postBid, .{});
    router.post("/sort", postSort, .{});

    std.debug.print("listening http://localhost:{d}/\n", .{PORT});
    std.debug.print("... or any other IP address pointing to this machine\n", .{});
    try server.listen();
}

fn index(app: *App, _: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();
    defer {
        const t2 = std.time.microTimestamp();
        logz.info().string("event", "index").int("elapsed (μs)", t2 - t1).log();
    }

    const session_id = try app.newSessionID();
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
    std.debug.print("new index page - set cookie session = {d}\n", .{session_id});

    res.content_type = .HTML;
    res.body = @embedFile("022_index.html");
}

fn catsList(app: *App, req: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();
    app.mutex.lock();
    defer {
        app.mutex.unlock();
        const t2 = std.time.microTimestamp();
        logz.info().string("event", "catsList").int("elapsed (μs)", t2 - t1).log();
    }

    const stream = try res.startEventStreamSync();
    // DO NOT close - this stream stays open forever
    // and gets subscribed to "cats" update events
    //
    var cookies = req.cookies();
    if (cookies.get("session")) |session| {
        try app.subscribeSession("cats", stream, App.publishCatList, session);
    } else {
        try app.subscribe("cats", stream, App.publishCatList);
        std.debug.print("cant find session cookie ???\n", .{});
    }
}

fn postBid(app: *App, req: *httpz.Request, _: *httpz.Response) !void {
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
    std.debug.print("bids {any}\n", .{signals.bids});
    const new_bid = signals.bids[id];
    std.debug.print("new bid {}\n", .{new_bid});

    app.cats.items[id].bid = new_bid;
    app.cats.items[id].ts = std.time.nanoTimestamp();

    // update any screens subscribed to "cats"
    try app.publish("cats");
}

fn postSort(app: *App, req: *httpz.Request, _: *httpz.Response) !void {
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
        bids: []usize,
    };
    if (try req.json(params)) |p| {
        std.debug.print("request json body for sort = {s}\n", .{p.sort});
        const new_sort = SortType.fromString(p.sort);

        var cookies = req.cookies();
        if (cookies.get("session")) |session| {
            if (app.sessions.getPtr(session)) |app_session| {
                std.debug.print("got this session {?}\n", .{app_session});
                app_session.sort = new_sort;
                std.debug.print("upgraded to {?}\n", .{app_session});
                try app.publishSession("cats", session);
            }
        }
    }
}
