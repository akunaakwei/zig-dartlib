#ifndef DARTLIB_H_
#define DARTLIB_H_

#include <stdbool.h>
#include <stdint.h>
#include "dart_api.h"

#ifdef __cplusplus
extern "C" {
#endif

extern const uint8_t kDartVmSnapshotData[];
extern const uint8_t kDartVmSnapshotInstructions[];
extern const uint8_t kDartCoreIsolateSnapshotData[];
extern const uint8_t kDartCoreIsolateSnapshotInstructions[];

typedef struct {
  const char* script_uri;
  const char* main;
  Dart_IsolateFlags* flags;
  void* isolate_group_data;
  void* isolate_data;
} IsolateCreationData;

typedef struct {
  enum { kBindHttpServerToAFreePort = 0, kDoNotAutoStartHttpServer = -1 };
  const char* ip;
  int port;
  const char* write_service_info_filename;
  bool dev_mode;
  bool deterministic;
  bool disable_auth_codes;
} VmServiceConfiguration;

enum BuiltinLibraryId {
  kInvalidLibrary = -1,
  kBuiltinLibrary = 0,
  kIOLibrary,
  kHttpLibrary,
  kCLILibrary,
};

DART_EXPORT
bool Dart_EmbedderInitOnce(char** error);

DART_EXPORT
void Dart_EmbedderCleanup(void);

DART_EXPORT
Dart_Isolate Dart_EmbedderCreateVmServiceIsolate(const IsolateCreationData* data, const VmServiceConfiguration* config, const uint8_t* isolate_data, const uint8_t* isolate_instr, char** error);

DART_EXPORT
Dart_Isolate Dart_EmbedderCreateKernelServiceIsolate(const IsolateCreationData* data, const uint8_t* buffer, intptr_t buffer_size, char** error);

DART_EXPORT
void Dart_DFEInit(void);

DART_EXPORT
void Dart_DFESetUseDartFrontend(bool value);

DART_EXPORT
bool Dart_DFEGetUseDartFrontend(void);

DART_EXPORT
bool Dart_DFECanUseDartFrontend(void);

DART_EXPORT
const char* Dart_DFEGetFrontendFilename(void);

DART_EXPORT
void Dart_DFESetIncrementalCompiler(bool value);

DART_EXPORT
bool Dart_DFEGetIncrementalCompiler(void);

DART_EXPORT
void Dart_DFESetVerbosity(Dart_KernelCompilationVerbosityLevel value);

DART_EXPORT
Dart_KernelCompilationVerbosityLevel Dart_DFEGetVerbosity(void);

DART_EXPORT
void Dart_DFEReadScript(const char* script_uri, const struct AppSnapshot* app_snapshot,uint8_t** kernel_buffer, intptr_t* kernel_buffer_size, bool decode_uri);

DART_EXPORT
void Dart_DFECompileAndReadScript(const char* script_uri, uint8_t** kernel_buffer, intptr_t* kernel_buffer_size, char** error, int* exit_code, const char* package_config, bool for_snapshot, bool embed_sources);

DART_EXPORT
void Dart_DFELoadPlatform(const uint8_t** kernel_buffer,intptr_t* kernel_buffer_size);

DART_EXPORT
void Dart_DFELoadKernelService(const uint8_t** kernel_service_buffer, intptr_t* kernel_service_buffer_size);

DART_EXPORT
Dart_Handle Dart_NewError(const char* format, ...);

DART_EXPORT
Dart_Handle Dart_NewInternalError(const char* message);

DART_EXPORT
Dart_Handle Dart_EnvironmentCallbackDefault(Dart_Handle name);

DART_EXPORT
bool Dart_EntropySourceDefault(uint8_t* buffer, intptr_t length);

DART_EXPORT
void Dart_BuiltinSetNativeResolver(enum BuiltinLibraryId id);

DART_EXPORT
void Dart_VmServiceSetNativeResolver(void);

DART_EXPORT
Dart_Handle Dart_PrepareForScriptLoading(bool is_service_isolate, bool trace_loading);

DART_EXPORT
Dart_Handle Dart_SetupIOLibrary(const char* namespc_path, const char* script_uri, bool disable_exit);

DART_EXPORT
Dart_Handle Dart_SetupPackageConfig(const char* packages_file);

DART_EXPORT
Dart_Handle Dart_LibraryTagHandlerDefault(Dart_LibraryTag tag, Dart_Handle library, Dart_Handle url);

#ifdef __cplusplus
}
#endif

#endif