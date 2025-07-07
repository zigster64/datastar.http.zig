== patchSignalsOnlyIfMissing handler ==

// these are short lived updates so we close the request as soon as its done
const stream = try res.startEventStreamSync();
defer stream.close();

var msg = datastar.patchSignalsIfMissing(stream);
defer msg.end();

// create a random color

var w = msg.writer();

// this will set the following signals
const foo = prng.random().intRangeAtMost(u8, 1, 100);
const bar = prng.random().intRangeAtMost(u8, 1, 100);
try w.print("{{ foo: {d}, bar: {d} }}", .{ foo, bar }); // first will update only
