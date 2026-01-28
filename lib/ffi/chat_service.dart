import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'ai_chat_ffi.dart';
import 'chat_message.dart';

// Commands for the Isolate
enum ChatCommand {
  initialize,
  loadModel,
  setSystemPrompt,
  processUserPrompt,
  generateNextToken,
  stopGeneration,
  resetConversation,
  getSystemInfo,
  dispose
}

class ChatService {
  bool _isInitialized = false;
  bool _modelLoaded = false;
  bool _isGenerating = false;

  final List<ChatMessage> _messages = [];
  final StreamController<List<ChatMessage>> _messagesController =
      StreamController<List<ChatMessage>>.broadcast();

  // Isolate communication
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  Completer<void>? _initCompleter;
  
  // Pending requests (for simple command-response)
  Completer<dynamic>? _pendingCommandCompleter;

  Stream<List<ChatMessage>> get messages => _messagesController.stream;
  List<ChatMessage> get currentMessages => List.unmodifiable(_messages);
  bool get isGenerating => _isGenerating;

  /// Initialize FFI and backend in the background isolate
  Future<void> initialize() async {
    if (_isInitialized) return;

    print('[ChatService] Spawning Isolate...');
    _receivePort = ReceivePort();
    _initCompleter = Completer<void>();
    
    // Spawn isolate
    _isolate = await Isolate.spawn(
      _isolateEntry, 
      _receivePort!.sendPort,
      debugName: 'AIChatIsolate'
    );

    // Wait for first message (SendPort)
    final firstMessage = await _receivePort!.first;
    if (firstMessage is SendPort) {
      _sendPort = firstMessage;
      print('[ChatService] Isolate connected');
    } else {
      throw Exception('Failed to connect to isolate');
    }
    
    // Setup listener for subsequent messages
    _receivePort = ReceivePort(); // New port for ongoing comms
    _sendPort!.send(_receivePort!.sendPort); // Handshake
    
    _receivePort!.listen(_handleIsolateMessage);
    
    // Send initialize command
    await _sendCommand(ChatCommand.initialize, null);

    _isInitialized = true;
    print('[ChatService] Service initialized');
  }

  void _handleIsolateMessage(dynamic message) {
    if (message is Map) {
      final type = message['type'];
      final data = message['data'];
      
      if (type == 'response') {
        if (_pendingCommandCompleter != null && !_pendingCommandCompleter!.isCompleted) {
          _pendingCommandCompleter!.complete(data);
          _pendingCommandCompleter = null;
        }
      } else if (type == 'token') {
        _handleNewToken(data as String);
      } else if (type == 'generation_done') {
        _handleGenerationDone();
      } else if (type == 'log') {
        print('[Isolate] ${data}');
      } else if (type == 'error') {
         if (_pendingCommandCompleter != null && !_pendingCommandCompleter!.isCompleted) {
          _pendingCommandCompleter!.completeError(data);
          _pendingCommandCompleter = null;
        }
        print('[ChatService] Error from isolate: $data');
      }
    }
  }

  Future<dynamic> _sendCommand(ChatCommand command, dynamic args) {
    if (_pendingCommandCompleter != null) {
      // In a real app we might want a queue, but here we just wait or error?
      // For now, assume sequential usage except for cancellation (stop)
      if (command == ChatCommand.stopGeneration) {
        // Allow stop even if pending
      } else {
        // print('[ChatService] Warning: Command overlap for $command');
      }
    }
    _pendingCommandCompleter = Completer<dynamic>();
    _sendPort!.send({'command': command, 'args': args});
    return _pendingCommandCompleter!.future;
  }

  /// Load model from assets or file system
  Future<bool> loadModel(String modelPath) async {
    if (!_isInitialized) {
      await initialize();
    }

    print('[ChatService] Loading model from: $modelPath');

    // Check if path is an asset
    String actualPath = modelPath;
    if (modelPath.startsWith('assets/models')) {
      // Copy asset to temporary directory on MAIN THREAD (IO available)
      actualPath = await _copyAssetToTemp(modelPath);
    }

    try {
      final result = await _sendCommand(ChatCommand.loadModel, actualPath);
      if (result == true) {
        _modelLoaded = true;
        print('[ChatService] Model loaded successfully');
        return true;
      }
      return false;
    } catch (e) {
      print('[ChatService] Failed to load model: $e');
      return false;
    }
  }

