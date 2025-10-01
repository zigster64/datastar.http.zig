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
    event_id: ?[]const u8 = null, // TODO - add this to the output
    retry_duration: ?i64 = null, // TODO - add this to the output
};

pub const PatchSignalsOptions = struct {
    only_if_missing: bool = false,
    event_id: ?[]const u8 = null, // TODO - add this to the output
    retry_duration: ?i64 = null, // TODO - add this to the output
};

pub const ExecuteScriptOptions = struct {
    auto_remove: bool = true, // by default remove the script after use, otherwise explicity set this to false if you want to keep the script loaded
    attributes: ?[][]const u8 = null,
    event_id: ?[]const u8 = null,
    retry_duration: ?i64 = null, // TODO - add this to the output
};

pub const SSE = struct {
    stream: std.net.Stream = undefined,
    msg: ?Message = null,

    /// use close() to flush out the data to the SSE connection, then close the connection
    pub fn close(self: *SSE) void {
        self.flush();
        self.stream.close();
    }

    /// use flush() to flush out all the data to the SSE connection, keeps connection open
    pub fn flush(self: *SSE) void {
        if (self.msg) |*msg| msg.end();
    }

    pub fn writer(self: *Message) ?*std.Io.Writer {
        if (self.msg) |msg| {
            return &msg.interface;
        }
        return null;
    }

    pub fn patchElements(self: *SSE, opt: PatchElementsOptions) *std.Io.Writer {
        if (self.msg) |*msg| {
            msg.swapTo(.patchElements, opt);
        } else {
            self.msg = Message.init(self.stream, .patchElements, opt);
        }
        return &self.msg.?.interface;
    }

    pub fn patchSignals(self: *SSE, opt: PatchSignalsOptions) *std.Io.Writer {
        if (self.msg) |*msg| {
            msg.swapTo(.patchSignals, opt);
        } else {
            self.msg = Message.init(self.stream, .patchSignals, opt);
        }
        return &self.msg.?.interface;
    }

    pub fn executeScript(self: *SSE, opt: ExecuteScriptOptions) *std.Io.Writer {
        if (self.msg) |*msg| {
            msg.swapTo(.executeScript, opt);
        } else {
            self.msg = Message.init(self.stream, .executeScript, opt);
        }
        return &self.msg.?.interface;
    }

    // pub fn removeElements(stream: std.net.Stream, selector: []const u8) !void {
    //     const w = stream.writer();
    //     try w.print("event: datastar-patch-elements\ndata: mode remove\ndata: selector {s}\n\n", .{selector});
    // }
};

pub fn NewSSE(req: anytype, res: anytype) !SSE {
    _ = req;
    const stream = try res.startEventStreamSync();
    return SSE{
        .stream = stream,
    };
}

pub const Message = struct {
    stream: std.net.Stream,
    started: bool = false,
    command: Command = .patchElements,

    patch_element_options: PatchElementsOptions = .{},
    patch_signal_options: PatchSignalsOptions = .{},
    execute_script_options: ExecuteScriptOptions = .{},

    line_in_progress: bool = false,
    interface: std.Io.Writer,

    // const Writer = std.io.Writer(
    //     *Message,
    //     anyerror,
    //     write,
    // );

    pub fn init(stream: std.net.Stream, comptime command: Command, opt: anytype) Message {
        var m = Message{
            .stream = stream,
            .command = command,
            .interface = .{
                .buffer = &.{},
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
        self.end();
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

    pub fn end(self: *Message) void {
        if (self.started) {
            self.started = false;
            self.line_in_progress = false;
            var sw = self.stream.writer(&.{});
            var w = &sw.interface;
            w.writeAll("\n\n") catch return;
            w.flush() catch return;
        }
    }

    pub fn header(self: *Message) !void {
        var sw = self.stream.writer(&.{});
        var w = &sw.interface;
        // TODO - apply all the other missing options that I havnt covered yet
        switch (self.command) {
            .patchElements => {
                try w.writeAll("event: datastar-patch-elements\n");
                if (self.patch_element_options.selector) |s| {
                    try w.print("data: selector {s}\n", .{s});
                }
                const mt = self.patch_element_options.mode;
                switch (mt) {
                    .outer => {},
                    else => try w.print("data: mode {s}\n", .{@tagName(mt)}),
                }
            },
            .patchSignals => {
                try w.writeAll("event: datastar-patch-signals\n");
                if (self.patch_signal_options.only_if_missing) {
                    try w.writeAll("data: onlyIfMissing true\n");
                }
            },
            .executeScript => {
                try w.writeAll(
                    \\event: datastar-patch-elements
                    \\data: mode append
                    \\data: selector body
                    \\
                );
            },
        }
        self.started = true;
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        var self: *Message = @fieldParentPtr("interface", w);
        _ = splat;

        // nothing in buffer yet - will allow buffering later

        // pub fn write(self: *Message, bytes: []const u8) !usize {
        if (!self.started) {
            try self.header();
        }

        var start: usize = 0;
        const bytes = data[0];
        var swriter = self.stream.writer(&.{});
        var sw = &swriter.interface;

        for (bytes, 0..) |b, i| {
            if (b == '\n') {
                if (self.line_in_progress) {
                    try sw.print("{s}\n", .{bytes[start..i]});
                } else {
                    switch (self.command) {
                        .patchElements => {
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
                        .executeScript => {
                            try sw.print(
                                "data: elements <script{s}>{s}</script>\n",
                                .{
                                    if (!self.execute_script_options.auto_remove) "" else " data-effect='el.remove()'",
                                    bytes[start..i],
                                },
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
                    .patchElements => {
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
                    .executeScript => {
                        try sw.print(
                            "data: elements <script{s}>{s}</script>",
                            .{
                                if (!self.execute_script_options.auto_remove) "" else " data-effect='el.remove()'",
                                bytes[start..],
                            },
                        );
                    },
                }
                self.line_in_progress = true;
            }
        }

        return bytes.len;
    }

    // pub fn writer(self: *Message) Writer {
    //     return .{ .context = self };
    // }
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
