pub const Command = enum {
    mergeFragments,
    mergeSignals,
    removeSignals,
    executeScript,
};

pub const MergeType = enum {
    morph,
    inner,
    outer,
    prepend,
    append,
    before,
    after,
    upsertAttributes,
};

pub const MergeFragmentsOptions = struct {
    merge_type: MergeType = .morph,
    selector: ?[]const u8 = null,
    view_transition: bool = false,
};

const Self = @This();

pub fn mergeFragments(stream: std.net.Stream) Message {
    return mergeFragmentsOpt(stream, .{});
}

pub fn mergeFragmentsOpt(stream: std.net.Stream, opt: MergeFragmentsOptions) Message {
    return Message.init(stream, .mergeFragments, opt);
}

pub fn removeFragments(stream: std.net.Stream, selector: []const u8) !void {
    const w = stream.writer();
    try w.print("event: datastar-remove-fragments\ndata: selector {s}\n\n", .{selector});
}

pub fn upsertAttributes(stream: std.net.Stream, selector: []const u8, attribs: []const u8) !void {
    const w = stream.writer();
    try w.print("event: datastar-merge-fragments\ndata: selector {s}\ndata: mergeMode upsertAttributes\ndata: fragments {s}\n\n", .{
        selector,
        attribs,
    });
}

pub const Message = struct {
    stream: std.net.Stream,
    started: bool = false,
    command: Command = .mergeFragments,
    merge_options: MergeFragmentsOptions = .{},
    only_if_missing: bool = false,

    const Writer = std.io.Writer(
        *Message,
        anyerror,
        write,
    );

    pub fn init(stream: std.net.Stream, comptime command: Command, opt: anytype) Message {
        var m = Message{ .stream = stream };
        switch (command) {
            .mergeFragments => {
                m.merge_options = opt;
            },
            else => {},
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
            .mergeFragments => {
                try w.writeAll("event: datastar-merge-fragments\n");
                if (self.merge_options.selector) |s| {
                    try w.print("data: selector {s}\n", .{s});
                }
                const mt = self.merge_options.merge_type;
                if (mt != .morph) {
                    try w.print("data: mergeMode {s}\n", .{@tagName(mt)});
                } // no modes specified - will default to "morph" using idiomoph
            },
            .mergeSignals => try w.writeAll("event: datastar-merge-signals\n"),
            .removeSignals => try w.writeAll("event: datastar-remove-signals\n"),
            .executeScript => try w.writeAll("event: datastar-execute-script\n"),
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
                try self.stream.writer().print("data: {s} {s}\n", .{
                    switch (self.command) {
                        .mergeFragments => "fragments",
                        .mergeSignals => "signals",
                        .removeSignals => "paths",
                        .executeScript => "script",
                    },
                    bytes[start..i],
                });
                start = i + 1;
            }
        }

        if (start < bytes.len) {
            try self.stream.writer().print("data: {s} {s}\n", .{
                switch (self.command) {
                    .mergeFragments => "fragments",
                    .mergeSignals => "signals",
                    .removeSignals => "paths",
                    .executeScript => "script",
                },
                bytes[start..],
            });
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
