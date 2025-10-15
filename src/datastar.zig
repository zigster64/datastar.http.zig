pub const Command = enum {
    patchElements,
    patchSignals,
    executeScript,
};

pub const PatchMode = enum {
    inner,
    outer,
    replace,
    prepend,
    append,
    before,
    after,
    remove,
};

pub const PatchElementsOptions = struct {
    mode: PatchMode = .outer,
    selector: ?[]const u8 = null,
    view_transition: bool = false,
    event_id: ?[]const u8 = null,
    retry_duration: ?i64 = null,
};

pub const PatchSignalsOptions = struct {
    only_if_missing: bool = false,
    event_id: ?[]const u8 = null,
    retry_duration: ?i64 = null,
};

pub const ScriptAttributes = std.StringArrayHashMap([]const u8);

pub const ExecuteScriptOptions = struct {
    auto_remove: bool = true, // by default remove the script after use, otherwise explicity set this to false if you want to keep the script loaded
    attributes: ?ScriptAttributes = null,
    event_id: ?[]const u8 = null,
    retry_duration: ?i64 = null,
};

const Config = struct {
    buffer_size: usize = 0,
    // ... other config options can be added here
};

var config: Config = .{};

pub fn configure(new_config: Config) void {
    config = new_config;
}

pub const SSE = struct {
    stream: std.net.Stream = undefined,
    msg: ?Message = null,
    buffer: []u8 = &.{},

    /// use close() to flush out the data to the SSE connection, then close the connection
    pub fn close(self: *SSE) void {
        self.flush() catch {};
        self.stream.close();
    }

    /// use flush() to flush out all the data to the SSE connection, keeps connection open
    pub fn flush(self: *SSE) !void {
        if (self.msg) |*msg| try msg.end();
    }

    pub fn writer(self: *Message) ?*std.Io.Writer {
        if (self.msg) |msg| {
            return &msg.interface;
        }
        return null;
    }

    pub fn patchElements(self: *SSE, elements: []const u8, opt: PatchElementsOptions) !void {
        try self.flush();
        var msg = Message.init(self.stream, .patchElements, opt, self.buffer);
        try msg.header();
        var w = &msg.interface;
        try w.writeAll(elements);
        try msg.end();
    }

    pub fn patchElementsFmt(self: *SSE, comptime elements: []const u8, args: anytype, opt: PatchElementsOptions) !void {
        try self.flush();
        var msg = Message.init(self.stream, .patchElements, opt, self.buffer);
        try msg.header();
        var w = &msg.interface;
        try w.print(elements, args);
        try msg.end();
    }

    pub fn patchElementsWriter(self: *SSE, opt: PatchElementsOptions) *std.Io.Writer {
        if (self.msg) |*msg| {
            msg.swapTo(.patchElements, opt);
        } else {
            self.msg = Message.init(self.stream, .patchElements, opt, self.buffer);
        }
        return &self.msg.?.interface;
    }

    pub fn patchSignals(self: *SSE, value: anytype, json_opt: std.json.Stringify.Options, opt: PatchSignalsOptions) !void {
        try self.flush();
        var msg = Message.init(self.stream, .patchSignals, opt, self.buffer);
        try msg.header();

        const json_formatter = std.json.fmt(value, json_opt);
        try json_formatter.format(&msg.interface);
        try msg.end();
    }

    pub fn patchSignalsWriter(self: *SSE, opt: PatchSignalsOptions) *std.Io.Writer {
        if (self.msg) |*msg| {
            msg.swapTo(.patchSignals, opt);
        } else {
            self.msg = Message.init(self.stream, .patchSignals, opt, self.buffer);
        }
        return &self.msg.?.interface;
    }

    pub fn executeScript(self: *SSE, script: []const u8, opt: ExecuteScriptOptions) !void {
        try self.flush();
        var msg = Message.init(self.stream, .executeScript, opt, self.buffer);
        var w = &msg.interface;
        try msg.header();
        try w.writeAll(script);
        try msg.end();
    }

    pub fn executeScriptFmt(self: *SSE, comptime script: []const u8, args: anytype, opt: ExecuteScriptOptions) !void {
        try self.flush();
        var msg = Message.init(self.stream, .executeScript, opt, self.buffer);
        var w = &msg.interface;
        try msg.header();
        try w.print(script, args);
        try msg.end();
    }

    pub fn executeScriptWriter(self: *SSE, opt: ExecuteScriptOptions) *std.Io.Writer {
        if (self.msg) |*msg| {
            msg.swapTo(.executeScript, opt);
        } else {
            self.msg = Message.init(self.stream, .executeScript, opt, self.buffer);
        }
        return &self.msg.?.interface;
    }
};

