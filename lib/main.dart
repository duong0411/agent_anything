import 'package:flutter/material.dart';
import 'package:flutter_application_1/llama_service.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Llama.cpp FFI Chat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ChatPage(),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _modelPathController = TextEditingController();
  final TextEditingController _systemPromptController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final LlamaService _llamaService = LlamaService();

  final List<ChatMessage> _messages = [];
  bool _isGenerating = false;
  bool _isCopying = false;
  String _currentResponse = "";
  int _maxTokens = 2048;
  static const platform = MethodChannel('com.example.flutter_application_1/helper');

  @override
  void initState() {
    super.initState();
    _systemPromptController.text = "You are a helpful AI assistant.";
    _prepareModel();
  }

  Future<void> _prepareModel() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/qwen2.5-1.5b-instruct-q4_k_m.gguf';
    _modelPathController.text = path;

    if (File(path).existsSync()) {
      _addSystemMessage("Model found at $path");
      return;
    }

    setState(() {
      _isCopying = true;
    });

    _addSystemMessage("Copying model from assets... (this may take a while)");

    try {
      // Use native (Kotlin) copy to avoid memory issues with large files
      _addSystemMessage("Starting native copy from assets...");
      
      final bool? result = await platform.invokeMethod('copyAsset', {
        'assetPath': 'assets/models/qwen2.5-1.5b-instruct-q4_k_m.gguf',
        'targetPath': path,
      });

      if (result == true) {
        _addSystemMessage("Model copied efficiently to $path");
      } else {
        throw Exception("Native copy returned false");
      }
    } catch (e) {
      _addSystemMessage("Error copying asset (native): $e");
    } finally {
      if (mounted) {
        setState(() {
          _isCopying = false;
        });
      }
    }
  }

  void _loadModel() async {
    final path = _modelPathController.text;
    if (path.isEmpty) {
      _addSystemMessage("Please provide a model path");
      return;
    }

    _addSystemMessage("Loading model...");

    try {
      // Load model with system prompt
      final success = _llamaService.loadModel(
        path,
        systemPrompt: _systemPromptController.text.trim(),
      );

      if (success) {
        _addSystemMessage("Model loaded successfully!");
        // Show system info
        final systemInfo = _llamaService.getSystemInfo();
        _addSystemMessage("System: $systemInfo");
      } else {
        _addSystemMessage("Failed to load model");
      }
    } catch (e) {
      _addSystemMessage("Error loading model: $e");
    }
  }

  void _updateSystemPrompt() {
    if (!_llamaService.isLoaded) {
      _addSystemMessage("Please load model first");
      return;
    }

    final prompt = _systemPromptController.text.trim();
    if (prompt.isEmpty) {
      _addSystemMessage("System prompt cannot be empty");
      return;
    }

    try {
      final success = _llamaService.setSystemPrompt(prompt);
      if (success) {
        _addSystemMessage("System prompt updated");
      } else {
        _addSystemMessage("Failed to update system prompt");
      }
    } catch (e) {
      _addSystemMessage("Error updating system prompt: $e");
    }
  }

  void _sendMessage() async {
    final text = _promptController.text.trim();
    if (text.isEmpty || !_llamaService.isLoaded || _isGenerating) return;

    // Add user message
    _addMessage(ChatMessage(role: MessageRole.user, content: text));
    _promptController.clear();

    setState(() {
      _isGenerating = true;
      _currentResponse = "";
    });

    // Add placeholder for AI response
    _addMessage(ChatMessage(role: MessageRole.assistant, content: ""));

    try {
      await for (final token in _llamaService.prompt(text, maxTokens: _maxTokens)) {
        setState(() {
          _currentResponse += token;
          // Update last message
          _messages.last = ChatMessage(
            role: MessageRole.assistant,
            content: _currentResponse,
          );
        });
        _scrollToBottom();
      }
    } catch (e) {
      _addSystemMessage("Error generating: $e");
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  void _stopGeneration() {
    if (_isGenerating) {
      _llamaService.stopGeneration();
      setState(() {
        _isGenerating = false;
      });
      _addSystemMessage("Generation stopped");
    }
  }

  void _resetConversation() {
    if (!_llamaService.isLoaded) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Conversation'),
        content: const Text('Are you sure you want to clear the chat history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _llamaService.resetConversation();
              setState(() {
                _messages.clear();
              });
              _addSystemMessage("Conversation reset");
              Navigator.pop(context);
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  void _addMessage(ChatMessage message) {
    setState(() {
      _messages.add(message);
    });
    _scrollToBottom();
  }

  void _addSystemMessage(String content) {
    _addMessage(ChatMessage(role: MessageRole.system, content: content));
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

  void _showSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _systemPromptController,
              decoration: const InputDecoration(
                labelText: 'System Prompt',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('Max Tokens:'),
                const SizedBox(width: 16),
                Expanded(
                  child: Slider(
                    value: _maxTokens.toDouble(),
                    min: 128,
                    max: 4096,
                    divisions: 15,
                    label: _maxTokens.toString(),
                    onChanged: (value) {
                      setState(() {
                        _maxTokens = value.toInt();
                      });
                    },
                  ),
                ),
                Text(_maxTokens.toString()),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              _updateSystemPrompt();
              Navigator.pop(context);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _llamaService.shutdown();
    _scrollController.dispose();
    _modelPathController.dispose();
    _systemPromptController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Llama FFI Chat'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_llamaService.isLoaded) ...[
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showSettings,
              tooltip: 'Settings',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _resetConversation,
              tooltip: 'Reset Conversation',
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          // Model loading section
          if (!_llamaService.isLoaded)
            Container(
              color: Colors.grey[200],
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _modelPathController,
                          decoration: const InputDecoration(
                            labelText: 'Path to GGUF Model',
                            hintText: '/path/to/model.gguf',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _isCopying ? null : _loadModel,
                        child: _isCopying 
                            ? const SizedBox(
                                width: 20, 
                                height: 20, 
                                child: CircularProgressIndicator(strokeWidth: 2)
                              ) 
                            : const Text('Load Model'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _systemPromptController,
                    decoration: const InputDecoration(
                      labelText: 'System Prompt (optional)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),

          // Status bar
          if (_llamaService.isLoaded)
            Container(
              color: Colors.green[100],
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  const Text('Model loaded'),
                  const Spacer(),
                  if (_isGenerating) ...[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    const Text('Generating...'),
                  ],
                ],
              ),
            ),

          const Divider(height: 1),

          // Chat area
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return MessageBubble(message: message);
              },
            ),
          ),

          // Input area
          if (_llamaService.isLoaded)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    spreadRadius: 1,
                    blurRadius: 3,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promptController,
                      enabled: !_isGenerating,
                      decoration: const InputDecoration(
                        labelText: 'Enter your message',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_isGenerating)
                    IconButton(
                      icon: const Icon(Icons.stop),
                      onPressed: _stopGeneration,
                      color: Colors.red,
                      tooltip: 'Stop Generation',
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: _sendMessage,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// Message model
enum MessageRole { system, user, assistant }

class ChatMessage {
  final MessageRole role;
  final String content;

  ChatMessage({required this.role, required this.content});
}

// Message bubble widget
class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final isSystem = message.role == MessageRole.system;

    if (isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        child: Center(
          child: Text(
            message.content,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
        padding: const EdgeInsets.all(12.0),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser ? Colors.blue[100] : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUser ? 'You' : 'AI',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isUser ? Colors.blue[900] : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message.content,
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}