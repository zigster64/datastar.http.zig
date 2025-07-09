// Streams is an arraylist of IO streams that represent open connections
// we subscribe long running requests and store the io stream and the signals
// to be applied

const Streams = @This();

gpa: std.mem.Allocator,
mutex: std.Thread.Mutex = .{},
subscriptions: std.StringHashMap(std.ArrayList(std.net.Stream)),

pub fn init(gpa: std.mem.Allocator) Streams {
    return .{
        .gpa = gpa,
        .subscriptions = std.StringHashMap(std.ArrayList(std.net.Stream)).init(gpa),
    };
}

pub fn deinit(self: *Streams) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    for (self.subscriptions.items) |subs| {
        for (subs.items) |s| {
            s.close();
        }
        subs.deinit();
    }
    self.subscriptions.deinit();
}

// add a stream and subscribe it to a topic
pub fn subscribe(self: *Streams, stream: std.net.Stream, topic: []const u8) !void {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (self.subscriptions.getPtr(topic)) |subs| {
        try subs.append(stream);
    } else {
        var sublist = std.ArrayList(std.net.Stream).init(self.gpa);
        try sublist.append(stream);
        try self.subscriptions.put(topic, sublist);
    }
}

pub fn remove(self: *Streams, topic: []const u8, stream: std.net.Stream) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    var subs = self.subscriptions.get(topic) orelse return;

    for (subs.items, 0..) |sub, i| {
        if (sub == stream) {
            std.debug.print("remove stream {s}:{any}\n", .{ topic, stream });
            _ = subs.items.swapRemove(i);
        }
    }
}

pub fn lock(self: *Streams) void {
    self.mutex.lock();
}

pub fn unlock(self: *Streams) void {
    self.mutex.unlock();
}

const std = @import("std");