  /// Set system prompt
  Future<bool> setSystemPrompt(String prompt) async {
    if (!_modelLoaded) return false;

    print('[ChatService] Setting system prompt');
    try {
      final result = await _sendCommand(ChatCommand.setSystemPrompt, prompt);
      if (result == true) {
         // Add system message to chat
        _messages.clear();
        _messages.add(ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          role: MessageRole.system,
          content: prompt,
        ));
        _messagesController.add(_messages);
        return true;
      }
      return false;
    } catch (e) {
      print('Error setting prompt: $e');
      return false;
    }
  }

  /// Send user message and get streaming response
  Future<void> sendMessage(String userMessage, {int maxTokens = 512}) async {
    if (!_modelLoaded || _isGenerating) return;

    _isGenerating = true;

    // Add user message
    final userMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.user,
      content: userMessage,
    );
    _messages.add(userMsg);
    _messagesController.add(_messages);

    print('[ChatService] Processing user prompt: $userMessage');
    
    // Create assistant message (streaming)
    final assistantMsg = ChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      role: MessageRole.assistant,
      content: '',
      isComplete: false,
    );
    _messages.add(assistantMsg);
    _messagesController.add(_messages);
    
    // Send command to isolate to start processing and generating
    // We send payload to tell it to loop tokens automatically
    _sendPort!.send({
      'command': ChatCommand.processUserPrompt, 
      'args': {'prompt': userMessage, 'maxTokens': maxTokens}
    });
    
    // Note: We don't await a single response here, we listen for 'token' events
  }

  void _handleNewToken(String token) {
    if (!_isGenerating) return;
    final lastIndex = _messages.length - 1;
    final currentContent = _messages[lastIndex].content;
    
    _messages[lastIndex] = _messages[lastIndex].copyWith(
      content: currentContent + token,
    );
    _messagesController.add(_messages);
  }

  void _handleGenerationDone() {
    if (!_isGenerating) return;
    _isGenerating = false;
    final lastIndex = _messages.length - 1;
    _messages[lastIndex] = _messages[lastIndex].copyWith(
      isComplete: true,
    );
    _messagesController.add(_messages);
    print('[ChatService] Generation complete');
  }

  /// Stop current generation
  void stopGeneration() {
    if (!_isGenerating) return;
    print('[ChatService] Stopping generation');
    _sendPort!.send({'command': ChatCommand.stopGeneration});
    _isGenerating = false;
  }

  /// Reset conversation
  void resetConversation() {
    print('[ChatService] Resetting conversation');
    _sendPort!.send({'command': ChatCommand.resetConversation});
    _messages.clear();
    _messagesController.add(_messages);
  }

  /// Get system info
  Future<String> getSystemInfo() async {
    return await _sendCommand(ChatCommand.getSystemInfo, null) as String;
  }

  /// Cleanup resources
  Future<void> dispose() async {
    print('[ChatService] Disposing resources');
    if (_sendPort != null) {
      _sendPort!.send({'command': ChatCommand.dispose});
    }
    await Future.delayed(Duration(milliseconds: 500));
    _isolate?.kill();
    _isolate = null;
    await _messagesController.close();
  }

  Future<String> _copyAssetToTemp(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    final tempDir = Directory.systemTemp;
    final fileName = assetPath.split('/').last;
    final tempFile = File('${tempDir.path}/$fileName');
    await tempFile.writeAsBytes(byteData.buffer.asUint8List());
    print('[ChatService] Copied asset to: ${tempFile.path}');
    return tempFile.path;
  }
}

// -----------------------------------------------------------------------------
// Isolate Entry Point
// -----------------------------------------------------------------------------
void _isolateEntry(SendPort mainSendPort) {
  // Setup communication channel
  final isolateReceivePort = ReceivePort();
  mainSendPort.send(isolateReceivePort.sendPort);

  // Listen for handshake to get the main response port
  isolateReceivePort.listen((message) {
    if (message is SendPort) {
      final responsePort = message;
      // Now switch to command loop
      isolateReceivePort.close();
      final commandReceivePort = ReceivePort();
      responsePort.send({'type': 'response', 'data': null}); // Ack (not really needed but ok) - Actually wait, the init protocol was: 
      // 1. spawn -> send isolateReceivePort
      // 2. main gets isolateReceivePort -> sets _sendPort
      // 3. main creates _receivePort -> sends _receivePort.sendPort to isolate
      // 4. isolate gets mainReceivePort -> loop
      
      // Let's restart the listen logic to match what I wrote above.
      // Re-reading `initialize`:
      // _sendPort!.send(_receivePort!.sendPort);
      
      _isolateLoop(commandReceivePort, responsePort);
    }
  });
}

