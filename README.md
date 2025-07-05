# Datastar lib for http.zig

This is an alternative to the official Zig Datastar SDK https://github.com/starfederation/datastar/tree/main/sdk/zig 

The main difference is that this API uses stream processing, instead of building up a buffer. As a result, you can 
connect this to any code that simply `print()` or `writeAll()` to the stream, and the lib will inject the necessary
protocol commands.

## Signal Scoping Fix

This version includes a fix for signal scoping issues where signals were globally shared across all elements on a page instead of being scoped to specific DOM sections. 

### Before the fix:
- `patchSignals()` would affect ALL elements with `data-bind-*` attributes on the entire page
- Multiple cards/components would interfere with each other's signals
- `onlyIfMissing` behavior was unpredictable due to global signal state

### After the fix:
- Use `patchSignalsOpt()` with a `selector` to scope signals to specific DOM elements
- Each page/component can have its own isolated signal state
- Backward compatibility maintained - legacy `patchSignals()` still works globally

### Example usage:
```zig
// Scoped to a specific page/component
var msg = datastar.patchSignalsOpt(stream, .{
    .selector = "#my-component",
});

// Legacy usage (global scope) still works
var msg = datastar.patchSignals(stream);
```