pub fn NewSSE(req: anytype, res: anytype) !SSE {
    _ = req;
    const stream = try res.startEventStreamSync();
    return SSE{
        .stream = stream,
        .buffer = blk: {
            if (config.buffer_size == 0) {
                break :blk &.{};
            }
            // std.debug.print("Applying config buffer size of {d}\n", .{config.buffer_size});
            break :blk try res.arena.alloc(u8, config.buffer_size);
        },
    };
}

pub fn NewSSEBuffered(req: anytype, res: anytype, buffer: []u8) !SSE {
    _ = req;
    const stream = try res.startEventStreamSync();
    return SSE{
        .stream = stream,
        .buffer = buffer,
    };
}

pub fn NewSSEFromStream(stream: std.net.Stream, buffer: []u8) SSE {
    return SSE{
        .stream = stream,
        .buffer = buffer,
    };
}

pub const Message = struct {
    stream: std.net.Stream,
    stream_writer: std.net.Stream.Writer,
    started: bool = false,
    command: Command = .patchElements,

    patch_element_options: PatchElementsOptions = .{},
    patch_signal_options: PatchSignalsOptions = .{},
    execute_script_options: ExecuteScriptOptions = .{},

    line_in_progress: bool = false,
    interface: std.Io.Writer,

    pub fn init(stream: std.net.Stream, comptime command: Command, opt: anytype, buffer: []u8) Message {
        var m = Message{
            .stream = stream,
            .stream_writer = stream.writer(&.{}),
            .command = command,
            .interface = .{
                .buffer = buffer, // by default is empty, but can be expanded using NewSSEBuffered()
                .vtable = &.{
                    .drain = &drain,
                },
            },
        };
        switch (command) {
            .patchElements => {
                m.patch_element_options = opt;
            },
            .patchSignals => {
                m.patch_signal_options = opt;
            },
            .executeScript => {
                m.execute_script_options = opt;
            },
        }
        return m;
    }

    pub fn swapTo(self: *Message, comptime command: Command, opt: anytype) void {
        // always just swap to new command
        self.end() catch {};
        self.command = command;
        switch (command) {
            .patchElements => {
                self.patch_element_options = opt;
            },
            .patchSignals => {
                self.patch_signal_options = opt;
            },
            .executeScript => {
                self.execute_script_options = opt;
            },
        }
    }

    pub fn end(self: *Message) !void {
        var me = &self.interface;
        try me.flush();
        if (self.started) {
            self.started = false;
            self.line_in_progress = false;
            var w = &self.stream_writer.interface;

            switch (self.command) {
                else => {},
                .executeScript => {
                    // need to close off the script tag !!
                    try w.writeAll("</script>");
                },
            }
            try w.writeAll("\n\n");
            try w.flush();
        }
    }

    pub fn header(self: *Message) !void {
        // var sw = self.stream.writer(&.{});
        var w = &self.stream_writer.interface;
        // TODO - apply all the other missing options that I havnt covered yet
        switch (self.command) {
            .patchElements => {
                try w.writeAll("event: datastar-patch-elements\n");
                if (self.patch_element_options.event_id) |event_id| {
                    try w.print("id: {s}\n", .{event_id});
                }
                if (self.patch_element_options.retry_duration) |retry| {
                    try w.print("retry: {}\n", .{retry});
                }
                if (self.patch_element_options.selector) |s| {
                    try w.print("data: selector {s}\n", .{s});
                }
                if (self.patch_element_options.view_transition) {
                    try w.print("data: useViewTransition true\n", .{});
                }
                const mt = self.patch_element_options.mode;
                switch (mt) {
                    .outer => {},
                    else => try w.print("data: mode {t}\n", .{mt}),
                }
            },
            .patchSignals => {
                try w.writeAll("event: datastar-patch-signals\n");
                if (self.patch_signal_options.event_id) |event_id| {
                    try w.print("id: {s}\n", .{event_id});
                }
                if (self.patch_signal_options.retry_duration) |retry| {
                    try w.print("retry: {}\n", .{retry});
                }
                if (self.patch_signal_options.only_if_missing) {
                    try w.writeAll("data: onlyIfMissing true\n");
                }
            },
            .executeScript => {
                try w.writeAll("event: datastar-patch-elements\n");
                if (self.execute_script_options.event_id) |event_id| {
                    try w.print("id: {s}\n", .{event_id});
                }
                if (self.execute_script_options.retry_duration) |retry| {
                    try w.print("retry: {}\n", .{retry});
                }
                try w.writeAll("data: mode append\ndata: selector body\ndata: elements <script");

                // now add the attribs if any are supplied
                if (self.execute_script_options.attributes) |attribs| {
                    for (attribs.keys(), attribs.values()) |key, value| {
                        try w.print(" {s}=\"{s}\"", .{ key, value });
                    }
                }
                if (self.execute_script_options.auto_remove) {
                    try w.writeAll(" data-effect=\"el.remove()\"");
                }

                // TODO - append the array of attribs here
                try w.writeAll(">");
                self.line_in_progress = true; // because the script content is appended to the script declaration line !!
            },
        }
        self.started = true;
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        var self: *Message = @fieldParentPtr("interface", w);
        _ = splat;

        // std.debug.print("Message.drain with buffer '{s}', end={d}, data = '{s}'\n", .{ w.buffered(), w.end, data[0] });

        // pub fn write(self: *Message, bytes: []const u8) !usize {
        if (!self.started) {
            try self.header();
        }

        var written: usize = 0;
        if (w.end > 0) {
            written += try writeBytes(self, &self.stream_writer.interface, w.buffered());
            // std.debug.print("Message.drain with non-empty buffer '{s}', end={d}, data = '{s}'\n", .{ w.buffered(), w.end, data[0] });
        }
        written += try writeBytes(self, &self.stream_writer.interface, data[0]);
        return w.consume(written);
    }

    fn writeBytes(self: *Message, sw: *std.Io.Writer, bytes: []const u8) std.Io.Writer.Error!usize {
        var start: usize = 0;
        for (bytes, 0..) |b, i| {
            if (b == '\n') {
                if (self.line_in_progress) {
                    try sw.print("{s}\n", .{bytes[start..i]});
                } else {
                    switch (self.command) {
                        .patchElements, .executeScript => {
                            try sw.print(
                                "data: elements {s}\n",
                                .{bytes[start..i]},
                            );
                        },
                        .patchSignals => {
                            try sw.print(
                                "data: signals {s}\n",
                                .{bytes[start..i]},
                            );
                        },
                    }
                }
                start = i + 1;
                self.line_in_progress = false;
            }
        }

        if (start < bytes.len) {
            if (self.line_in_progress) {
                try sw.print("{s}", .{bytes[start..]});
            } else {
                // is a completely new line
                switch (self.command) {
                    .patchElements, .executeScript => {
                        try sw.print(
                            "data: elements {s}",
                            .{bytes[start..]},
                        );
                    },
                    .patchSignals => {
                        try sw.print(
                            "data: signals {s}",
                            .{bytes[start..]},
                        );
                    },
                }
                self.line_in_progress = true;
            }
        }

        return bytes.len;
    }
};

