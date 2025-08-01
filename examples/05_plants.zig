const std = @import("std");
const Stream = std.net.Stream;
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
    name: []const u8,
    image_base_index: u32 = 0,

    state: PlantState = .Alive,
    growth_stage: GrowthStage = .Seedling,
    growth_steps: u32 = 0,
    stats: PlantStats = .{}, // Current Stats of plant, dynamic
    desired_stats: PlantStats = .{}, // Desired status of plant, static

    // Balance stats that prefer to be around 0.5 and dislike being around 0 or 1
    const PlantStats = struct {
        water: f32 = 0.5, // Water saturation, depletes over time based on sun exposure, increased by bucket
        ph: f32 = 0.5, // Abstracted soil level, refers to ph and nutrient levels, depletes over time, increased by fertilizer
        sun: f32 = 0.5, // Availability of sunlight, static but increases water loss
    };
    const image_format_string = "./assets/tile{d:0>3}.png";
    const PlantState = enum {
        Dead,
        Dying,
        Alive,
        Thriving,
    };

    const GrowthStage = enum {
        Seedling,
        Sprout,
        Young,
        Medium,
        Adult,
        Elder,
        Fruiting,
    };
    pub fn update(p: *Plant) !void {
        if (p.state == .Dead or p.growth_stage == .Fruiting) {
            return;
        }
        // Update state based on stats and desired stats
        switch (p.state) {
            .Dead => {},
            .Dying => {
                // Move to alive if conditions are met
                const water_diff = @abs(p.desired_stats.water - p.stats.water);
                const ph_diff = @abs(p.desired_stats.ph - p.stats.ph);
                const sun_diff = @abs(p.desired_stats.sun - p.stats.sun);

                if (water_diff < 0.3 and ph_diff < 0.3 and sun_diff < 0.3) {
                    p.state = .Alive;
                } else if (water_diff > 0.5 or ph_diff > 0.5 or sun_diff > 0.5) {
                    p.state = .Dead;
                }
            },
            .Alive => {
                p.growth_steps += 1;

                const water_diff = @abs(p.desired_stats.water - p.stats.water);
                const ph_diff = @abs(p.desired_stats.ph - p.stats.ph);
                const sun_diff = @abs(p.desired_stats.sun - p.stats.sun);

                if (water_diff < 0.1 and ph_diff < 0.1 and sun_diff < 0.1) {
                    p.state = .Thriving;
                } else if (water_diff > 0.3 or ph_diff > 0.3 or sun_diff > 0.3) {
                    p.state = .Dying;
                }
            },
            .Thriving => {
                p.growth_steps += 2;

                const water_diff = @abs(p.desired_stats.water - p.stats.water);
                const ph_diff = @abs(p.desired_stats.ph - p.stats.ph);
                const sun_diff = @abs(p.desired_stats.sun - p.stats.sun);

                if (water_diff > 0.1 or ph_diff > 0.1 or sun_diff > 0.1) {
                    p.state = .Alive;
                }
            },
        }

        // Update water
        std.debug.print("Updating stats...\n", .{});
        p.stats.water -= 0.01;

        // Update ph
        if (p.stats.ph < 0.5) {
            p.stats.ph += 0.01;
        } else {
            p.stats.ph -= 0.01;
        }

        // Grow plant if it breaches the threshold of growth
        if (p.growth_steps > 25 and p.growth_stage != .Fruiting) {
            p.growth_stage = @enumFromInt(@intFromEnum(p.growth_stage) + 1);
            p.growth_steps = 0;
        }
        std.debug.print("Plant stats: {{water: {d}, ph: {d}, sun: {d}}}\n", .{
            p.stats.water,
            p.stats.ph,
            p.stats.sun,
        });
    }

    pub fn render(p: Plant, id: usize, w: anytype, gpa: std.mem.Allocator) !void {
        const img_name = try std.fmt.allocPrint(gpa, image_format_string, .{p.image_base_index + @intFromEnum(p.growth_stage)});
        const img_class: []const u8 = switch (p.state) {
            .Dead => "dead",
            .Dying => "dying",
            .Alive => "alive",
            .Thriving => "thriving",
        };
        try w.print(
            \\<div class="card w-6/12 h-11/12 bg-yellow-700 card-lg shadow-sm m-auto mt-4 border-4 border-solid border-yellow-900">
            \\  <div class="card-body" id="plant-{[id]}">
            \\    <h2 class="card-title">#{[id]} {[name]s}</h2>
            \\    <div class="avatar">
            \\      <div class="m-auto w-32 h-32 rounded-md">
            \\        <img class="{[class]s}" data-on-click="@post('/planteffect/{[id]}')" src="{[img]s}">
            \\      </div>
            \\    </div>
            \\    <pre>
            \\      <div> water: {[water]}, ph: {[ph]}, sun: {[sun]}
            \\      <div> growth: {[steps]} / 25 </pre>
            \\    </pre>
            \\  </div>
            \\</div>
        , .{
            .id = id,
            .name = p.name,
            .img = img_name,
            .class = img_class,
            .water = p.stats.water,
            .ph = p.stats.ph,
            .sun = p.stats.sun,
            .steps = p.growth_steps,
        });
    }
};

