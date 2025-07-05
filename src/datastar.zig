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
};

const Self = @This();

pub fn patchElements(stream: std.net.Stream) Message {
    return patchElementsOpt(stream, .{});
}

pub fn patchElementsOpt(stream: std.net.Stream, opt: PatchElementsOptions) Message {
    return Message.init(stream, .patchElements, opt);
}

pub fn patchSignals(stream: std.net.Stream) Message {
    return Message.init(stream, .patchSignals, false);
}

pub fn patchSignalsIfMissing(stream: std.net.Stream) Message {
    return Message.init(stream, .patchSignals, true);
}

pub fn executeScript(stream: std.net.Stream) Message {
    return Message.init(stream, .executeScript, true);
}

pub fn executeScriptKeep(stream: std.net.Stream) Message {
    return Message.init(stream, .executeScript, false);
}

pub fn removeElements(stream: std.net.Stream, selector: []const u8) !void {
    const w = stream.writer();
    try w.print("event: datastar-patch-elements\ndata: mode remove\ndata: selector {s}\n\n", .{selector});
}

pub const Message = struct {
    stream: std.net.Stream,
    started: bool = false,
    command: Command = .patchElements,
    patch_options: PatchElementsOptions = .{},
    only_if_missing: bool = false,
    line_in_progress: bool = false,
    keep_script: bool = false,

    const Writer = std.io.Writer(
        *Message,
        anyerror,
        write,
    );

    pub fn init(stream: std.net.Stream, comptime command: Command, opt: anytype) Message {
        var m = Message{ .stream = stream, .command = command };
        switch (command) {
            .patchElements => {
                m.patch_options = opt; // must be a PatchElementsOptions
            },
            .patchSignals => {
                m.only_if_missing = opt; // must be a bool
            },
            .executeScript => {
                m.keep_script = opt; // must be a bool
            },
        }
        return m;
    }

    pub fn messageType(self: *Message, protocol: Command) void {
        if (self.protocol == protocol) {
            return;
        }
        // swap to new protocol
        self.end();
        self.protocol = protocol;
    }

    pub fn end(self: *Message) void {
        if (self.started) {
            self.started = false;
            self.stream.writer().writeAll("\n\n") catch return;
        }
    }

    pub fn header(self: *Message) !void {
        var w = self.stream.writer();
        switch (self.command) {
            .patchElements => {
                try w.writeAll("event: datastar-patch-elements\n");
                if (self.patch_options.selector) |s| {
                    try w.print("data: selector {s}\n", .{s});
                }
                const mt = self.patch_options.mode;
                switch (mt) {
                    .outer => {},
                    else => try w.print("data: mode {s}\n", .{@tagName(mt)}),
                }
            },
            .patchSignals => {
                try w.writeAll("event: datastar-patch-signals\n");
                if (self.only_if_missing) {
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

    pub fn write(self: *Message, bytes: []const u8) !usize {
        if (!self.started) {
            try self.header();
        }

        var start: usize = 0;

        for (bytes, 0..) |b, i| {
            if (b == '\n') {
                if (self.line_in_progress) {
                    try self.stream.writer().print("{s}\n", .{bytes[start..i]});
                } else {
                    switch (self.command) {
                        .patchElements => {
                            try self.stream.writer().print(
                                "data: elements {s}\n",
                                .{bytes[start..i]},
                            );
                        },
                        .patchSignals => {
                            try self.stream.writer().print(
                                "data: signals {s}\n",
                                .{bytes[start..i]},
                            );
                        },
                        .executeScript => {
                            try self.stream.writer().print(
                                "data: elements <script{s}>{s}</script>\n",
                                .{
                                    if (self.keep_script) "" else " data-effect='el.remove()'",
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
                try self.stream.writer().print("{s}", .{bytes[start..]});
            } else {
                // is a completely new line
                switch (self.command) {
                    .patchElements => {
                        try self.stream.writer().print(
                            "data: elements {s}",
                            .{bytes[start..]},
                        );
                    },
                    .patchSignals => {
                        try self.stream.writer().print(
                            "data: signals {s}",
                            .{bytes[start..]},
                        );
                    },
                    .executeScript => {
                        try self.stream.writer().print(
                            "data: elements <script{s}>{s}</script>",
                            .{
                                if (self.keep_script) "" else " data-effect='el.remove()'",
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

    pub fn writer(self: *Message) Writer {
        return .{ .context = self };
    }
};

pub fn readSignals(comptime T: type, req: *httpz.Request) !T {
    switch (req.method) {
        .GET => {
            const query = try req.query();
            const signals = query.get("datastar") orelse return error.MissingDatastarKey;
            return std.json.parseFromSliceLeaky(T, req.arena, signals, .{});
        },
        else => {
            const body = req.body() orelse return error.MissingBody;
            return std.json.parseFromSliceLeaky(T, req.arena, body, .{});
        },
    }
}

const std = @import("std");
const httpz = @import("httpz");
