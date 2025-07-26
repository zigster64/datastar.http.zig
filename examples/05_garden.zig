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
    router.post("/water/:plantid", postWater, .{});
    router.post("/sun/:plantid", postSun, .{});
    router.post("/fertilize/:plantid", postFertilize, .{});
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

fn postWater(app: *App, req: *httpz.Request, _: *httpz.Response) !void {
    const t1 = std.time.microTimestamp();
    app.mutex.lock();
    defer {
        app.mutex.unlock();
        const t2 = std.time.microTimestamp();
        logz.info().string("event", "postWater").int("elapsed (μs)", t2 - t1).log();
    }

    const id_param = req.param("plantid").?;
    const id = try std.fmt.parseInt(usize, id_param, 10);

    if (id < 0 or id >= app.plants.items.len) {
        return error.InvalidID;
    }

    const Watering = struct {
        water: f32,
    };
    const signals = try datastar.readSignals(Watering, req);
    std.debug.print("Water {any}\n", .{signals.water});
    const water_qt = signals.water;
    std.debug.print("Watered plant {s} with water amount {d}\n", .{ app.plants.items[id].name, water_qt });
    app.plants.items[id].water_level += water_qt;

    // update any screens subscribed to "plants"
    try app.publish("plants");
}

fn postSun(app: *App, req: *httpz.Request, _: *httpz.Response) !void {
    _ = app;
    _ = req;
}

fn postFertilize(app: *App, req: *httpz.Request, _: *httpz.Response) !void {
    _ = app;
    _ = req;
}
