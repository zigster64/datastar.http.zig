== executeScript handler ==

const sample = req.param("sample").?;
const sample_id = try std.fmt.parseInt(u8, sample, 10);

// these are short lived updates so we close the request as soon as its done
var sse = try datastar.NewSSE(req, res);
defer sse.close();

var w = sse.executeScript(.{});

const script_data = if (sample_id == 1)
    "console.log('Running from executescript!');"
else
    \\parent = document.querySelector('#executescript-card');
    \\console.log(parent.outerHTML);
;

try w.writeAll(script_data);