void _isolateLoop(ReceivePort commandPort, SendPort responsePort) {
  // We need to re-initialize FFI bindings here? 
  // AIChatFFI is a static class. We need to make sure dlopen is called.
  
  commandPort.listen((message) async {
    if (message is! Map) return;
    
    final command = message['command'] as ChatCommand;
    final args = message['args'];
    
    try {
      switch (command) {
        case ChatCommand.initialize:
          AIChatFFI.initialize();
          AIChatFFI.initBackend();
          responsePort.send({'type': 'response', 'data': true});
          break;
          
        case ChatCommand.loadModel:
          final path = args as String;
          final result = AIChatFFI.loadModel(path);
          if (result == 0) {
            final sessionResult = AIChatFFI.prepareSession();
             responsePort.send({'type': 'response', 'data': sessionResult == 0});
          } else {
             responsePort.send({'type': 'error', 'data': 'Load failed code $result'});
          }
          break;
          
        case ChatCommand.setSystemPrompt:
          final prompt = args as String;
          final result = AIChatFFI.processSystemPrompt(prompt);
          responsePort.send({'type': 'response', 'data': result == 0});
          break;
          
        case ChatCommand.processUserPrompt:
          // This starts the generation loop
          final prompt = args['prompt'] as String;
          final maxTokens = args['maxTokens'] as int;
          
          final result = AIChatFFI.processUserPrompt(prompt, maxTokens: maxTokens);
          if (result != 0) {
            responsePort.send({'type': 'error', 'data': 'Process prompt failed $result'});
          } else {
            // Start generation loop inside isolate
            _generateTokensLoop(responsePort);
          }
          break;
          
        case ChatCommand.stopGeneration:
          AIChatFFI.stopGeneration();
          // The loop breaks automatically? No, we check condition in loop.
          break;
          
        case ChatCommand.resetConversation:
          AIChatFFI.resetConversation();
          break;
          
        case ChatCommand.getSystemInfo:
          final info = AIChatFFI.getSystemInfo();
          responsePort.send({'type': 'response', 'data': info});
          break;
          
        case ChatCommand.dispose:
          AIChatFFI.unload();
          AIChatFFI.shutdown();
          Isolate.exit();
          break;
          
        default:
          break;
      }
    } catch (e, stack) {
      responsePort.send({'type': 'error', 'data': e.toString()});
      print(stack);
    }
  });
}

// Helper to run the generation loop synchronously in the isolate
void _generateTokensLoop(SendPort responsePort) {
  while (true) {
    // We can add a check for stop flag? 
    // AIChatFFI.generateNextToken() returns null when done or stopped.
    // If stopGeneration was called, the C++ state 'stop_generation_position' or internal flag might be set?
    // In current ai_chat.cpp: stop_generation_ffi resets short term states.
    // generate_next_token_ffi checks stop_generation_position. 
    // So if we call stopGeneration from another event?
    // Wait. Isolates are single threaded event loops.
    // If we are in this while(true) loop, we CANNOT process the 'stopGeneration' message from the port!
    // THIS IS A PROBLEM.
    // We need to yield to the event loop or check the port?
    // Dart isolates don't support checking port synchronously easily without blocking?
    // Actually, we can use `Future.delayed(Duration.zero)` to yield, but that makes it async.
    // Better: generate one token, send it, then schedule next generation as a microtask or just async loop.
    
    // BUT we want blocking speed if possible? No, async is fine for 20-30 tokens/sec.
    
    // Changing to async loop allows processing "stop" command in between.
    
    // However, for this simple implementation, let's just loop with a small yield.
    // But yield won't help if we are in a tight loop unless we return to event loop.
    
    // Let's make this _generateTokensLoop NOT a loop, but a recursive future or loop with await.
    // But we are inside the message handler...
    // We should NOT block the message handler.
    
    // We can spawn a separate runner? No.
    // We just return from the handler, but kick off an async operation.
    
    _generateNextTokenAsync(responsePort);
    break;
  }
}

Future<void> _generateNextTokenAsync(SendPort responsePort) async {
  // Generate one token
  final token = AIChatFFI.generateNextToken();
  
  if (token == null) {
    responsePort.send({'type': 'generation_done'});
    return;
  }
  
  if (token.isNotEmpty) {
    responsePort.send({'type': 'token', 'data': token});
  }
  
  // Yield to allow processing other events (like Stop)
  await Future.delayed(Duration.zero);
  
  // Recursively call for next (or loop)
  // Check if we should stop?
  // C++ side handles stop logic via `stop_generation_ffi` which resets state, so `generateNextToken` will return null or empty? 
  // Let's verify ai_chat.cpp. 
  // `stop_generation_ffi` calls `reset_short_term_states`. 
  // `reset_short_term_states` sets `stop_generation_position = 0`.
  // `generate_next_token_ffi` checks `current_position >= stop_generation_position`.
  // If we reset to 0, and current is > 0, it returns nullptr.
  // So yes, calling stopGeneration works, IF the command is processed.
  // By using `await Future.delayed(Duration.zero)`, we allow the Isolate event loop to process the 'stopGeneration' command message.
  
  _generateNextTokenAsync(responsePort);
}

