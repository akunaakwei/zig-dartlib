const std = @import("std");
const dart = @import("dartlib");

var allocator: std.mem.Allocator = undefined;
var stderr: std.io.Writer = undefined;
var stdout: std.io.Writer = undefined;

const IsolateGroupData = struct {
    url: [*c]const u8,
    packages_file: [*c]const u8,
    app_snapshot: ?*anyopaque,
    isolate_run_app_snapshot: bool,
    callback_data: ?*anyopaque,
    kernel_buffer: ?[]u8,
};

const IsolateData = struct {
    isolate_group_data: *IsolateGroupData,
    packages_file: [*c]const u8,
};

const MessageHandler = struct {
    pub var pending_count: usize = 0;
    pub fn notify(isolate: dart.Dart_Isolate) callconv(.c) void {
        _ = isolate;
        pending_count += 1;
    }
};

pub fn main() !void {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    defer {
        const gpa_status = gpa.deinit();
        std.debug.assert(gpa_status == .ok);
    }
    allocator = gpa.allocator();
    var stderr_buffer: [1024]u8 = undefined;
    const stderr_filewriter = std.fs.File.stderr().writer(&stderr_buffer);
    stderr = stderr_filewriter.interface;
    // defer stderr.flush() catch {};

    var stdout_buffer: [1024]u8 = undefined;
    const stdout_filewriter = std.fs.File.stdout().writer(&stdout_buffer);
    stdout = stdout_filewriter.interface;
    defer stdout.flush() catch {};

    _ = dart.Dart_SetVMFlags(0, null);
    {
        var err: [*c]u8 = undefined;
        if (!dart.Dart_EmbedderInitOnce(&err)) {
            try stderr.print("Dart_EmbedderInitOnce: {s}\n", .{err});
            return error.EmbedderInitOnceFailed;
        }
    }
    dart.Dart_DFEInit();
    dart.Dart_DFESetUseDartFrontend(true);
    dart.Dart_DFESetIncrementalCompiler(false);
    {
        var params: dart.Dart_InitializeParams = .{
            .version = dart.DART_INITIALIZE_PARAMS_CURRENT_VERSION,
            .vm_snapshot_data = dart.kDartVmSnapshotData,
            .vm_snapshot_instructions = dart.kDartVmSnapshotInstructions,
            .create_group = isolateGroupCreateCallback,
            .initialize_isolate = isolateInitializeCallback,
            .shutdown_isolate = isolateShutdownCallback,
            .cleanup_isolate = isolateCleanupCallback,
            .cleanup_group = isolateGroupCleanupCallback,
            .thread_start = null,
            .thread_exit = null,
            .file_open = null,
            .file_read = null,
            .file_write = null,
            .file_close = null,
            .entropy_source = dart.Dart_EntropySourceDefault,
            .get_service_assets = undefined,
            .start_kernel_isolate = dart.Dart_DFEGetUseDartFrontend() and dart.Dart_DFECanUseDartFrontend(),
            .code_observer = null,
        };
        const maybe_err = dart.Dart_Initialize(&params);
        if (maybe_err) |err| {
            try stderr.print("Dart_Initialize: {s}\n", .{err});
            return error.InitializeFailed;
        }
    }

    var flags: dart.Dart_IsolateFlags = .{};
    dart.Dart_IsolateFlagsInitialize(&flags);
    if (std.os.argv.len <= 1) {
        try stderr.print("not enough arguments\n", .{});
        return error.InvalidArgument;
    }
    var isolate_err: [*c]u8 = undefined;
    const isolate = createIsolate(true, std.os.argv[1], "main", null, null, &flags, null, &isolate_err);
    if (isolate == null) {
        try stderr.print("createIsolate: {s}\n", .{isolate_err});
        return error.CreateIsolateFailed;
    }
    dart.Dart_EnterIsolate(isolate);
    dart.Dart_SetMessageNotifyCallback(MessageHandler.notify);
    dart.Dart_EnterScope();
    const lib = dart.Dart_RootLibrary();
    _ = dart.Dart_SetNativeResolver(lib, resolveNativeFunction, null);
    const mainClosure = dart.Dart_GetField(lib, dart.Dart_NewStringFromCString("main"));
    if (!dart.Dart_IsClosure(mainClosure)) {
        try stderr.print("main closure not found\n", .{});
        return error.MainClosureNotFound;
    }
    var args = [_]dart.Dart_Handle{
        mainClosure, dart.Dart_Null(),
    };
    const isolate_lib = dart.Dart_LookupLibrary(dart.Dart_NewStringFromCString("dart:isolate"));

    {
        const result = dart.Dart_Invoke(isolate_lib, dart.Dart_NewStringFromCString("_startMainIsolate"), args.len, &args);
        if (dart.Dart_IsError(result)) {
            try stderr.print("Dart_Invoke: {s}\n", .{dart.Dart_GetError(result)});
            return error.DartInvokeFailed;
        }
    }
    {
        const result = dart.Dart_RunLoop();
        if (dart.Dart_IsError(result)) {
            try stderr.print("Dart_RunLoop: {s}\n", .{dart.Dart_GetError(result)});
            return error.DartRunloopFailed;
        }
    }
    {
        const result = drainMicrotaskQueue(isolate_lib);
        if (dart.Dart_IsError(result)) {
            try stderr.print("drainMicrotaskQueue: {s}\n", .{dart.Dart_GetError(result)});
            return error.DrainMicrotaskQueueFailed;
        }
    }
    {
        dart.Dart_EnterScope();
        while (MessageHandler.pending_count > 0) : (MessageHandler.pending_count -= 1) {
            const result = dart.Dart_HandleMessage();
            if (dart.Dart_IsError(result)) {
                try stderr.print("Dart_HandleMessage: {s}\n", .{dart.Dart_GetError(result)});
                return error.DartHandleMessageFailed;
            }
        }
        dart.Dart_ExitScope();
    }
    dart.Dart_ExitScope();
    dart.Dart_ShutdownIsolate();
    {
        const maybe_err = dart.Dart_Cleanup();
        if (maybe_err) |err| {
            try stderr.print("Dart_Cleanup: {s}\n", .{err});
            return error.CleanupFailed;
        }
        dart.Dart_EmbedderCleanup();
    }
    // try stderr.flush();
}

