import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';

// ============================================================================
// FFI Type Definitions
// ============================================================================

// Native function signatures
typedef InitFFINative = ffi.Void Function(ffi.Pointer<Utf8>);
typedef LoadModelFFINative = ffi.Int32 Function(ffi.Pointer<Utf8>);
typedef PrepareSessionFFINative = ffi.Int32 Function();
typedef ProcessSystemPromptFFINative = ffi.Int32 Function(ffi.Pointer<Utf8>);
typedef ProcessUserPromptFFINative = ffi.Int32 Function(ffi.Pointer<Utf8>, ffi.Int32);
typedef GenerateNextTokenFFINative = ffi.Pointer<Utf8> Function();
typedef StopGenerationFFINative = ffi.Void Function();
typedef ResetConversationFFINative = ffi.Void Function();
typedef UnloadFFINative = ffi.Void Function();
typedef ShutdownFFINative = ffi.Void Function();
typedef GetSystemInfoFFINative = ffi.Pointer<Utf8> Function();

// Dart function signatures
typedef InitFFIDart = void Function(ffi.Pointer<Utf8>);
typedef LoadModelFFIDart = int Function(ffi.Pointer<Utf8>);
typedef PrepareSessionFFIDart = int Function();
typedef ProcessSystemPromptFFIDart = int Function(ffi.Pointer<Utf8>);
typedef ProcessUserPromptFFIDart = int Function(ffi.Pointer<Utf8>, int);
typedef GenerateNextTokenFFIDart = ffi.Pointer<Utf8> Function();
typedef StopGenerationFFIDart = void Function();
typedef ResetConversationFFIDart = void Function();
typedef UnloadFFIDart = void Function();
typedef ShutdownFFIDart = void Function();
typedef GetSystemInfoFFIDart = ffi.Pointer<Utf8> Function();

// ============================================================================
// AIChatFFI - Main FFI Wrapper Class
// ============================================================================

class AIChatFFI {
  static ffi.DynamicLibrary? _lib;
  static bool _initialized = false;

  // Function pointers
  static late final InitFFIDart _initFFI;
  static late final LoadModelFFIDart _loadModel;
  static late final PrepareSessionFFIDart _prepareSession;
  static late final ProcessSystemPromptFFIDart _processSystemPrompt;
  static late final ProcessUserPromptFFIDart _processUserPrompt;
  static late final GenerateNextTokenFFIDart _generateNextToken;
  static late final StopGenerationFFIDart _stopGeneration;
  static late final ResetConversationFFIDart _resetConversation;
  static late final UnloadFFIDart _unload;
  static late final ShutdownFFIDart _shutdown;
  static late final GetSystemInfoFFIDart _getSystemInfo;

  /// Initialize FFI library
  static void initialize() {
    if (_initialized) return;

    // Load the native library
    if (Platform.isAndroid) {
      _lib = ffi.DynamicLibrary.open('libai_chat.so');
    } else if (Platform.isIOS || Platform.isMacOS) {
      _lib = ffi.DynamicLibrary.process();
    } else {
      throw UnsupportedError('Platform ${Platform.operatingSystem} is not supported');
    }

    // Lookup functions
    _initFFI = _lib!.lookupFunction<InitFFINative, InitFFIDart>('init_ffi');
    _loadModel = _lib!.lookupFunction<LoadModelFFINative, LoadModelFFIDart>('load_model_ffi');
    _prepareSession = _lib!.lookupFunction<PrepareSessionFFINative, PrepareSessionFFIDart>('prepare_session_ffi');
    _processSystemPrompt = _lib!.lookupFunction<ProcessSystemPromptFFINative, ProcessSystemPromptFFIDart>('process_system_prompt_ffi');
    _processUserPrompt = _lib!.lookupFunction<ProcessUserPromptFFINative, ProcessUserPromptFFIDart>('process_user_prompt_ffi');
    _generateNextToken = _lib!.lookupFunction<GenerateNextTokenFFINative, GenerateNextTokenFFIDart>('generate_next_token_ffi');
    _stopGeneration = _lib!.lookupFunction<StopGenerationFFINative, StopGenerationFFIDart>('stop_generation_ffi');
    _resetConversation = _lib!.lookupFunction<ResetConversationFFINative, ResetConversationFFIDart>('reset_conversation_ffi');
    _unload = _lib!.lookupFunction<UnloadFFINative, UnloadFFIDart>('unload_ffi');
    _shutdown = _lib!.lookupFunction<ShutdownFFINative, ShutdownFFIDart>('shutdown_ffi');
    _getSystemInfo = _lib!.lookupFunction<GetSystemInfoFFINative, GetSystemInfoFFIDart>('get_system_info_ffi');

    _initialized = true;
  }

  /// Initialize llama.cpp backend
  static void initBackend([String backendPath = '']) {
    final pathPtr = backendPath.toNativeUtf8();
    try {
      _initFFI(pathPtr);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Load GGUF model from path
  static int loadModel(String modelPath) {
    final pathPtr = modelPath.toNativeUtf8();
    try {
      return _loadModel(pathPtr);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Prepare session (create context and sampler)
  static int prepareSession() {
    return _prepareSession();
  }

  /// Process system prompt
  static int processSystemPrompt(String prompt) {
    final promptPtr = prompt.toNativeUtf8();
    try {
      return _processSystemPrompt(promptPtr);
    } finally {
      malloc.free(promptPtr);
    }
  }

  /// Process user prompt
  static int processUserPrompt(String prompt, {int maxTokens = 512}) {
    final promptPtr = prompt.toNativeUtf8();
    try {
      return _processUserPrompt(promptPtr, maxTokens);
    } finally {
      malloc.free(promptPtr);
    }
  }

  /// Generate next token (for streaming)
  /// Returns null if generation is complete
  static String? generateNextToken() {
    final tokenPtr = _generateNextToken();
    if (tokenPtr.address == 0) {
      return null; // Generation complete
    }
    final token = tokenPtr.toDartString();
    return token.isEmpty ? '' : token; // Return empty string for continuation
  }

  /// Stop current generation
  static void stopGeneration() {
    _stopGeneration();
  }

  /// Reset conversation (clear chat history)
  static void resetConversation() {
    _resetConversation();
  }

  /// Unload model and free resources
  static void unload() {
    _unload();
  }

  /// Shutdown backend completely
  static void shutdown() {
    _shutdown();
  }

  /// Get system information
  static String getSystemInfo() {
    final infoPtr = _getSystemInfo();
    return infoPtr.toDartString();
  }
}
