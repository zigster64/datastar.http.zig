== executeScript handler ==

const sample = req.param("sample").?;
const sample_id = try std.fmt.parseInt(u8, sample, 10);

// these are short lived updates so we close the request as soon as its done
var sse = try datastar.NewSSE(req, res);
defer sse.close();

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