fn drainMicrotaskQueue(isolate_lib: dart.Dart_Handle) dart.Dart_Handle {
    dart.Dart_EnterScope();
    const invoke_name = dart.Dart_NewStringFromCString("_runPendingImmediateCallback");
    var result = dart.Dart_Invoke(isolate_lib, invoke_name, 0, null);
    if (dart.Dart_IsError(result)) {
        stderr.print("Error drainMicrotaskQueue 1: {s}\n", .{dart.Dart_GetError(result)}) catch {};
        return result;
    }
    result = dart.Dart_HandleMessage();
    if (dart.Dart_IsError(result)) {
        stderr.print("Error drainMicrotaskQueue 2: {s}\n", .{dart.Dart_GetError(result)}) catch {};
        return result;
    }
    dart.Dart_ExitScope();

    return result;
}

fn isolateGroupCreateCallback(script_uri: [*c]const u8, main_entry: [*c]const u8, package_root: [*c]const u8, package_config: [*c]const u8, flags: [*c]dart.Dart_IsolateFlags, parent_isolate_data: ?*anyopaque, err: [*c][*c]u8) callconv(.c) dart.Dart_Isolate {
    if (std.mem.eql(u8, std.mem.span(script_uri), dart.DART_KERNEL_ISOLATE_NAME)) {
        return createKernelIsolate(script_uri, main_entry, package_root, package_config, flags, parent_isolate_data, err);
    } else if (std.mem.eql(u8, std.mem.span(script_uri), dart.DART_VM_SERVICE_ISOLATE_NAME)) {
        return createVmServiceIsolate(script_uri, main_entry, package_root, package_config, flags, parent_isolate_data, err);
    } else {
        return createIsolate(false, script_uri, main_entry, package_root, package_config, flags, parent_isolate_data, err);
    }
}

