const std = @import("std");
const httpz = @import("httpz");
const logz = @import("logz");
const zts = @import("zts");
const datastar = @import("datastar");

const Allocator = std.mem.Allocator;
const PORT = 8085;

fn index(_: *httpz.Request, res: *httpz.Response) !void {
    res.body = @embedFile("05_index.html");
}

const Plant = struct {
    id: u8,
    name: []const u8,
    img_name: []const u8,

    state: GrowthState,
    // Balance stats that prefer to be around 0.5 and dislike being arount 0 or 1
    // TODO make plants with their own preferences for each stat and unique depletion rates
    water_level: f32 = 0.5, // Water saturation, depletes over time based on sun exposure, increased by bucket
    soil_quality: f32 = 0.5, // Abstracted soil level, refers to ph and nutrient levels, depletes over time, increased by fertilizer
    sun_level: f32 = 0.5, // Availability of sunlight, static but increases water loss

    const GrowthState = enum {
        Full,
        Medium,
        Sprouting,
        Dying,
        Dead,
    };

    pub fn render(p: Plant, w: anytype) !void {
        try w.print(
            \\<div class="card w-8/12 bg-slate-300 card-lg shadow-sm m-auto mt-4">
            \\  <div class="card-body" id="plant-{[id]}">
            \\    <h2 class="card-title">#{[id]} {[name]s}</h2>
            \\    <div class="avatar">
            \\      <div class="m-auto w-48 h-48 rounded-full">
            \\        <img data-on-click="@post('/water/{[id]}')" src="{[img]s}">
            \\      </div>
            \\    </div>
            \\  </div>
            \\</div>
        , .{
            .id = p.id,
            .name = p.name,
            .img = p.img_name,
        });
    }
};

pub const Plants = std.ArrayList(Plant);

pub const App = struct {
    gpa: Allocator,
    plants: Plants,
    mutex: std.Thread.Mutex,
    subscribers: ?datastar.Subscribers(*App) = null,

    pub fn init(gpa: Allocator) !*App {
        const app = try gpa.create(App);
        app.* = .{
            .gpa = gpa,
            .mutex = .{},
            .plants = try initPlants(gpa),
            .subscribers = try datastar.Subscribers(*App).init(gpa, app),
        };
        return app;
    }

    pub fn enableSubscriptions(app: *App) !void {
        app.subscribers = try datastar.Subscribers(*App).init(app.gpa, app);
    }

    pub fn deinit(app: *App) void {
        app.plants.deinit();
        app.gpa.destroy(app);
    }

    // convenience function
    pub fn subscribe(app: *App, topic: []const u8, stream: std.net.Stream, callback: anytype) !void {
        try app.subscribers.?.subscribe(topic, stream, callback);
    }

    // convenience function
    pub fn publish(app: *App, topic: []const u8) !void {
        try app.subscribers.?.publish(topic);
    }

    pub fn publishPlantList(app: *App, stream: std.net.Stream, _: ?[]const u8) !void {
        const t1 = std.time.microTimestamp();
        defer {
            const t2 = std.time.microTimestamp();
            logz.info().string("event", "publishPlantList").int("elapsed (μs)", t2 - t1).log();
        }

        // Update the HTML in the correct order
        var msg = datastar.patchElements(stream);
        defer msg.end();

        // UGLY - doing very manual updates on the signals array below ... ok for demo with only 6 plants, but dont do this in real life please
        var w = msg.writer();
        try w.print(
            \\<div id="plant-list" class="grid grid-cols-2 grid-rows-2 mt-32 h-full" data-signals="{{ states: [{d},{d},{d},{d}] }}">
        , .{
            @intFromEnum(app.plants.items[0].state),
            @intFromEnum(app.plants.items[1].state),
            @intFromEnum(app.plants.items[2].state),
            @intFromEnum(app.plants.items[3].state),
        });

        for (app.plants.items) |plant| {
            try plant.render(w);
        }
        try w.writeAll(
            \\</div>
        );
    }
};

fn initPlants(gpa: Allocator) !Plants {
    var plants = Plants.init(gpa);
    try plants.append(.{
        .id = 0,
        .name = "Tomato Plant",
        .img_name = "./assets/tile000.png",
        .state = .Sprouting,
    });
    try plants.append(.{
        .id = 1,
        .name = "Onion Plant",
        .img_name = "./assets/tile001.png",
        .state = .Sprouting,
    });
    try plants.append(.{
        .id = 2,
        .name = "Cactus Plant",
        .img_name = "./assets/tile001.png",
        .state = .Sprouting,
    });
    try plants.append(.{
        .id = 3,
        .name = "Basil Plant",
        .img_name = "./assets/tile001.png",
        .state = .Sprouting,
    });
    return plants;
}
