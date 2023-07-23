const std = @import("std");

pub fn build(b: *std.Build) void {
    const memutils = b.addModule("memutils", .{
        .source_file = .{ .path = "src/memutils.zig" },
    });
    _ = memutils;

    {
        const target = b.standardTargetOptions(.{});
        const optimize = b.standardOptimizeOption(.{});
        // Creates a step for unit testing. This only builds the test executable
        // but does not run it.
        const tests = b.addTest(.{
            .root_source_file = .{ .path = "src/memutils.zig" },
            .target = target,
            .optimize = optimize,
        });

        const run_tests = b.addRunArtifact(tests);
        const test_step = b.step("test", "Run library tests");
        test_step.dependOn(&run_tests.step);
    }
}
