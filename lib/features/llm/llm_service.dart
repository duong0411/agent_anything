import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../../bindings/rac_bindings.dart';

class LlmService {
  Pointer<Pointer<Void>>? _handle;

  bool get isLoaded => _handle != null && _handle!.value != nullptr;

  LlmService() {
    _handle = calloc<Pointer<Void>>();
  }

  void dispose() {
    if (_handle != null) {
      calloc.free(_handle!);
      _handle = null;
    }
  }

  Future<void> initialize() async {
    final bindings = RacBindings();
    final result = bindings.racLlmComponentCreate(_handle!);
    if (result != 0) {
      throw Exception("Failed to create LLM component: $result");
    }
  }

  Future<void> loadModel(String modelPath) async {
    if (!isLoaded) await initialize();

    final bindings = RacBindings();
    final pathPtr = modelPath.toNativeUtf8();
    final idPtr = "default_model".toNativeUtf8();
    final namePtr = "Llama Model".toNativeUtf8();

    try {
      final result = bindings.racLlmComponentLoadModel(
        _handle!.value,
        pathPtr,
        idPtr,
        namePtr,
      );

      if (result != 0) {
        throw Exception("Failed to load model: $result");
      }
    } finally {
      calloc.free(pathPtr);
      calloc.free(idPtr);
      calloc.free(namePtr);
    }
  }

  Future<String> generate(String prompt) async {
    if (!isLoaded) throw Exception("LLM component not loaded");

    final bindings = RacBindings();
    final promptPtr = prompt.toNativeUtf8();
    
    // Configure Options
    final options = calloc<RacLlmOptions>();
    options.ref.max_tokens = 256;
    options.ref.temperature = 0.7;
    options.ref.top_p = 0.9;
    options.ref.streaming_enabled = 0; // False for now
    options.ref.stop_sequences = nullptr;
    options.ref.num_stop_sequences = 0;
    options.ref.system_prompt = nullptr;

    // Result struct
    final result = calloc<RacLlmResult>();

    try {
      final status = bindings.racLlmComponentGenerate(
        _handle!.value,
        promptPtr,
        options,
        result,
      );

      if (status != 0) {
        throw Exception("Generation failed with status: $status");
      }

      // Copy text to Dart String
      final generatedText = result.ref.text.toDartString();
      
      // Free result resources using C API
      bindings.racLlmResultFree(result);
      
      return generatedText;
    } finally {
      calloc.free(promptPtr);
      calloc.free(options);
      calloc.free(result);
    }
  }
}
