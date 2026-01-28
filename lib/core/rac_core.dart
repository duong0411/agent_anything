import 'dart:ffi';
import 'package:ffi/ffi.dart';
import '../bindings/rac_bindings.dart';

class RacCore {
  static bool _initialized = false;
  static final RacBindings _bindings = RacBindings();

  static void initialize() {
    if (_initialized) return;

    // 1. Initialize Core
    final config = calloc<RacConfig>();
    config.ref.log_level = 3; // Info
    config.ref.platform_adapter = nullptr; // Default adapter
    config.ref.log_tag = "RacDart".toNativeUtf8();
    config.ref.reserved = nullptr;

    final result = _bindings.racInit(config);
    calloc.free(config.ref.log_tag);
    calloc.free(config);

    if (result != 0) {
      print("Failed to initialize RAC Core: $result");
      return;
    }

    // 2. Register Backends
    // Important: manually register LlamaCPP backend since it's statically linked
    final registerResult = _bindings.racRegisterLlama();
    if (registerResult != 0) {
      print("Failed to register LlamaCPP backend: $registerResult");
    } else {
      print("LlamaCPP backend registered successfully");
    }

    _initialized = true;
    print("RAC SDK Initialized");
  }
}
