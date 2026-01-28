import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// =============================================================================
// STRUCTS
// =============================================================================

final class RacConfig extends Struct {
  external Pointer<Void> platform_adapter;
  @Int32()
  external int log_level;
  external Pointer<Utf8> log_tag;
  external Pointer<Void> reserved;
}

final class RacLlmConfig extends Struct {
  external Pointer<Utf8> model_id;
  @Int32()
  external int preferred_framework;
  @Int32()
  external int context_length;
  @Float()
  external double temperature;
  @Int32()
  external int max_tokens;
  external Pointer<Utf8> system_prompt;
  @Int32()
  external int streaming_enabled;
}

final class RacLlmOptions extends Struct {
  @Int32()
  external int max_tokens;
  @Float()
  external double temperature;
  @Float()
  external double top_p;
  external Pointer<Pointer<Utf8>> stop_sequences;
  @Size()
  external int num_stop_sequences;
  @Int32()
  external int streaming_enabled;
  external Pointer<Utf8> system_prompt;
}

final class RacLlmResult extends Struct {
  external Pointer<Utf8> text;
  @Int32()
  external int prompt_tokens;
  @Int32()
  external int completion_tokens;
  @Int32()
  external int total_tokens;
  @Int64()
  external int time_to_first_token_ms;
  @Int64()
  external int total_time_ms;
  @Float()
  external double tokens_per_second;
}

// =============================================================================
// NATIVE FUNCTIONS
// =============================================================================

// rac_init
typedef RacInitC = Int32 Function(Pointer<RacConfig> config);
typedef RacInitDart = int Function(Pointer<RacConfig> config);

// rac_backend_llamacpp_register
typedef RacRegisterLlamaC = Int32 Function();
typedef RacRegisterLlamaDart = int Function();

// rac_llm_component_create
typedef RacLlmComponentCreateC = Int32 Function(Pointer<Pointer<Void>> handle);
typedef RacLlmComponentCreateDart = int Function(Pointer<Pointer<Void>> handle);

// rac_llm_component_load_model
typedef RacLlmComponentLoadModelC = Int32 Function(
    Pointer<Void> handle,
    Pointer<Utf8> model_path,
    Pointer<Utf8> model_id,
    Pointer<Utf8> model_name);
typedef RacLlmComponentLoadModelDart = int Function(
    Pointer<Void> handle,
    Pointer<Utf8> model_path,
    Pointer<Utf8> model_id,
    Pointer<Utf8> model_name);

// rac_llm_component_generate
typedef RacLlmComponentGenerateC = Int32 Function(
    Pointer<Void> handle,
    Pointer<Utf8> prompt,
    Pointer<RacLlmOptions> options,
    Pointer<RacLlmResult> result);
typedef RacLlmComponentGenerateDart = int Function(
    Pointer<Void> handle,
    Pointer<Utf8> prompt,
    Pointer<RacLlmOptions> options,
    Pointer<RacLlmResult> result);

// rac_llm_result_free
typedef RacLlmResultFreeC = Void Function(Pointer<RacLlmResult> result);
typedef RacLlmResultFreeDart = void Function(Pointer<RacLlmResult> result);

// =============================================================================
// BINDINGS CLASS
// =============================================================================

class RacBindings {
  static DynamicLibrary? _lib;

  static DynamicLibrary get lib {
    if (_lib != null) return _lib!;
    
    if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('librac_commons.so');
    } else if (Platform.isIOS || Platform.isMacOS) {
      _lib = DynamicLibrary.process();
    } else {
      throw UnsupportedError('Unsupported platform');
    }
    return _lib!;
  }

  // Lookups
  late final RacInitDart racInit = lib
      .lookupFunction<RacInitC, RacInitDart>('rac_init');

  late final RacRegisterLlamaDart racRegisterLlama = lib
      .lookupFunction<RacRegisterLlamaC, RacRegisterLlamaDart>('rac_backend_llamacpp_register');

  late final RacLlmComponentCreateDart racLlmComponentCreate = lib
      .lookupFunction<RacLlmComponentCreateC, RacLlmComponentCreateDart>('rac_llm_component_create');

  late final RacLlmComponentLoadModelDart racLlmComponentLoadModel = lib
      .lookupFunction<RacLlmComponentLoadModelC, RacLlmComponentLoadModelDart>('rac_llm_component_load_model');

  late final RacLlmComponentGenerateDart racLlmComponentGenerate = lib
      .lookupFunction<RacLlmComponentGenerateC, RacLlmComponentGenerateDart>('rac_llm_component_generate');

  late final RacLlmResultFreeDart racLlmResultFree = lib
      .lookupFunction<RacLlmResultFreeC, RacLlmResultFreeDart>('rac_llm_result_free');

  // Singleton
  static final RacBindings _instance = RacBindings._internal();
  factory RacBindings() => _instance;
  RacBindings._internal();
}
