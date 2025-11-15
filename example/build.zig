const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dartlib_dep = b.dependency("dartlib", .{
        .target = target,
        .optimize = optimize,
    });
    const dartlib = dartlib_dep.artifact("dartlib");

    const c_wf = b.addWriteFiles();
    const c_h = c_wf.add("c.h",
        \\#include <dartlib_api.h>
    );
    const c_translate = b.addTranslateC(.{
        .root_source_file = c_h,
        .target = target,
        .optimize = optimize,
    });
    c_translate.addIncludePath(dartlib.getEmittedIncludeTree());
    const c_mod = c_translate.createModule();

    const exe = b.addExecutable(.{
        .name = "dart-hello-world",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "c", .module = c_mod },
            },
        }),
    });
    exe.linkLibrary(dartlib);

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}
