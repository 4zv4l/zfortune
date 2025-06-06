const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zfortune",
        .optimize = optimize,
        .target = target,
        .root_source_file = b.path("src/main.zig"),
    });
    b.installArtifact(exe);
}