fn createKernelIsolate(script_uri: [*c]const u8, main_entry: [*c]const u8, package_root: [*c]const u8, package_config: [*c]const u8, flags: [*c]dart.Dart_IsolateFlags, parent_isolate_data: ?*anyopaque, err: [*c][*c]u8) callconv(.c) dart.Dart_Isolate {
    _ = package_root;
    _ = parent_isolate_data;

    const snapshot_uri = dart.Dart_DFEGetFrontendFilename();
    var kernel_service_buffer: [*c]const u8 = undefined;
    var kernel_service_buffer_len: isize = 0;
    dart.Dart_DFELoadKernelService(&kernel_service_buffer, &kernel_service_buffer_len);
    const isolate_group_data = allocator.create(IsolateGroupData) catch return null;
    isolate_group_data.* = .{
        .url = snapshot_uri orelse script_uri,
        .packages_file = package_config,
        .app_snapshot = null,
        .isolate_run_app_snapshot = false,
        .callback_data = null,
        .kernel_buffer = null,
    };
    const isolate_data = allocator.create(IsolateData) catch return null;
    isolate_data.* = .{
        .isolate_group_data = isolate_group_data,
        .packages_file = package_config,
    };
    const data: dart.IsolateCreationData = .{
        .script_uri = script_uri,
        .main = main_entry,
        .flags = @ptrCast(flags),
        .isolate_group_data = @ptrCast(isolate_group_data),
        .isolate_data = @ptrCast(isolate_data),
    };
    const isolate = dart.Dart_EmbedderCreateKernelServiceIsolate(&data, kernel_service_buffer, kernel_service_buffer_len, err);
    dart.Dart_EnterIsolate(@ptrCast(isolate));
    defer dart.Dart_ExitIsolate();
    dart.Dart_EnterScope();
    defer dart.Dart_ExitScope();

    _ = dart.Dart_SetLibraryTagHandler(dart.Dart_LibraryTagHandlerDefault);
    _ = setupCoreLibraries(isolate, isolate_data, true, null);

    return isolate;
}

fn setupCoreLibraries(isolate: dart.Dart_Isolate, isolate_data: *IsolateData, is_isolate_group_start: bool, resolved_packages_config: [*c][*c]const u8) dart.Dart_Handle {
    _ = isolate;
    var result = dart.Dart_PrepareForScriptLoading(false, true);
    if (dart.Dart_IsError(result)) {
        return result;
    }
    result = dart.Dart_SetupPackageConfig(isolate_data.packages_file);
    if (dart.Dart_IsError(result)) {
        return result;
    }
    if (!dart.Dart_IsNull(result) and resolved_packages_config.* != null) {
        result = dart.Dart_StringToCString(result, resolved_packages_config);
        if (dart.Dart_IsError(result)) {
            return result;
        }
        if (is_isolate_group_start) {
            isolate_data.isolate_group_data.packages_file = resolved_packages_config.*;
            isolate_data.packages_file = resolved_packages_config.*;
        }
    }

    result = dart.Dart_SetEnvironmentCallback(dart.Dart_EnvironmentCallbackDefault);
    if (dart.Dart_IsError(result)) {
        return result;
    }
    dart.Dart_BuiltinSetNativeResolver(dart.kBuiltinLibrary);
    dart.Dart_BuiltinSetNativeResolver(dart.kIOLibrary);
    dart.Dart_BuiltinSetNativeResolver(dart.kCLILibrary);
    dart.Dart_VmServiceSetNativeResolver();
    result = dart.Dart_SetupIOLibrary(null, isolate_data.isolate_group_data.url, true);
    if (dart.Dart_IsError(result)) {
        return result;
    }
    return result;
}

