import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import 'core/rac_core.dart';
import 'features/llm/llm_service.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RunAnywhere Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  final LlmService _llmService = LlmService();
  bool _isModelLoaded = false;
  bool _isGenerating = false;
  String _status = "Initializing...";

  @override
  void initState() {
    super.initState();
    _initSdk();
  }

  Future<void> _initSdk() async {
    try {
      // 1. Initialize Core
      RacCore.initialize();
      
      // 2. Load Model (Copy from assets to internal storage if needed)
      // Note: For demo simplicity, we assume the model is manually placed or we download it.
      // But here we will try to look for a known path or asset.
      // REPLACE THIS PATH with your actual model path on device
      // e.g. /data/user/0/com.example.flutter_application_1/app_flutter/model.gguf
      final  dir = await getApplicationDocumentsDirectory();
      final modelPath = "${dir.path}/model.gguf";
      
      // Check if model exists, if not, show instruction
      if (!File(modelPath).existsSync()) {
        setState(() {
          _status = "Model not found at $modelPath.\nPlease copy a .gguf model there.";
        });
        return;
      }

      setState(() {
        _status = "Loading model...";
      });

      await _llmService.loadModel(modelPath);

      setState(() {
        _isModelLoaded = true;
        _status = "Ready";
      });
    } catch (e) {
      setState(() {
        _status = "Error: $e";
      });
    }
  }

  @override
  void dispose() {
    _llmService.dispose();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || !_isModelLoaded || _isGenerating) return;

    _controller.clear();
    setState(() {
      _messages.add({"role": "user", "content": text});
      _isGenerating = true;
    });
    
    _scrollToBottom();

    try {
      final response = await _llmService.generate(text);
      
      setState(() {
        _messages.add({"role": "assistant", "content": response});
      });
    } catch (e) {
      setState(() {
        _messages.add({"role": "system", "content": "Error: $e"});
      });
    } finally {
      setState(() {
        _isGenerating = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RunAnywhere Chat'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(20),
            child: 
            Text(_status, style: const TextStyle(fontSize: 12))
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['role'] == 'user';
                final isSystem = msg['role'] == 'system';
                
                return Align(
                  alignment: isSystem ? Alignment.center : (isUser ? Alignment.centerRight : Alignment.centerLeft),
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSystem 
                          ? Colors.red.shade100 
                          : (isUser ? Colors.blue.shade100 : Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                    child: Text(msg['content'] ?? ""),
                  ),
                );
              },
            ),
          ),
          if (_isGenerating)
             const Padding(
               padding: EdgeInsets.all(8.0),
               child: LinearProgressIndicator(),
             ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}