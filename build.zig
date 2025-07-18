const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dep_opts = .{
        .target = target,
        .optimize = optimize,
    };

    const datastar_httpz_module = b.addModule("datastar.httpz", .{
        .root_source_file = b.path("src/datastar.zig"),
        .target = target,
    });

    const httpz_module = b.dependency("httpz", dep_opts);
    datastar_httpz_module.addImport("httpz", httpz_module.module("httpz"));

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/datastar.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple },
    });
    const run_test = b.addRunArtifact(tests);
    run_test.has_side_effects = true;

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_test.step);

    const examples = [_]struct {
        file: []const u8,
        name: []const u8,
        libc: bool = false,
    }{
        .{ .file = "examples/01_basic.zig", .name = "example_1" },
        .{ .file = "examples/02_petshop.zig", .name = "example_2" },
        .{ .file = "examples/022_petshop.zig", .name = "example_22" },
        // .{ .file = "examples/03_racing.zig", .name = "example_3" },
    };

    {
        for (examples) |ex| {
            const exe = b.addExecutable(.{
                .name = ex.name,
                .root_module = b.createModule(.{
                    .root_source_file = b.path(ex.file),
                    .target = target,
                    .optimize = optimize,
                }),
            });
            exe.root_module.addImport("datastar.httpz", datastar_httpz_module);

            // add some 3rd party deps to get the app working
            exe.root_module.addImport("httpz", httpz_module.module("httpz"));

            const logz_module = b.dependency("logz", dep_opts);
            exe.root_module.addImport("logz", logz_module.module("logz"));

            const zts_module = b.dependency("zts", dep_opts);
            exe.root_module.addImport("zts", zts_module.module("zts"));

            b.installArtifact(exe);

            const run_cmd = b.addRunArtifact(exe);
            run_cmd.step.dependOn(b.getInstallStep());
            if (b.args) |args| {
                run_cmd.addArgs(args);
            }

            const run_step = b.step(ex.name, ex.file);
            run_step.dependOn(&run_cmd.step);
        }
    }
}
