const std = @import("std");
const tk = @import("tokamak");
const logz = @import("logz");
const datastar = @import("datastar");
const Allocator = std.mem.Allocator;

const PORT = 8181;

var update_count: usize = 1;
var update_mutex: std.Thread.Mutex = .{};

var prng = std.Random.DefaultPrng.init(0);

fn getCountAndIncrement() usize {
    update_mutex.lock();
    defer {
        update_count += 1;
        update_mutex.unlock();
    }
    return update_count;
}

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

const App = struct {
    server: tk.Server,
    routes: []const tk.Route = &.{
        .get("/", index),
        .get("/text-html", textHTML),
        .get("/patch", patchElements),
        .get("/patch/opts", patchElementsOpts),
        .get("/patch/opts/reset", patchElementsOptsReset),
        .get("/patch/json", jsonSignals),
        .get("/patch/signals", patchSignals),
        .get("/patch/signals/onlymissing", patchSignalsOnlyIfMissing),
        .get("/patch/signals/remove/:names", patchSignalsRemove),
        .get("/executescript/:sample", executeScript),
        .get("/code/:snip", code),
    },

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
};

pub fn main() !void {
    try tk.app.run(tk.Server.start, &.{ Config, App });
}

// This example demonstrates basic DataStar operations
// PatchElements / PatchSignals

pub fn main_old() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    const allocator = gpa.allocator();

    const routes: []const tk.Route = &.{
        .get("/", index),
        .get("/text-html", textHTML),
        .get("/patch", patchElements),
        .get("/patch/opts", patchElementsOpts),
        .get("/patch/opts/reset", patchElementsOptsReset),
        .get("/patch/json", jsonSignals),
        .get("/patch/signals", patchSignals),
        .get("/patch/signals/onlymissing", patchSignalsOnlyIfMissing),
        .get("/patch/signals/remove/:names", patchSignalsRemove),
        .get("/executescript/:sample", executeScript),
        .get("/code/:snip", code),
    };

    var server = try tk.Server.init(
        allocator,
        routes,
        .{
            .listen = .{
                .port = PORT,
                .hostname = "0.0.0.0",
            },
        },
    );

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

    datastar.configure(.{ .buffer_size = 255 });

    std.debug.print("listening http://localhost:{d}/\n", .{PORT});
    std.debug.print("... or any other IP address pointing to this machine\n", .{});
    try server.start();
}

fn index(res: *tk.Response) !void {
    res.body = @embedFile("01_index.html");
}

// Output a normal text/html response, and have it automatically patch the DOM
fn textHTML(res: *tk.Response) !void {
    const t1 = std.time.microTimestamp();
    defer {
        const t2 = std.time.microTimestamp();
        logz.info().string("event", "textHTML").int("elapsed (μs)", t2 - t1).log();
        // NOTE - you will see REALLY fast timings on these ones compared to SSE transfers
        // but thats only because this function exits before doing any writing.
        // It just sets the response body ... the http engine will do the writing afterwards
        //
        // If this function is changed to get a writer to the response, and w.print
        // directly to the stream just like the SSE methods use,  then you will see the
        // timings are ballpark the same as doing the SSE calls.
    }

    res.content_type = .HTML;

    res.body = try std.fmt.allocPrint(
        res.arena,
        \\<p id="text-html">This is update number {d}</p>
    ,
        .{getCountAndIncrement()},
    );
}

// create a patchElements stream, which will write commands over the SSE connection
// to update parts of the DOM. It will look for the DOM with the matching ID in the default case
fn patchElements(req: *tk.Request, res: *tk.Response) !void {
    const t1 = std.time.microTimestamp();
    defer {
        const t2 = std.time.microTimestamp();
        logz.info().string("event", "patchElements").int("elapsed (μs)", t2 - t1).log();
    }

    // // these are short lived updates so we close the request as soon as its done
    var sse = try datastar.NewSSE(req, res);
    defer sse.close();

    try sse.patchElementsFmt(
        \\<p id="mf-patch">This is update number {d}</p>
    ,
        .{getCountAndIncrement()},
        .{},
    );
}

