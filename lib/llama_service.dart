import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// Type definitions for C functions
typedef InitFfiC = Void Function(Pointer<Utf8> backendPath);
typedef InitFfiDart = void Function(Pointer<Utf8> backendPath);

typedef LoadModelC = Int32 Function(Pointer<Utf8> modelPath);
typedef LoadModelDart = int Function(Pointer<Utf8> modelPath);

typedef PrepareSessionC = Int32 Function();
typedef PrepareSessionDart = int Function();

typedef ProcessSystemPromptC = Int32 Function(Pointer<Utf8> systemPrompt);
typedef ProcessSystemPromptDart = int Function(Pointer<Utf8> systemPrompt);

typedef ProcessUserPromptC = Int32 Function(Pointer<Utf8> userPrompt, Int32 nPredict);
typedef ProcessUserPromptDart = int Function(Pointer<Utf8> userPrompt, int nPredict);

typedef GenerateNextTokenC = Pointer<Utf8> Function();
typedef GenerateNextTokenDart = Pointer<Utf8> Function();

typedef StopGenerationC = Void Function();
typedef StopGenerationDart = void Function();

typedef ResetConversationC = Void Function();
typedef ResetConversationDart = void Function();

typedef UnloadFfiC = Void Function();
typedef UnloadFfiDart = void Function();

typedef ShutdownFfiC = Void Function();
typedef ShutdownFfiDart = void Function();

typedef GetSystemInfoC = Pointer<Utf8> Function();
typedef GetSystemInfoDart = Pointer<Utf8> Function();

class LlamaService {
  late DynamicLibrary _nativeLib;

  late InitFfiDart _initFfi;
  late LoadModelDart _loadModel;
  late PrepareSessionDart _prepareSession;
  late ProcessSystemPromptDart _processSystemPrompt;
  late ProcessUserPromptDart _processUserPrompt;
  late GenerateNextTokenDart _generateNextToken;
  late StopGenerationDart _stopGeneration;
  late ResetConversationDart _resetConversation;
  late UnloadFfiDart _unloadFfi;
  late ShutdownFfiDart _shutdownFfi;
  late GetSystemInfoDart _getSystemInfo;

  bool _isInitialized = false;
  bool _isLoaded = false;
  bool _isGenerating = false;

  LlamaService() {
    _loadLibrary();
  }

  void _loadLibrary() {
    if (Platform.isAndroid) {
      try {
        _nativeLib = DynamicLibrary.open('libai-chat.so');
      } catch (e) {
        try {
          _nativeLib = DynamicLibrary.open('libai_chat.so');
        } catch (_) {
          _nativeLib = DynamicLibrary.process();
        }
      }
    } else if (Platform.isLinux) {
      _nativeLib = DynamicLibrary.process();
    } else {
      _nativeLib = DynamicLibrary.process();
    }

    // Bind all FFI functions
    _initFfi = _nativeLib
        .lookup<NativeFunction<InitFfiC>>('init_ffi')
        .asFunction();

    _loadModel = _nativeLib
        .lookup<NativeFunction<LoadModelC>>('load_model_ffi')
        .asFunction();

    _prepareSession = _nativeLib
        .lookup<NativeFunction<PrepareSessionC>>('prepare_session_ffi')
        .asFunction();

    _processSystemPrompt = _nativeLib
        .lookup<NativeFunction<ProcessSystemPromptC>>('process_system_prompt_ffi')
        .asFunction();

    _processUserPrompt = _nativeLib
        .lookup<NativeFunction<ProcessUserPromptC>>('process_user_prompt_ffi')
        .asFunction();

    _generateNextToken = _nativeLib
        .lookup<NativeFunction<GenerateNextTokenC>>('generate_next_token_ffi')
        .asFunction();

    _stopGeneration = _nativeLib
        .lookup<NativeFunction<StopGenerationC>>('stop_generation_ffi')
        .asFunction();

    _resetConversation = _nativeLib
        .lookup<NativeFunction<ResetConversationC>>('reset_conversation_ffi')
        .asFunction();

    _unloadFfi = _nativeLib
        .lookup<NativeFunction<UnloadFfiC>>('unload_ffi')
        .asFunction();

    _shutdownFfi = _nativeLib
        .lookup<NativeFunction<ShutdownFfiC>>('shutdown_ffi')
        .asFunction();

    _getSystemInfo = _nativeLib
        .lookup<NativeFunction<GetSystemInfoC>>('get_system_info_ffi')
        .asFunction();
  }