pub fn readSignals(comptime T: type, req: anytype) !T {
    switch (req.method) {
        .GET => {
            const query = try req.query();
            const signals = query.get("datastar") orelse return error.MissingDatastarKey;
            return std.json.parseFromSliceLeaky(
                T,
                req.arena,
                signals,
                .{ .ignore_unknown_fields = true },
            );
        },
        else => {
            const body = req.body() orelse return error.MissingBody;
            return std.json.parseFromSliceLeaky(
                T,
                req.arena,
                body,
                .{ .ignore_unknown_fields = true },
            );
        },
    }
}

const SessionType = ?[]const u8;
const StreamList = std.ArrayList(std.net.Stream);

pub fn Subscribers(comptime T: type) type {
    return struct {
        gpa: Allocator,
        app: T,
        subs: Subscriptions,
        mutex: std.Thread.Mutex = .{},

        const Self = @This();
        const Subscription = struct {
            stream: std.net.Stream,
            action: Callback(T),
            session: SessionType = null,
        };
        const Subscriptions = std.StringHashMap(std.ArrayList(Subscription));

        pub fn init(gpa: Allocator, ctx: T) !Self {
            return .{
                .gpa = gpa,
                .app = ctx,
                .subs = Subscriptions.init(gpa),
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.subs) |s| {
                for (s) |sub| {
                    sub.stream.close() catch {};
                    if (sub.session != null) {
                        self.gpa.free(sub.session);
                    }
                }
                s.deinit();
            }
            self.sub.deinit();
        }

        pub fn subscribe(self: *Self, topic: []const u8, stream: std.net.Stream, func: Callback(T)) !void {
            return self.subscribeSession(topic, stream, func, null);
        }

        pub fn subscribeSession(self: *Self, topic: []const u8, stream: std.net.Stream, func: Callback(T), session: SessionType) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // check first that the given stream isnt already subscribed to this topic !!
            // if it is, then quit now, because they already have the most recent patch update
            // and we DONT want to get into a state where we close a socket then attempt to
            // write to it again in the same publish loop
            {
                if (self.subs.getPtr(topic)) |subs| {
                    for (subs.items) |sub| {
                        if (sub.stream.handle == stream.handle) {
                            std.debug.print("Stream {d} is already subscribed to topic {s} ... ignoring. Fix Your Code !\n", .{ stream.handle, topic });
                            return;
                        }
                    }
                }
            }
            // on first subscription, try to write the output first
            // if it works, then we add them to the subscriber list
            std.debug.print("calling the initial subscribe callback function for topic {s} on stream {d}\n", .{ topic, stream.handle });
            @call(.auto, func, .{ self.app, stream, session }) catch |err| {
                stream.close();
                return err;
            };

            var new_sub = Subscription{
                .stream = stream,
                .action = func,
            };
            if (session) |sv| {
                // we need to dupe the session passed in, because its often just a stack variable
                // pay careful attention to freeing this dupe whenever the session is terminated
                // which can happen during publish and it detects that the connection has closed
                new_sub.session = try self.gpa.dupe(u8, sv);
            }
            if (self.subs.getPtr(topic)) |subs| {
                try subs.append(self.gpa, new_sub);
            } else {
                var new_sublist: std.ArrayList(Subscription) = .empty;
                try new_sublist.append(self.gpa, new_sub);
                try self.subs.put(topic, new_sublist);
            }

            std.debug.print("Updated subs on topic {s} :\n", .{topic});
            for (self.subs.get(topic).?.items, 0..) |s, ii| {
                std.debug.print("  {d} - {any} Session {?s}\n", .{ ii, s.stream, s.session });
            }
        }

        fn purge(self: *Self, streams: StreamList) void {
            if (streams.items.len == 0) return;

            const t1 = std.time.microTimestamp();
            defer {
                std.debug.print("Purge took only {d}μs\n", .{std.time.microTimestamp() - t1});
            }

            // for each topic - go through all subscriptions and remove the matching stream
            var iterator = self.subs.iterator();
            while (iterator.next()) |*entry| {
                const topic = entry.key_ptr.*;
                var subs = entry.value_ptr;

                // traverse the list backwards, so its safe to drop elements during the traversal
                var i: usize = subs.items.len;
                while (i > 0) {
                    i -= 1;
                    const sub = subs.items[i];
                    for (streams.items) |stream| {
                        if (sub.stream.handle == stream.handle) {
                            _ = subs.swapRemove(i);
                            std.debug.print("Closing subscriber {}:{d} on topic {s}\n", .{ i, sub.stream.handle, topic });
                        }
                    }
                }
            }
        }

        pub fn publish(self: *Self, topic: []const u8) !void {
            return self.publishSession(topic, null);
        }

        pub fn publishSession(self: *Self, topic: []const u8, session: SessionType) !void {
            self.mutex.lock();
            var dead_streams: StreamList = .empty;
            defer {
                if (dead_streams.items.len > 0) {
                    self.purge(dead_streams);
                }
                dead_streams.deinit(self.gpa);
                self.mutex.unlock();
            }

            // std.debug.print("publish on topic {s} for session {?s}\n", .{ topic, session });
            if (self.subs.getPtr(topic)) |subs| {
                // traverse the list backwards, so its safe to drop elements during the traversal
                var i: usize = subs.items.len;
                while (i > 0) {
                    i -= 1;
                    var sub = subs.items[i];
                    if (sub.session == null) {
                        // we publish everything, without passing a session value
                        // std.debug.print("calling the publish callback for topic {s} on stream {d}\n", .{ topic, sub.stream.handle });
                        @call(.auto, sub.action, .{ self.app, sub.stream, null }) catch |err| {
                            switch (err) {
                                error.NotOpenForWriting => {},
                                else => {
                                    sub.stream.close();
                                },
                            }
                            try dead_streams.append(self.gpa, sub.stream);
                        };
                    } else {
                        if (session) |sv| {
                            // only publish subs where the session value matches what we ask for
                            if (sub.session) |ss| {
                                if (std.mem.eql(u8, sv, ss)) {
                                    // std.debug.print("calling the publish callback for topic {s} on stream {d} with session {s}\n", .{ topic, sub.stream.handle, ss });
                                    @call(.auto, sub.action, .{ self.app, sub.stream, ss }) catch |err| {
                                        switch (err) {
                                            error.NotOpenForWriting => {},
                                            else => {
                                                sub.stream.close();
                                            },
                                        }
                                        if (sub.session) |subsession| self.gpa.free(subsession);
                                        try dead_streams.append(self.gpa, sub.stream);
                                    };
                                }
                            }
                        } else {
                            // publish all
                            // std.debug.print("calling the publish callback for topic {s} on stream {d} with session {?s}\n", .{ topic, sub.stream.handle, sub.session });
                            @call(.auto, sub.action, .{ self.app, sub.stream, sub.session }) catch |err| {
                                switch (err) {
                                    error.NotOpenForWriting => {},
                                    else => {
                                        sub.stream.close();
                                    },
                                }
                                if (sub.session) |subsession| self.gpa.free(subsession);
                                try dead_streams.append(self.gpa, sub.stream);
                            };
                        }
                    }
                }

                std.debug.print("Remaining subs on topic {s} :\n", .{topic});
                for (subs.items, 0..) |s, ii| {
                    std.debug.print("  {d} - {any} Session {?s}\n", .{ ii, s.stream, s.session });
                }
            }
        }
    };
}

pub fn Callback(comptime ctx: type) type {
    if (ctx == void) {
        return *const fn (std.net.Stream) anyerror!void;
    }
    return *const fn (ctx, std.net.Stream, SessionType) anyerror!void;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