// create a patchElements stream, which will write commands over the SSE connection
// to update parts of the DOM. It will look for the DOM with the matching ID in the default case
//
// Use a variety of patch options for this one
fn patchElementsOpts(req: *tk.Request, res: *tk.Response) !void {
    const t1 = std.time.microTimestamp();
    defer {
        const t2 = std.time.microTimestamp();
        logz.info().string("event", "patchElementsOpts").int("elapsed (μs)", t2 - t1).log();
    }

    const opts = struct {
        morph: []const u8,
    };

    const signals = try datastar.readSignals(opts, req);
    // jump out if we didnt set anything
    if (signals.morph.len < 1) {
        return;
    }
    // these are short lived updates so we close the request as soon as its done
    var sse = try datastar.NewSSE(req, res);
    defer sse.close();

    // read the signals to work out which options to set, checking the name of the
    // option vs the enum values, and add them relative to the mf-patch-opt item
    var patch_mode: datastar.PatchMode = .outer;
    for (std.enums.values(datastar.PatchMode)) |mt| {
        if (std.mem.eql(u8, @tagName(mt), signals.morph)) {
            patch_mode = mt;
            break; // can only have 1 patch type
        }
    }

    if (patch_mode == .outer or patch_mode == .inner) {
        return; // dont do morphs - its not relevant to this demo card
    }

    var w = sse.patchElementsWriter(.{
        .selector = "#mf-patch-opts",
        .mode = patch_mode,
    });
    switch (patch_mode) {
        .replace => {
            try w.writeAll(
                \\<p id="mf-patch-opts" class="border-4 border-error">Complete Replacement of the OUTER HTML</p>
            );
        },
        else => {
            try w.print(
                \\<p>This is update number {d}</p>
            , .{getCountAndIncrement()});
        },
    }
}

// Just reset the options form if it gets ugly
fn patchElementsOptsReset(req: *tk.Request, res: *tk.Response) !void {
    const t1 = std.time.microTimestamp();
    defer {
        const t2 = std.time.microTimestamp();
        logz.info().string("event", "patchElementsOptsReset").int("elapsed (μs)", t2 - t1).log();
    }

    // these are short lived updates so we close the request as soon as its done
    var sse = try datastar.NewSSE(req, res);
    defer sse.close();

    try sse.patchElements(@embedFile("01_index_opts.html"), .{
        .selector = "#patch-element-card",
    });
}

const FoojBarjResponse = struct {
    fooj: u8,
    barj: u8,
};

fn jsonSignals() !FoojBarjResponse {
    const t1 = std.time.microTimestamp();

    // this will set the following signals, by just outputting a JSON response rather than an SSE response
    const foo = prng.random().intRangeAtMost(u8, 0, 255);
    const bar = prng.random().intRangeAtMost(u8, 0, 255);

    defer {
        const t2 = std.time.microTimestamp();
        logz.info().string("event", "patchSignals").int("fooj", foo).int("barj", bar).int("elapsed (μs)", t2 - t1).log();
    }

    return .{
        .fooj = foo,
        .barj = bar,
    };
}

fn patchSignals(req: *tk.Request, res: *tk.Response) !void {
    const t1 = std.time.microTimestamp();

    // Outputs a formatted patch-signals SSE response to update signals
    var sse = try datastar.NewSSE(req, res);
    defer sse.close();

    const foo = prng.random().intRangeAtMost(u8, 0, 255);
    const bar = prng.random().intRangeAtMost(u8, 0, 255);

    try sse.patchSignals(.{
        .foo = foo,
        .bar = bar,
    }, .{}, .{});

    const t2 = std.time.microTimestamp();
    logz.info().string("event", "patchSignals").int("foo", foo).int("bar", bar).int("elapsed (μs)", t2 - t1).log();
}

fn patchSignalsOnlyIfMissing(req: *tk.Request, res: *tk.Response) !void {
    const t1 = std.time.microTimestamp();

    // these are short lived updates so we close the request as soon as its done
    var sse = try datastar.NewSSE(req, res);
    defer sse.close();

    // this will set the following signals
    const foo = prng.random().intRangeAtMost(u8, 1, 100);
    const bar = prng.random().intRangeAtMost(u8, 1, 100);

    try sse.patchSignals(
        .{
            .newfoo = foo,
            .newbar = bar,
        },
        .{},
        .{ .only_if_missing = true },
    );

    try sse.executeScript("console.log('Patched newfoo and newbar, but only if missing');", .{});

    const t2 = std.time.microTimestamp();
    logz.info().string("event", "patchSignals").int("foo", foo).int("bar", bar).int("elapsed (μs)", t2 - t1).log();
}