fn createVmServiceIsolate(script_uri: [*c]const u8, main_entry: [*c]const u8, package_root: [*c]const u8, package_config: [*c]const u8, flags: [*c]dart.Dart_IsolateFlags, parent_isolate_data: ?*anyopaque, err: [*c][*c]u8) callconv(.c) dart.Dart_Isolate {
    _ = package_root;
    _ = parent_isolate_data;
    const isolate_group_data = allocator.create(IsolateGroupData) catch return null;
    isolate_group_data.* = .{
        .url = script_uri,
        .packages_file = package_config,
        .app_snapshot = null,
        .isolate_run_app_snapshot = false,
        .callback_data = null,
        .kernel_buffer = null,
    };
    const isolate_data = allocator.create(IsolateData) catch return null;
    isolate_data.* = .{
        .isolate_group_data = isolate_group_data,
        .packages_file = package_config,
    };

    flags.*.load_vmservice_library = true;
    const data: dart.IsolateCreationData = .{
        .script_uri = script_uri,
        .main = main_entry,
        .flags = @ptrCast(flags),
        .isolate_group_data = @ptrCast(isolate_group_data),
        .isolate_data = @ptrCast(isolate_data),
    };
    const config: dart.VmServiceConfiguration = .{
        .ip = "127.0.0.1",
        .port = 2001,
        .write_service_info_filename = null,
        .dev_mode = false,
        .deterministic = true,
        .disable_auth_codes = true,
    };
    const isolate = dart.Dart_EmbedderCreateVmServiceIsolate(&data, &config, dart.kDartCoreIsolateSnapshotData, dart.kDartCoreIsolateSnapshotInstructions, err);
    dart.Dart_EnterIsolate(isolate);
    defer dart.Dart_ExitIsolate();
    dart.Dart_EnterScope();
    defer dart.Dart_ExitScope();

    _ = dart.Dart_SetEnvironmentCallback(dart.Dart_EnvironmentCallbackDefault);
    return isolate;
}

fn createIsolate(is_main: bool, script_uri: [*c]const u8, main_entry: [*c]const u8, package_root: [*c]const u8, package_config: [*c]const u8, flags: [*c]dart.Dart_IsolateFlags, parent_isolate_data: ?*anyopaque, err: [*c][*c]u8) callconv(.c) dart.Dart_Isolate {
    _ = is_main;
    _ = package_root;
    var kernel_buffer: [*c]u8 = undefined;
    var kernel_buffer_len: isize = 0;
    dart.Dart_DFEReadScript(script_uri, null, &kernel_buffer, &kernel_buffer_len, true);
    flags.*.null_safety = true;

    const isolate_group_data = allocator.create(IsolateGroupData) catch return null;
    isolate_group_data.* = .{
        .url = script_uri,
        .packages_file = package_config,
        .app_snapshot = null,
        .isolate_run_app_snapshot = false,
        .callback_data = parent_isolate_data,
        .kernel_buffer = null,
    };
    if (kernel_buffer != null) {
        isolate_group_data.*.kernel_buffer = kernel_buffer[0 .. @as(usize, @intCast(kernel_buffer_len)) - 1];
    }

    var platform_kernel_buffer: [*c]const u8 = undefined;
    var platform_kernel_buffer_len: isize = 0;
    dart.Dart_DFELoadPlatform(&platform_kernel_buffer, &platform_kernel_buffer_len);
    if (platform_kernel_buffer == null) {
        platform_kernel_buffer = kernel_buffer;
        platform_kernel_buffer_len = kernel_buffer_len;
    }

    const isolate_data = allocator.create(IsolateData) catch return null;
    isolate_data.* = .{
        .isolate_group_data = isolate_group_data,
        .packages_file = package_config,
    };
    const isolate = dart.Dart_CreateIsolateGroupFromKernel(script_uri, main_entry, platform_kernel_buffer, platform_kernel_buffer_len, @ptrCast(flags), isolate_group_data, isolate_data, err);
    if (isolate == null) {
        stderr.print("{s}\n", .{err.*}) catch {};
        return null;
    }
    dart.Dart_EnterScope();

    var result = dart.Dart_SetLibraryTagHandler(dart.Dart_LibraryTagHandlerDefault);
    if (dart.Dart_IsError(result)) {
        dart.Dart_ExitScope();
        dart.Dart_ShutdownIsolate();
        return null;
    }

    var resolved_packages_config: [*c]const u8 = null;
    result = setupCoreLibraries(isolate, isolate_data, true, &resolved_packages_config);
    if (dart.Dart_IsError(result)) {
        dart.Dart_ExitScope();
        dart.Dart_ShutdownIsolate();
        return null;
    }

    if (kernel_buffer == null and !dart.Dart_IsKernelIsolate(isolate)) {
        var application_kernel_buffer: [*c]u8 = undefined;
        var application_kernel_buffer_len: isize = 0;
        var exit_code: c_int = 0;
        dart.Dart_DFECompileAndReadScript(script_uri, &application_kernel_buffer, &application_kernel_buffer_len, err, &exit_code, resolved_packages_config, true, false);
        if (application_kernel_buffer == null or application_kernel_buffer_len == 0) {
            dart.Dart_ExitScope();
            dart.Dart_ShutdownIsolate();
            stderr.print("{s}", .{err.*}) catch {};
            return null;
        }
        stderr.print("application_kernel_buffer_len: {d}\n", .{application_kernel_buffer_len}) catch {};
        isolate_group_data.*.kernel_buffer = application_kernel_buffer[0 .. @as(usize, @intCast(application_kernel_buffer_len)) - 1];
        kernel_buffer = application_kernel_buffer;
        kernel_buffer_len = application_kernel_buffer_len;
    }

    if (kernel_buffer != null) {
        stderr.print("Dart_LoadScriptFromKernel\n", .{}) catch {};
        result = dart.Dart_LoadScriptFromKernel(kernel_buffer, kernel_buffer_len);
        if (dart.Dart_IsError(result)) {
            dart.Dart_ExitScope();
            dart.Dart_ShutdownIsolate();
            return null;
        }
    }
    dart.Dart_ExitScope();
    dart.Dart_ExitIsolate();
    stderr.print("Dart_IsolateMakeRunnable\n", .{}) catch {};
    err.* = dart.Dart_IsolateMakeRunnable(isolate);
    if (err.* != null) {
        stderr.print("Dart_IsolateMakeRunnable failed: {s}\n", .{err.*}) catch {};
        dart.Dart_EnterIsolate(isolate);
        dart.Dart_ShutdownIsolate();
        return null;
    }
    return isolate;
}

