#include "dartlib_api.h"
#include <include/dart_embedder_api.h>
#include <bin/dfe.h>
#include <bin/dartutils.h>
#include <bin/loader.h>
#include <bin/builtin.h>
#include <bin/vmservice_impl.h>


bool Dart_EmbedderInitOnce(char** error) {
    return dart::embedder::InitOnce(error);
}

void Dart_EmbedderCleanup() {
    dart::embedder::Cleanup();
}

Dart_Isolate Dart_EmbedderCreateVmServiceIsolate(const IsolateCreationData* data, const VmServiceConfiguration* config, const uint8_t* isolate_data, const uint8_t* isolate_instr, char** error) {
    return dart::embedder::CreateVmServiceIsolate(*reinterpret_cast<const dart::embedder::IsolateCreationData*>(data), *reinterpret_cast<const dart::embedder::VmServiceConfiguration*>(config), isolate_data, isolate_instr, error);
}

Dart_Isolate Dart_EmbedderCreateKernelServiceIsolate(const IsolateCreationData* data, const uint8_t* buffer, intptr_t buffer_size, char** error) {
    return dart::embedder::CreateKernelServiceIsolate(*reinterpret_cast<const dart::embedder::IsolateCreationData*>(data), buffer, buffer_size, error);
}

void Dart_DFEInit() {
    dart::bin::dfe.Init();
}

void Dart_DFESetUseDartFrontend(bool value) {
    dart::bin::dfe.set_use_dfe(value);
}

bool Dart_DFEGetUseDartFrontend() {
    return dart::bin::dfe.UseDartFrontend();
}

bool Dart_DFECanUseDartFrontend() {
    return dart::bin::dfe.CanUseDartFrontend();
}

const char* Dart_DFEGetFrontendFilename() {
    return dart::bin::dfe.frontend_filename();
}

void Dart_DFESetIncrementalCompiler(bool value) {
    dart::bin::dfe.set_use_incremental_compiler(value);
}

bool Dart_DFEGetIncrementalCompiler() {
    return dart::bin::dfe.use_incremental_compiler();
}

void Dart_DFESetVerbosity(Dart_KernelCompilationVerbosityLevel value) {
    dart::bin::dfe.set_verbosity(value);
}

Dart_KernelCompilationVerbosityLevel Dart_DFEGetVerbosity() {
    return dart::bin::dfe.verbosity();
}

void Dart_DFEReadScript(const char* script_uri, const struct AppSnapshot* app_snapshot,uint8_t** kernel_buffer, intptr_t* kernel_buffer_size, bool decode_uri) {
    dart::bin::dfe.ReadScript(script_uri, reinterpret_cast<const dart::bin::AppSnapshot*>(app_snapshot), kernel_buffer, kernel_buffer_size);
}

void Dart_DFECompileAndReadScript(const char* script_uri, uint8_t** kernel_buffer, intptr_t* kernel_buffer_size, char** error, int* exit_code, const char* package_config, bool for_snapshot, bool embed_sources) {
    dart::bin::dfe.CompileAndReadScript(script_uri, kernel_buffer, kernel_buffer_size, error, exit_code, package_config, for_snapshot, embed_sources);
}

void Dart_DFELoadPlatform(const uint8_t** kernel_buffer,intptr_t* kernel_buffer_size) {
    dart::bin::dfe.LoadPlatform(kernel_buffer, kernel_buffer_size);
}

void Dart_DFELoadKernelService(const uint8_t** kernel_service_buffer, intptr_t* kernel_service_buffer_size) {
    dart::bin::dfe.LoadKernelService(kernel_service_buffer, kernel_service_buffer_size);
}

Dart_Handle Dart_NewError(const char* format, ...) {
    va_list args;
    va_start(args, format);
    Dart_Handle result = dart::bin::DartUtils::NewError(format, args);
    va_end(args);
    return result;
}

Dart_Handle Dart_NewInternalError(const char* message) {
    return dart::bin::DartUtils::NewInternalError(message);
}

Dart_Handle Dart_EnvironmentCallbackDefault(Dart_Handle name) {
    return dart::bin::DartUtils::EnvironmentCallback(name);
}

bool Dart_EntropySourceDefault(uint8_t* buffer, intptr_t length) {
    return dart::bin::DartUtils::EntropySource(buffer, length);
}

void Dart_BuiltinSetNativeResolver(BuiltinLibraryId id) {
    dart::bin::Builtin::SetNativeResolver(static_cast<dart::bin::Builtin::BuiltinLibraryId>(id));
}

void Dart_VmServiceSetNativeResolver(void) {
#if !defined(PRODUCT)
    dart::bin::VmService::SetNativeResolver();
#endif
}

Dart_Handle Dart_PrepareForScriptLoading(bool is_service_isolate, bool trace_loading) {
    return dart::bin::DartUtils::PrepareForScriptLoading(is_service_isolate, trace_loading);
}

Dart_Handle Dart_SetupIOLibrary(const char* namespc_path, const char* script_uri, bool disable_exit) {
    return dart::bin::DartUtils::SetupIOLibrary(namespc_path, script_uri, disable_exit);
}

Dart_Handle Dart_SetupPackageConfig(const char* packages_file) {
    return dart::bin::DartUtils::SetupPackageConfig(packages_file);
}

Dart_Handle Dart_LibraryTagHandlerDefault(Dart_LibraryTag tag, Dart_Handle library, Dart_Handle url) {
    return dart::bin::Loader::LibraryTagHandler(tag, library, url);
}