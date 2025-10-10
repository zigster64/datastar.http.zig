# Datastar lib for http.zig

A Zig library that conforms to the DataStar SDK specification.

https://github.com/starfederation/datastar/blob/develop/sdk/ADR.md

This SDK uses streams all the way down, so there is no implicit extra allocations.

Current version is based on Zig 0.15.1, and uses the latest master of http.zig

So this will work with custom apps using http.zig / jetzig / tokamak, etc

Future updates will include support for Zig stdlib http server, as well as 
other popular HTTP server libs, such as zzz and tardy.

# Validation Test

** TODO ** - validation-test isnt there yet. Will update once its complete **

When you run `zig build`, it will compile several apps into `./zig-out/bin` including a binary called `validation-test`

Run `./zig-out/bin/validation-test`, which will start a server on port 7331

Then follow the procedure documented at

https://github.com/starfederation/datastar/blob/main/sdk/tests/README.md

To run the official DataStar validation suite against this test harness


# Example Apps

When you run `zig build` it will compile several apps into `./zig-out/bin/` to demonstrate using different parts 
of the api

Using http.zig :

- example_1  shows using the DataStar API using basic SDK handlers
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

This will configure the connnection for SSE transfers, and provides an object with DataStar methods for
patching elements, patching signals, executing scripts, etc.

When you are finished with the SSE object, you should either :

- Call `sse.close()` if you are done and want to close the connection as part of your handler.

- Otherwise, the SSE connection is left open after you exit your handler function. In this case, you can 
  access the `sse.stream: std.net.Stream` value and store it somewhere for additional updates over that open connection. 

- This Zig SDK also includes a simple Pub/Sub subsystem that takes care o  tracking open connections in a convenient manner, or you can use the value `sse.stream` to roll your own as well. 


# Using the DataStar SDK

## Reading Signals from the request

```zig
    pub fn readSignals(comptime T: type, req: anytype) !T
```

Will take a Type (struct) and a HTTP request, and returns a filled in struct of the requested type.

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


PatchElementsOptions is as follows :

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

See the DataStar documentation for the usage of these options when using patchElements.

Most of the time, you will want to simply pass an empty tuple `.{}` as the options parameter. 

## Patching Signals

TODO - code works fine, needs README writeup

## Executing Scripts

TODO - code works fine, needs README writeup

# Publish and Subscribe

TODO - code works fine, needs README writeup

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

The SSE object uses a std.Io.Writer stream to convert normal HTML Element, Signal and Script updates into the DataStar protocol, and then write them to the browser's connection.

By default this std.Io.Writer uses a zero-sized intermediate buffer, so every chunk written is passed straight through to the underlying socket writer after being converted to DataStar protocol.

With http.zig, this underlying socket writer is already buffered, and uses async IO to drain data to the user's browser in the background after your handler exits. This is all taken care of for you.

For most applications, these defaults offer an excellent balance between performance and memory consumption.

For advanced use cases, you can opt in for applying buffering to the SSE operations as well, by setting a default buffer size. 

This will reduce the number of writes between the SSE processor and the underlying http.zig writer to the browser, at the expense of one extra allocation per request.

To configure buffering, use this : 

```zig
    datastar.configure(.{ .buffer_size = 255 });
```

If your handlers are typically doing a large number of small writes inside a patchElements operation, then its definitely worth thinking about using a buffer for this.

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
This custom sized buffer allows the whole output to be written into memory before being passed on to the socket writer.

Consider using this if you have a rare case that makes sense.




# Contrib Policy

All contribs welcome.

Please raise a github issue first before adding a PR, and reference the issue in the PR title. 

This allows room for open discussion, as well as tracking of issues opened and closed.


# Advocacy Policy

Happy to advocate for DataStar and Zig and this API very strongly

DataStar has so many good things going for it, and Zig is a really good fit for a high performance / low resource DataStar server

But ... we dont say anything online until we have reproducable benchmarks that people can check for themselves and come
to their own conclusions

Always advocate using objective and easy to demonstrate evidence first


# LLM Policy

Avoid LLM like the plague please.

By all means use it for rubber ducking, but dont trust any code it produces, especially with Zig latest, let alone DataStar latest.

Its just not there yet (even if it looks convincing sometimes)


