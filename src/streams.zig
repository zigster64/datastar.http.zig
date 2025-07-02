// Streams is an arraylist of IO streams that represent open connections
// we subscribe long running requests and store the io stream and the signals
// to be applied
gpa: std.mem.Allocator,
streams: std.ArrayList(std.net.Stream),
mutex: std.Thread.Mutex = .{},

pub fn init(gpa: std.mem.Allocator) Streams {
    return .{
        .gpa = gpa,
        .streams = std.ArrayList(std.net.Stream).init(gpa),
        .subscriptions = std.StringHashMap(std.net.Stream).init(gpa),
    };
}

pub fn deinit(self: *Streams) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    for (self.streams.items) |s| {
        s.close();
    }
    self.streams.deinit();
    self.subscriptions.deinit();
}

// add a new stream, and return its unique id
pub fn add(self: *Streams, stream: std.net.Stream) !usize {
    self.mutex.lock();
    defer self.mutex.unlock();
    const index = self.streams.items.len;
    try self.streams.append(stream);
    return index;
}

// add a stream and subscribe it to a topic
// then call the first instance of it being run
// TODO - add signals to the the call
pub fn subscribe(self: *Streams, stream: std.net.Stream, topic: []const u8, ctx: anytype, func: anytype) !void {
    _ = try self.add(stream);
    try self.subscriptions.put(topic, stream);
}

pub fn remove(self: *Streams, index: usize) void {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (index < self.streams.items.len) {
        _ = self.streams.swapRemove(index);
    }
}

pub fn get(self: *Streams, index: usize) ?std.net.Stream {
    self.mutex.lock();
    defer self.mutex.unlock();
    if (index < self.streams.items.len) {
        return self.streams.items[index];
    }
    return null;
}

pub fn lock(self: *Streams) void {
    self.mutex.lock();
}

pub fn unlock(self: *Streams) void {
    self.mutex.unlock();
}

const Streams = @Self();
pub const std = @import("std");