const CarrotConfig = Plant{
    .name = "Carrot",
    .image_base_index = 0,
    .desired_stats = .{
        .water = 0.4,
        .ph = 0.4,
        .sun = 0.4,
    },
    .stats = .{
        .water = 0.4,
        .ph = 0.4,
        .sun = 0.4,
    },
};

const RadishConfig = Plant{
    .name = "Radish",
    .image_base_index = 0,
    .desired_stats = .{
        .water = 0.5,
        .ph = 0.8,
        .sun = 0.2,
    },
    .stats = .{
        .water = 0.5,
        .ph = 0.8,
        .sun = 0.2,
    },
};

const GourdConfig = Plant{
    .name = "Gourd",
    .image_base_index = 0,
    .desired_stats = .{
        .water = 0.2,
        .ph = 0.3,
        .sun = 0.6,
    },
    .stats = .{
        .water = 0.2,
        .ph = 0.3,
        .sun = 0.6,
    },
};

const TomatoConfig = Plant{
    .name = "Tomato",
    .image_base_index = 0,
    .desired_stats = .{
        .water = 0.8,
        .ph = 0.3,
        .sun = 0.6,
    },
    .stats = .{
        .water = 0.8,
        .ph = 0.3,
        .sun = 0.6,
    },
};

pub const App = struct {
    gpa: Allocator,
    plants: [4]?Plant,
    mutex: std.Thread.Mutex,
    subscribers: ?datastar.Subscribers(*App) = null,

    pub fn init(gpa: Allocator) !*App {
        const app = try gpa.create(App);
        app.* = .{
            .gpa = gpa,
            .mutex = .{},
            .plants = .{
                RadishConfig,
                CarrotConfig,
                TomatoConfig,
                GourdConfig,
            },
            .subscribers = try datastar.Subscribers(*App).init(gpa, app),
        };
        return app;
    }

    pub fn enableSubscriptions(app: *App) !void {
        app.subscribers = try datastar.Subscribers(*App).init(app.gpa, app);
    }

    pub fn deinit(app: *App) void {
        app.gpa.destroy(app);
    }

    // convenience function
    pub fn subscribe(app: *App, topic: []const u8, stream: Stream, callback: anytype) !void {
        try app.subscribers.?.subscribe(topic, stream, callback);
    }

    // convenience function
    pub fn publish(app: *App, topic: []const u8) !void {
        try app.subscribers.?.publish(topic);
    }

    pub fn publishPlantList(app: *App, stream: Stream, _: ?[]const u8) !void {
        const t1 = std.time.microTimestamp();
        defer {
            const t2 = std.time.microTimestamp();
            logz.info().string("event", "publishPlantList").int("elapsed (μs)", t2 - t1).log();
        }

        // Update the HTML in the correct order
        var msg = datastar.patchElements(stream);
        defer msg.end();

        var w = msg.writer();
        try w.print(
            \\<div id="plant-list" class="grid grid-cols-2 grid-rows-2 mt-32 h-8/12">
        , .{});

        // std.debug.print("Plant states are :\n {}\n{}\n{}\n{}\n\n", .{ app.plants[0].?, app.plants[1].?, app.plants[2].?, app.plants[3].? });
        for (0..4) |i| {
            if (app.plants[i]) |p| {
                try p.render(i, w, app.gpa);
            } else {
                try w.print(
                    \\<div class="card w-6/12 h-11/12 bg-yellow-800 card-lg shadow-sm m-auto mt-4 border-4 border-solid border-yellow-900">
                    \\  <div class="card-body" id="plant-{[id]}">
                    \\  </div>
                    \\</div>
                , .{ .id = i });
            }
        }
        try w.writeAll(
            \\</div>
        );
    }
    pub fn updatePlants(app: *App) !void {
        std.debug.print("Updated plants!\n", .{});
        for (0..4) |i| {
            if (app.plants[i]) |*p| {
                try p.update();
            }
        }
        try app.publish("plants");
    }
};
