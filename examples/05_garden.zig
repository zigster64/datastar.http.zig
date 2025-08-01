const std = @import("std");
const httpz = @import("httpz");
const logz = @import("logz");
const zts = @import("zts");
const datastar = @import("datastar");
const App = @import("05_plants.zig").App;
const homepage = @embedFile("05_index.html");

const Allocator = std.mem.Allocator;

const PORT = 8085;

// This example demonstrates a realtime pub/sub game that multople clients can join
// SSE and pub/sub to have realtime updates of updates to the garden
pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();

    var app = try App.init(allocator);
    defer app.deinit();

    var server = try httpz.Server(*App).init(allocator, .{
        .port = PORT,
        .address = "0.0.0.0",
    }, app);

    const game_t = try std.Thread.spawn(.{}, updateLoop, .{app});
    defer game_t.join();

    defer { // clean shutdown
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
    router.get("/plants", plantList, .{});
    router.post("/planteffect/:plantid", postPlantEffect, .{});
    router.get("/assets/:assetname", postAsset, .{});

    std.debug.print("listening http://localhost:{d}/\n", .{PORT});
    std.debug.print("... or any other IP address pointing to this machine\n", .{});
    try server.listen();
}

fn updateLoop(app: *App) !void {
    while (true) {
        try app.updatePlants();
        std.Thread.sleep(std.time.ns_per_s);
    }
}

fn postAsset(_: *App, req: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();
    defer {
        const t2 = std.time.microTimestamp();
        logz.info().string("event", "index").int("elapsed (μs)", t2 - t1).log();
    }
    const file_name = req.param("assetname").?;

    const static_dir = "./examples/assets/fantasy_crops"; //try std.fmt.allocPrint(res.arena, "{s}/{s}", .{static_dir,file_name});
    const fullPath = try std.fmt.allocPrint(res.arena, "{s}/{s}", .{ static_dir, file_name });

    const file = try std.fs.cwd().openFile(fullPath, .{});
    defer file.close();
    res.content_type = .PNG;
    res.body = try file.readToEndAlloc(res.arena, 100000);
}

fn index(_: *App, _: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();
    defer {
        const t2 = std.time.microTimestamp();
        logz.info().string("event", "index").int("elapsed (μs)", t2 - t1).log();
    }
    res.content_type = .HTML;
    res.body = homepage;
}

fn plantList(app: *App, _: *httpz.Request, res: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();
    app.mutex.lock();
    defer {
        app.mutex.unlock();
        const t2 = std.time.microTimestamp();
        logz.info().string("event", "plantsList").int("elapsed (μs)", t2 - t1).log();
    }

    const stream: std.net.Stream = try res.startEventStreamSync();
    // DO NOT close - this stream stays open forever
    // and gets subscribed to "plants" update events
    try app.subscribe("plants", stream, App.publishPlantList);
}

fn postPlantEffect(app: *App, req: *httpz.Request, _: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();
    app.mutex.lock();
    defer {
        app.mutex.unlock();
        const t2 = std.time.microTimestamp();
        logz.info().string("event", "postPlantEffect").int("elapsed (μs)", t2 - t1).log();
    }

    const id_param = req.param("plantid").?;
    const id = try std.fmt.parseInt(usize, id_param, 10);

    if (id < 0 or id >= 4) {
        return error.InvalidID;
    }

    const Hand = struct {
        hand: []const u8,
    };
    const signals = try datastar.readSignals(Hand, req);
    std.debug.print("Item {s}\n", .{signals.hand});
    if (std.mem.eql(u8, signals.hand, "watering")) {
        if (app.plants[id]) |*p| {
            p.stats.water += 0.1;
        }
    } else if (std.mem.eql(u8, signals.hand, "fertilizing")) {
        if (app.plants[id]) |*p| {
            p.stats.ph += 0.1;
        }
    } else if (std.mem.eql(u8, signals.hand, "sunning")) {
        if (app.plants[id]) |*p| {
            p.stats.sun += 0.1;
        }
    } else if (std.mem.eql(u8, signals.hand, "shovel")) {
        // Remove plant at index
        std.debug.print("Found shovel: {s}", .{signals.hand});
    } else if (std.mem.eql(u8, signals.hand, "carrot")) {
        // Remove plant at index
        std.debug.print("Found other hand item: {s}", .{signals.hand});
    } else if (std.mem.eql(u8, signals.hand, "onion")) {
        // Remove plant at index
        std.debug.print("Found other hand item: {s}", .{signals.hand});
    } else if (std.mem.eql(u8, signals.hand, "onion")) {
        // Remove plant at index
        std.debug.print("Found other hand item: {s}", .{signals.hand});
    } else if (std.mem.eql(u8, signals.hand, "onion")) {
        // Remove plant at index
    } else {
        std.debug.print("Found other hand item: {s}", .{signals.hand});
    }
    // update any screens subscribed to "plants"
    try app.publish("plants");
}