fn patchSignalsRemove(req: *tk.Request, res: *tk.Response, signals_to_remove: []const u8) !void {
    const t1 = std.time.microTimestamp();

    // const signals_to_remove: []const u8 = req.param("names").?;
    var names_iter = std.mem.splitScalar(u8, signals_to_remove, ',');

    // Would normally want to escape and validate the provided names here

    // these are short lived updates so we close the request as soon as its done
    var sse = try datastar.NewSSE(req, res);
    defer sse.close();

    var w = sse.patchSignalsWriter(.{});

    // Formatting of json payload
    const first = names_iter.next();
    if (first) |val| { // If receiving a list, send each signal to be removed
        var curr = val;
        _ = try w.write("{");
        while (names_iter.next()) |next| {
            try w.print("{s}: null, ", .{curr});
            curr = next;
        }
        try w.print("{s}: null }}", .{curr}); // Hack because trailing comma is not ok in json
    } else { // Otherwise, send only the single signal to be removed
        try w.print("{{ {s}: null }}", .{signals_to_remove});
    }

    const t2 = std.time.microTimestamp();
    logz.info().string("event", "patchSignalsRemove").string("remove", signals_to_remove).int("elapsed (μs)", t2 - t1).log();
}

fn executeScript(req: *tk.Request, res: *tk.Response, sample_id: u8) !void {
    const t1 = std.time.microTimestamp();

    // these are short lived updates so we close the request as soon as its done
    var sse = try datastar.NewSSE(req, res);
    defer sse.close();

    // make up an array of attributes for this
    var attribs = datastar.ScriptAttributes.init(res.arena);
    try attribs.put("type", "text/javascript");
    try attribs.put("trace", "true");
    try attribs.put("aardvark", "should appear last, not first");

    switch (sample_id) {
        1 => {
            try sse.executeScript("console.log('Running from executeScript() directly');", .{});
        },
        2 => {
            var w = sse.executeScriptWriter(.{
                .attributes = attribs,
            });
            try w.writeAll(
                \\console.log('Multiline Script, using executeScriptWriter and writing to it');
                \\parent = document.querySelector('#execute-script-page');
                \\console.log(parent.outerHTML);
            );
        },
        3 => {
            try sse.executeScriptFmt("console.log('Using formatted print {d}');", .{sample_id}, .{});
        },
        else => {
            try sse.executeScriptFmt("console.log('Unknown SampleID {d}');", .{sample_id}, .{});
        },
    }

    const t2 = std.time.microTimestamp();
    logz.info().string("event", "executeScript").int("sample_id", sample_id).int("elapsed (μs)", t2 - t1).log();
}

const snippets = [_][]const u8{
    @embedFile("snippets/code1.zig"),
    @embedFile("snippets/code2.zig"),
    @embedFile("snippets/code3.zig"),
    @embedFile("snippets/code4.zig"),
    @embedFile("snippets/code5t.zig"),
    @embedFile("snippets/code6.zig"),
    @embedFile("snippets/code7.zig"),
    @embedFile("snippets/code8.zig"),
};

fn code(req: *tk.Request, res: *tk.Response, snip_id: u8) !void {
    if (snip_id < 1 or snip_id > snippets.len) {
        return error.InvalidCodeSnippet;
    }

    const data = snippets[snip_id - 1];

    // create a buffer double the size of the snippet, to allow for brackets and extra HTML things
    // so it all fits nicely in a single write operation to the SSE stream
    const buffer: []u8 = try res.arena.alloc(u8, data.len * 2);
    var sse = try datastar.NewSSEBuffered(req, res, buffer);
    defer sse.close();

    const selector = try std.fmt.allocPrint(res.arena, "#code-{d}", .{snip_id});
    var w = sse.patchElementsWriter(.{
        .selector = selector,
        .mode = .append,
    });

    var it = std.mem.splitAny(u8, data, "\n");
    while (it.next()) |line| {
        try w.writeAll("<pre><code>");
        for (line) |c| {
            switch (c) {
                '<' => try w.writeAll("&lt;"),
                '>' => try w.writeAll("&gt;"),
                ' ' => try w.writeAll("&nbsp;"),
                else => try w.writeByte(c),
            }
        }
        try w.writeAll("</code></pre>\n");
    }
}
