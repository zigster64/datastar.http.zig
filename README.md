# Datastar lib for http.zig

A Zig library that conforms to the Datastar SDK specification.

https://github.com/starfederation/datastar/blob/develop/sdk/ADR.md

This SDK uses streams all the way down, so there is no implicit extra allocations.

Current version is based on Zig 0.15.2, and uses the latest master of http.zig

So this will work with custom apps using http.zig, as well as jetzig / tokamak, etc

Future updates will include support for Zig stdlib http server, as well as 
other popular HTTP server libs, such as zzz and tardy.

Future updates will provide example apps that demonstrate using jetzig and tokamak as well.

# Validation Test

When you run `zig build`, it will compile several apps into `./zig-out/bin` including a binary called `validation-test`

Run `./zig-out/bin/validation-test`, which will start a server on port 7331

Then follow the procedure documented at

https://github.com/starfederation/datastar/blob/main/sdk/tests/README.md

To run the official Datastar validation suite against this test harness

The source code for the `validation-test` program is in the file `tests/validation.zig`

Current version passes all tests.


# Example Apps

When you run `zig build` it will compile several apps into `./zig-out/bin/` to demonstrate using different parts 
of the api

Using http.zig :

- example_1  shows using the Datastar API using basic SDK handlers
- example_2  shows an example multi-user auction site for cats with realtime updates using pub/sub
- example_22 Same cat auction as above, but with per-user preferences, all handled on the backend only

<!-- - example_3  shows an example multi-user pigeon racing betting site with realtime updates -->
<!-- - example_4  shows an example multi-game, multi-player TicTacToe site, using the backstage actor framework -->

- example_5  shows an example multi-player Gardening Simulator using pub/sub

Using zig stdlib http server :

<!-- - example_10 as per example_1, but using zig stdlib instead of http.zig -->


# Installation and Usage

To build an application using this SDK

1) Add datastar.http.zig as a dependency in your `build.zig.zon`:

```bash
zig fetch --save="datastar" "git+https://github.com/zigstser64/datastar.http.zig#master"
```

2) In your `build.zig`, add the `datastar` module as a dependency you your program:

```zig
const datastar = b.dependency("datastar", .{
    .target = target,
    .optimize = optimize,
});

// the executable from your call to b.addExecutable(...)
exe.root_module.addImport("datastar", httpz.module("datastar"));
```


# Functions

## The SSE Object

Calling NewSSE, passing a request and response, will return an object of type SSE.

```zig
    pub fn NewSSE(req, res) !SSE 
```

This will configure the connnection for SSE transfers, and provides an object with Datastar methods for
patching elements, patching signals, executing scripts, etc.

When you are finished with the SSE object, you should either :

- Call `sse.close()` if you are done and want to close the connection as part of your handler.

- Otherwise, the SSE connection is left open after you exit your handler function. In this case, you can 
  access the `sse.stream: std.net.Stream` value and store it somewhere for additional updates over that open connection. 

- This Zig SDK also includes a simple Pub/Sub subsystem that takes care o  tracking open connections in a convenient manner, or you can use the value `sse.stream` to roll your own as well. 


# Using the Datastar SDK

## Reading Signals from the request

```zig
    pub fn readSignals(comptime T: type, req: anytype) !T
```

Will take a Type (struct) and a HTTP request, and returns a filled in struct of the requested type.

If the request is a `HTTP GET` request, it will extract the signals from the query params. You will see that 
your GET requests have a `?datastar=...` query param in most cases. This is how Datastar passes signals to
your backend via a GET request.

If the request is a `HTTP POST` or other request that uses a payload body, this function will use the 
payload body to extract the signals. This is how Datastar passes signals to your backend when using POST, etc.

Either way, provide `readSignals` with a type that you want to read the signals into, and it will use the
request method to work out which way to fill in the struct.

Example :
```zig
    const FooBar = struct {
        foor: []const u8,
        bar: []const u8,
    };

    const signals = try datastar.readSignals(FooBar, req);
    std.debug.print("Request sent foo: {s}, bar: {s}\n", .{signals.foo, signals.bar});
```


## Patching Elements

The SDK Provides 3 functions to patch elements over SSE.

These are all member functions of the SSE type that NewSSE(req, res) returns.


```zig
    pub fn patchElements(self: *SSE, elements: []const u8, opt: PatchElementsOptions) !void

    pub fn patchElementsFmt(self: *SSE, comptime elements: []const u8, args: anytype, opt: PatchElementsOptions) !void

    pub fn patchElementsWriter(self: *SSE, opt: PatchElementsOptions) *std.Io.Writer 
```