  /// Initialize the backend (must be called before loading model)
  void init({String? backendPath}) {
    if (_isInitialized) {
      print("Backend already initialized");
      return;
    }

    final pathPtr = (backendPath ?? "").toNativeUtf8();
    try {
      _initFfi(pathPtr);
      _isInitialized = true;
      print("Backend initialized successfully");
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// Get system information
  String getSystemInfo() {
    final infoPtr = _getSystemInfo();
    if (infoPtr == nullptr) {
      return "System info not available";
    }
    return infoPtr.toDartString();
  }

  /// Load model from file path
  bool loadModel(String modelPath, {String? systemPrompt}) {
    if (!File(modelPath).existsSync()) {
      print("Model file not found: $modelPath");
      return false;
    }

    // Ensure backend is initialized
    if (!_isInitialized) {
      init();
    }

    // Load model
    final pathPtr = modelPath.toNativeUtf8();
    try {
      final result = _loadModel(pathPtr);
      if (result != 0) {
        print("Failed to load model (error code: $result)");
        return false;
      }
    } finally {
      calloc.free(pathPtr);
    }

    // Prepare session
    final sessResult = _prepareSession();
    if (sessResult != 0) {
      print("Failed to prepare session (error code: $sessResult)");
      return false;
    }

    // Process system prompt if provided
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      if (!setSystemPrompt(systemPrompt)) {
        print("Failed to set system prompt");
        return false;
      }
    }

    _isLoaded = true;
    print("Model loaded successfully");
    return true;
  }

  /// Set or update system prompt
  bool setSystemPrompt(String systemPrompt) {
    if (!_isLoaded) {
      print("Model not loaded");
      return false;
    }

    final promptPtr = systemPrompt.toNativeUtf8();
    try {
      final result = _processSystemPrompt(promptPtr);
      if (result != 0) {
        print("Failed to process system prompt (error code: $result)");
        return false;
      }
      print("System prompt set successfully");
      return true;
    } finally {
      calloc.free(promptPtr);
    }
  }

  /// Generate response stream for user prompt
  Stream<String> prompt(String text, {int maxTokens = 2048}) async* {
    if (!_isLoaded) {
      throw Exception("Model not loaded");
    }

    if (_isGenerating) {
      throw Exception("Already generating. Stop current generation first.");
    }

    _isGenerating = true;

    try {
      // Process user prompt
      final promptPtr = text.toNativeUtf8();
      int result;
      try {
        result = _processUserPrompt(promptPtr, maxTokens);
      } finally {
        calloc.free(promptPtr);
      }

      if (result != 0) {
        throw Exception("Failed to process user prompt (error code: $result)");
      }

      // Generate tokens
      while (_isGenerating) {
        final tokenPtr = _generateNextToken();

        // nullptr means end of generation
        if (tokenPtr == nullptr) {
          break;
        }

        final token = tokenPtr.toDartString();
        // Note: tokenPtr points to static buffer in C++, no need to free

        if (token.isNotEmpty) {
          yield token;
        }
        // Empty string means partial UTF-8, continue accumulating
      }
    } finally {
      _isGenerating = false;
    }
  }

  /// Stop current generation
  void stopGeneration() {
    if (_isGenerating) {
      _isGenerating = false;
      _stopGeneration();
      print("Generation stopped");
    }
  }

  /// Reset conversation (clears chat history but keeps model loaded)
  void resetConversation() {
    if (!_isLoaded) {
      print("Model not loaded");
      return;
    }
    _resetConversation();
    print("Conversation reset");
  }

  /// Unload model and free resources
  void unload() {
    if (!_isLoaded) {
      return;
    }

    _isGenerating = false;
    _unloadFfi();
    _isLoaded = false;
    print("Model unloaded");
  }

  /// Shutdown backend completely
  void shutdown() {
    unload();
    if (_isInitialized) {
      _shutdownFfi();
      _isInitialized = false;
      print("Backend shutdown");
    }
  }

  /// Check if model is loaded
  bool get isLoaded => _isLoaded;

  /// Check if currently generating
  bool get isGenerating => _isGenerating;

  /// Check if backend is initialized
  bool get isInitialized => _isInitialized;
}