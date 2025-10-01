== patchSignalsRemove handler ==

const signals_to_remove: []const u8 = req.param("names").?;
var names_iter = std.mem.splitScalar(u8, signals_to_remove, ',');

// Would normally want to escape and validate the provided names here

// these are short lived updates so we close the request as soon as its done
var sse = try datastar.NewSSE(req, res);
defer sse.close();

var w = sse.patchSignals(.{});

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
