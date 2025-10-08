# Datastar lib for http.zig

This is an alternative to the official Zig Datastar SDK https://github.com/starfederation/datastar/tree/main/sdk/zig 

The main difference is that this API uses stream processing, instead of building up a buffer. As a result, you can 
connect this to any code that simply `print()` or `writeAll()` to the stream, and the lib will inject the necessary
protocol commands.

# Example Apps

When you `zig build` it will compile several apps into `./zig-out/bin/` to demonstrate different aspects 
of the api

Using http.zig :

- example_1  shows using the DataStar API using basic SDK handlers
- example_2  shows an example multi-user auction site for cats with realtime updates
- example_3  shows an example multi-user pigeon racing betting site with realtime updates
- example_4  shows an example multi-game, multi-player TicTacToe site, using the backstage actor framework
- example_5  shows an example multi-player Gardening Simulator

Using zig stdlib http server :

- example_10 as per example_1, but using zig stdlib instead of http.zig




# Functions

## The SSE Object

Calling NewSSE, passing a request and response, will return an object of type SSE.


```zig
    pub fn NewSSE(req, res) !SSE 
```

This will configure the connnection for SSE transfers, and provides an object with DataStar methods for
patching elements, patching signals, executing scripts, etc.

When you are finised with the SSE object, you should either :

- Call `sse.close()` if you are done and want to close the connection as part of your handler.

- Otherwise, the SSE connection is left open after you exit your handler function. In this case, you can 
  access the `sse.stream: std.net.Stream` value and store it for subsequent writes to that open connection. 

- This Zig SDK also includes a simple Pub/Sub subsystem that takes care of tracking open connections in a convenient manner, but you can use the value `sse.stream` to roll your own as well. 

## Patching Elements

The SDK Provides 3 functions to patch elements over SSE.

These are all member functions of the SSE type that NewSSE(req, res) returns.


```zig
    pub fn patchElements(self: *SSE, elements: []const u8, opt: PatchElementsOptions) !void

    pub fn patchElementsFmt(self: *SSE, comptime elements: []const u8, args: anytype, opt: PatchElementsOptions) !void

    pub fn patchElementsWriter(self: *SSE, opt: PatchElementsOptions) *std.Io.Writer 
```

Use `sse.patchElements` to directly patch the DOM with the given "elements" string.

Use `sse.patchElementsFmt` to directly patch the DOM with a formatted print (where elements,args is the format string, args).

Use `sse.patchElementsWriter` to return a writer object that you can programmatically write to using complex logic.

If using the Writer, then be sure to call `sse.flush()` when you are finished writing to it.

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

## Executing Scripts


# DEV STEALTH MODE

This repo is currently in semi-stealth DEV mode

That means sweeping breaking changes, as we are targetting DataStar 1.0 which is only in RC release at the moment

And ... probably a reworked http.zig as writergate changes may be implemented soon

And ... Zig 15 which doesnt come out till August 2025, and has many breaking changes

So ... lots of breaking changes, and yolo merges straight onto the master branch


After things settle, we will do the whole documentation - CI - tests - FeatureBranches engineering goodness

Until then - wild west development

# Contrib Policy

All contribs welcome.

Please raise an issue first before adding a PR, so there is room for discussion
before any code hits

Until we get out of stealth mode and get into a proper engineering cycle, PR reviews will be light and easy

Once we hit release ... expect PR reviews to be harsh and well reasoned

If you want to modify what someone else has already worked on - by all means put in a PR to change it, but also ping them offline
or put them on the review list to comment on the change

Realistically, once code is 'merged' then we ALL own it, but try and keep others in the the loop anyway

This is partially for common courtesy, but also for the Chesterton's Fence principle `https://fs.blog/chestertons-fence/`

Longer term - I would like this to hit 1.0 at the same time as Zig 15 and writergate changes settle down, and
then ONLY add new features to keep it in track with D* updates (or Zig / http.zig updates)

# Maintenance Policy

This is intended to be a professionally supported API for the DataStar community after we hit 1.0.  Im committed to that at least, and 
I believe we have enough good ppl on the team already to provide good support coverage long term

Its not a particulary difficult bit of code to maintain

# Advocacy Policy

Happy to advocate for DataStar and Zig and this API very strongly

But ... we dont say anything until we have reproducable benchmarks that people can apply themselves and come
to their own conclusions

If we do it right, we shouldnt need to sell anything - it will sell itself

# LLM Policy

Avoid LLM like the plague please. By all means use it for rubber ducking, but dont trust any code it produces

Its just not there yet (even if it looks convincing)


