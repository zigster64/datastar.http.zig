# Datastar lib for http.zig

This is an alternative to the official Zig Datastar SDK https://github.com/starfederation/datastar/tree/main/sdk/zig 

The main difference is that this API uses stream processing, instead of building up a buffer. As a result, you can 
connect this to any code that simply `print()` or `writeAll()` to the stream, and the lib will inject the necessary
protocol commands.