Use `sse.patchElements` to directly patch the DOM with the given "elements" string.

Use `sse.patchElementsFmt` to directly patch the DOM with a formatted print (where elements,args is the format string + args).

Use `sse.patchElementsWriter` to return a std.Io.Writer object that you can programmatically write to using complex logic.

If using the Writer, then be sure to call `sse.flush()` when you are finished writing to it and wish to keep the socket open, and writing to the same patchElements stream later.

Calling `sse.close()` will automatically flush the writer output.

Starting any new patchElements / patchSignals / executeScript on the SSE object will automatically flush the last writer as well.


PatchElementsOptions is defined as :

```zig
pub const PatchElementsOptions = struct {
    mode: PatchMode = .outer,
    selector: ?[]const u8 = null,
    view_transition: bool = false,
    event_id: ?[]const u8 = null,
    retry_duration: ?i64 = null,
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
```

See the Datastar documentation for the usage of these options when using patchElements.

https://data-star.dev/reference/sse_events

Most of the time, you will want to simply pass an empty tuple `.{}` as the options parameter. 

Example handler (from `examples/01_basic.zig`)

```zig
fn patchElements(req: *httpz.Request, res: *httpz.Response) !void {
    var sse = try datastar.NewSSE(req, res);
    defer sse.close();

    try sse.patchElementsFmt(
        \\<p id="mf-patch">This is update number {d}</p>
    ,
        .{getCountAndIncrement()},
        .{},
    );
}
```

## Patching Signals

The SDK provides 2 functions to patch signals over SSE.

These are all member functions of the SSE type that NewSSE(req, res) returns.

```zig
    pub fn patchSignals(self: *SSE, value: anytype, json_opt: std.json.Stringify.Options, opt: PatchSignalsOptions) !void

    pub fn patchSignalsWriter(self: *SSE, opt: PatchSignalsOptions) *std.Io.Writer
```

PatchSignalsOptions is defined as :
```zig
pub const PatchSignalsOptions = struct {
    only_if_missing: bool = false,
    event_id: ?[]const u8 = null,
    retry_duration: ?i64 = null,
};
```

Use `patchSignals` to directly patch the signals, passing in a value that will be JSON stringified into signals.

Use `patchSignalsWriter` to return a std.Io.Writer object that you can programmatically write raw JSON to.

Example handler (from `examples/01_basic.zig`)
```zig
fn patchSignals(req: *httpz.Request, res: *httpz.Response) !void {
    var sse = try datastar.NewSSE(req, res);
    defer sse.close();

    const foo = prng.random().intRangeAtMost(u8, 0, 255);
    const bar = prng.random().intRangeAtMost(u8, 0, 255);

    try sse.patchSignals(.{
        .foo = foo,
        .bar = bar,
    }, .{}, .{});
}
```

## Executing Scripts

The SDK provides 3 functions to initiate executing scripts over SSE.

```zig

    pub fn executeScript(self: *SSE, script: []const u8, opt: ExecuteScriptOptions) !void

    pub fn executeScriptFmt(self: *SSE, comptime script: []const u8, args: anytype, opt: ExecuteScriptOptions) !void 

    pub fn executeScriptWriter(self: *SSE, opt: ExecuteScriptOptions) *std.Io.Writer
```

ExecuteScriptOptions is defined as :
```zig
pub const ExecuteScriptOptions = struct {
    auto_remove: bool = true, // by default remove the script after use, otherwise explicity set this to false if you want to keep the script loaded
    attributes: ?ScriptAttributes = null,
    event_id: ?[]const u8 = null,
    retry_duration: ?i64 = null,
};
```

Use `executeScript` to send the given script to the frontend for execution.

Use `executeScriptFmt` to use a formatted print to create the script, and send it to the frontend for execution. 
Where (script, args) is the same as print(format, args).

Use `executeScriptWriter` to return a std.Io.Writer object that you can programmatically write the script to, for
more complex cases.

Example handler (from `examples/01_basic.zig`)
```zig
fn executeScript(req: *httpz.Request, res: *httpz.Response) !void {
    const value = req.param("value"); // can be null

    var sse = try datastar.NewSSE(req, res);
    defer sse.close();

    try sse.executeScriptFmt("console.log('You asked me to print {s}')"", .{
            value orelse "nothing at all",
    });
}
```

# Publish and Subscribe