fn isolateInitializeCallback(child_isolate_data: [*c]?*anyopaque, err: [*c][*c]u8) callconv(.c) bool {
    _ = child_isolate_data;
    _ = err;
    return true;
}

fn isolateShutdownCallback(isolate_group_data: ?*anyopaque, isolate_data: ?*anyopaque) callconv(.c) void {
    dart.Dart_EnterScope();
    _ = isolate_group_data;
    _ = isolate_data;

    const sticky_error = dart.Dart_GetStickyError();
    if (!dart.Dart_IsNull(sticky_error) and !dart.Dart_IsFatalError(sticky_error)) {
        stderr.print("Error shutting down isolate: {s}\n", .{dart.Dart_GetError(sticky_error)}) catch {};
    }
    dart.Dart_ExitScope();
}

fn isolateCleanupCallback(isolate_group_data: ?*anyopaque, isolate_data: ?*anyopaque) callconv(.c) void {
    allocator.destroy(@as(*IsolateData, @alignCast(@ptrCast(isolate_data.?))));
    _ = isolate_group_data;
}

fn isolateGroupCleanupCallback(isolate_group_data: ?*anyopaque) callconv(.c) void {
    allocator.destroy(@as(*IsolateGroupData, @alignCast(@ptrCast(isolate_group_data.?))));
}

fn print(args: dart.Dart_NativeArguments) callconv(.c) void {
    const str = dart.Dart_GetNativeArgument(args, 0);
    if (dart.Dart_IsString(str)) {
        var cstr: [*c]const u8 = undefined;
        const err = dart.Dart_StringToCString(str, &cstr);
        if (dart.Dart_IsError(err)) {
            return;
        }
        stdout.print("{s}\n", .{cstr}) catch {};
    }
}

fn resolveNativeFunction(name: dart.Dart_Handle, argc: c_int, auto_setup_scope: [*c]bool) callconv(.c) dart.Dart_NativeFunction {
    _ = argc;
    _ = auto_setup_scope;
    if (!dart.Dart_IsString(name)) {
        return null;
    }
    var cname: [*c]const u8 = undefined;
    const err = dart.Dart_StringToCString(name, &cname);
    if (dart.Dart_IsError(err)) {
        return null;
    }
    if (std.mem.eql(u8, std.mem.span(cname), "print")) {
        return print;
    }

    return null;
}
