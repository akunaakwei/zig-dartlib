const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(std.builtin.LinkMode, "linkage", "Linkage type for the library") orelse .static;

    const dart_dep = b.dependency("dart", .{
        .target = target,
        .optimize = optimize,
    });
    const libdart_jit = dart_dep.artifact("libdart_jit");
    const libdart_platform_jit = dart_dep.artifact("libdart_platform_jit");
    const libdart_platform_no_tsan_jit = dart_dep.artifact("libdart_platform_no_tsan_jit");
    const libdart_vm_jit = dart_dep.artifact("libdart_vm_jit");
    const libdart_compiler_jit = dart_dep.artifact("libdart_compiler_jit");
    const libdart_lib_jit = dart_dep.artifact("libdart_lib_jit");
    const crashpad = dart_dep.artifact("crashpad");
    const native_assets_api = dart_dep.artifact("native_assets_api");
    const observatory = dart_dep.artifact("observatory");
    const standalone_dart_io = dart_dep.artifact("standalone_dart_io");
    const libdart_builtin = dart_dep.artifact("libdart_builtin");

    const runtime = dart_dep.namedLazyPath("runtime");

    const boringssl = dart_dep.builder.dependency("boringssl", .{
        .target = target,
        .optimize = optimize,
    });
    const ssl = boringssl.artifact("ssl");

    const z_dep = dart_dep.builder.dependency("z", .{
        .target = target,
        .optimize = optimize,
    });
    const z = z_dep.artifact("z");

    const icu_dep = dart_dep.builder.dependency("icu", .{
        .target = target,
        .optimize = optimize,
    });
    const icuuc = icu_dep.artifact("icuuc");
    const icui18n = icu_dep.artifact("icui18n");

    const lib = b.addLibrary(.{
        .name = "dartlib",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = linkage,
    });

    lib.linkLibCpp();
    lib.addIncludePath(runtime);
    lib.addIncludePath(runtime.path(b, "include"));
    lib.addIncludePath(b.path("include"));
    lib.addCSourceFiles(.{
        .root = runtime.path(b, "bin"),
        .files = &.{
            "builtin.cc",
            "dartdev_isolate.cc",
            "dfe.cc",
            "gzip.cc",
            "loader.cc",

            "dart_embedder_api_impl.cc",
            "error_exit.cc",
            "icu.cc",
            "main_options.cc",
            "options.cc",
            "snapshot_utils.cc",
            "vmservice_impl.cc",
        },
        .flags = &.{"-DDART_IO_SECURE_SOCKET_DISABLED"},
    });
    lib.addCSourceFiles(.{
        .root = b.path("src"),
        .files = &.{"dartlib_api_impl.cc"},
        .flags = &.{""},
    });

    lib.linkLibrary(z);
    lib.linkLibrary(ssl);
    lib.linkLibrary(icuuc);
    lib.linkLibrary(icui18n);
    lib.linkLibrary(libdart_jit);
    lib.linkLibrary(libdart_platform_jit);
    lib.linkLibrary(libdart_platform_no_tsan_jit);
    lib.linkLibrary(standalone_dart_io);
    lib.linkLibrary(libdart_builtin);
    lib.linkLibrary(libdart_vm_jit);
    lib.linkLibrary(libdart_compiler_jit);
    lib.linkLibrary(libdart_lib_jit);
    lib.linkLibrary(crashpad);
    lib.linkLibrary(native_assets_api);
    lib.linkLibrary(observatory);

    lib.addAssemblyFile(dart_dep.namedLazyPath("vm_snapshot_data_linkable"));
    lib.addAssemblyFile(dart_dep.namedLazyPath("vm_snapshot_instructions_linkable"));
    lib.addAssemblyFile(dart_dep.namedLazyPath("isolate_snapshot_data_linkable"));
    lib.addAssemblyFile(dart_dep.namedLazyPath("isolate_snapshot_instructions_linkable"));
    lib.addAssemblyFile(dart_dep.namedLazyPath("platform_strong_dill_linkable"));
    lib.addAssemblyFile(dart_dep.namedLazyPath("kernel_service_dill_linkable"));

    switch (target.result.os.tag) {
        .windows => {
            lib.linkSystemLibrary("iphlpapi");
            lib.linkSystemLibrary("ws2_32");
            lib.linkSystemLibrary("Rpcrt4");
            lib.linkSystemLibrary("shlwapi");
            lib.linkSystemLibrary("winmm");
            lib.linkSystemLibrary("psapi");
            lib.linkSystemLibrary("advapi32");
            lib.linkSystemLibrary("shell32");
            lib.linkSystemLibrary("ntdll");
            lib.linkSystemLibrary("dbghelp");
            lib.linkSystemLibrary("ole32");
            lib.linkSystemLibrary("oleaut32");
            lib.linkSystemLibrary("crypt32");
            lib.linkSystemLibrary("bcrypt");
            lib.linkSystemLibrary("api-ms-win-core-path-l1-1-0");

            const maybe_comsupp_dep = dart_dep.builder.lazyDependency("comsupp", .{
                .target = target,
                .optimize = optimize,
            });
            if (maybe_comsupp_dep) |comsupp_dep| {
                lib.linkLibrary(comsupp_dep.artifact("comsupp"));
            }
        },
        .macos, .ios => {
            lib.linkFramework("CoreFoundation");
            lib.linkFramework("CoreServices");
            lib.linkFramework("Foundation");
            lib.linkFramework("Security");
        },
        else => {},
    }
    lib.installHeader(runtime.path(b, "include/dart_api.h"), "dart_api.h");
    lib.installHeader(b.path("include/dartlib_api.h"), "dartlib_api.h");
    b.installArtifact(lib);

    const translate = b.addTranslateC(.{
        .root_source_file = b.path("include/dartlib_api.h"),
        .target = target,
        .optimize = optimize,
    });
    translate.addIncludePath(runtime.path(b, "include"));
    const mod = translate.addModule("dartlib");
    mod.linkLibrary(lib);
}