** EXPERIMENTAL - WILL CHANGE **


## Attaching to an existing open SSE connection

In your callback function where you want to publish a result to an existing open SSE connection, you will need to get an SSE object from that stream first.

You can then use this SSE object to patchElements / patchSignals / executeScripts, etc

Use this function, which takes an existing open std.net.Stream, and an optional buffer to use for writes.

(ie - you can set it to the empty buffer &.{} for an unbuffered writer).


```zig
    pub fn NewSSEFromStream(stream: std.net.Stream, buffer: []u8) SSE
```

If using this method, you MUST use `sse.flush()` when you are finished.

Simplifed Example, from `examples/02_cats.zig` in the `publishCatList` function :

```zig

pub fn publishCatList(app: *App, stream: std.net.Stream, _: ?[]const u8) !void {

    // get an SSE object for the given stream
    var buffer: [1024]u8 = undefined;
    var sse = datastar.NewSSEFromStream(stream, &buffer);

    // Set the sse to PatchElements, and return us a writer
    var w = sse.patchElementsWriter(.{});

    // setup a grid to display the cats in
    try w.writeAll(
        \\<div id="cat-list" class="grid grid-cols-3>
    );

    // each cat object can render itself to the given writer
    for (app.cats.items) |cat| {
        try cat.render(w);
    }

    // finish the original grid
    try w.writeAll(
        \\</div>
    );

    try sse.flush(); // dont forget to flush !
```

# Advanced Topics

## SSE IO, buffering and async socket writes

Since Zig 0.15, IO and buffering are now a big deal, and offers some extreme options for fine tuning and optimizing your systems.  This is a good thing, and lots of fun to experiment with.

The SSE object uses a std.Io.Writer stream to convert normal HTML Element, Signal and Script updates into the Datastar protocol, and then write them to the browser's connection.

By default this std.Io.Writer uses a zero-sized intermediate buffer, so every chunk written is passed straight through to the underlying socket writer after being converted to Datastar protocol.

With http.zig, this underlying socket writer is already buffered, and uses async IO to drain data to the user's browser in the background after your handler exits. This is all taken care of for you.

For most applications, these defaults offer an excellent balance between performance and memory consumption.

For advanced use cases, you can opt in for applying buffering to the SSE operations as well, by setting a default buffer size. 

This will reduce the number of writes between the SSE processor and the underlying http.zig writer to the browser, at the expense of one extra allocation per request.

To configure buffering, use this : 

```zig
    datastar.configure(.{ .buffer_size = 255 });
```

If your handlers are typically doing a large number of small writes inside a patchElements operation, then its definitely worth thinking about using a buffer for this.

If you are using formatted printing a lot (either through `w.print(...) or sse.patchElementsFmt(...)`), then that will generate a larger number of small writes as well, as the print 
formatter likes to output fragments of your string, and each argument all as separate write operations.

The performance differences between using a buffer or not can be quite marginal (we are talking microseconds if at all), but its there if you think you need it. 

If you choose to use this, try and set the size of the buffer around the size of your most common smaller outputs, which could be 200-300 bytes depending on your application, or it could be a lot more.

For example - if you set the buffer size to 200, then write 500 bytes to it, you will end up with 3 writes to the underlying stream - 1 for each time the buffer is full, then 1 more to flush the remainder.

The SDK automatically takes care of flushing these intermediate buffers for you.

Benchmark, experiment, and make your own decision about whether buffering improves your app or not, and use what works best for you.

## Using custom buffering for a specific SSE object

In some rare cases, you may want to apply a custom buffer to the SSE stream outside of the default configuration.

Use 

```zig
    pub fn NewSSEBuffered(req, res, buffer) !SSE 
```

For example - see `fn code()` in `examples/01_basic.zig`, where it provides its own buffer to the SSE object, where the size is calculated in advance based on the size 
of the payload.

This is because the `code()` fn uses a tight loop that writes 1 byte at a time to the output. 
This custom sized buffer allows the whole output  bnto be written into memory before being passed on to the socket writer.

Consider using this if you have a rare case that makes sense.

# Contrib Policy

All contribs welcome.

Please raise a github issue first before adding a PR, and reference the issue in the PR title. 

This allows room for open discussion, as well as tracking of issues opened and closed.


# LLM Policy

Avoid LLM like the plague please.

By all means use it for rubber ducking, but dont trust any code it produces, especially with Zig latest, let alone Datastar latest.

Its just not there yet (even if it looks convincing sometimes)


