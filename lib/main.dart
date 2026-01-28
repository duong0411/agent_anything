import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ffi/chat_service.dart';
import 'ffi/chat_message.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Chat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
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
  final ChatService _chatService = ChatService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  bool _isLoading = true;
  String _statusMessage = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    try {
      setState(() {
        _statusMessage = 'Requesting permissions...';
      });

      // Request permissions
      await _requestPermissions();

      setState(() {
        _statusMessage = 'Initializing FFI...';
      });

      await _chatService.initialize();

      setState(() {
        _statusMessage = 'Loading model...';
      });

      // TODO: Update this path to your actual model file
      // Option 1: From assets (place model in assets/models/)
      final modelPath = '/storage/emulated/0/Download/smollm2-360m-instruct-q4_k_m.gguf';
      
      // Option 2: From external storage
      // final modelPath = '/storage/emulated/0/Download/your-model.gguf';

      final modelLoaded = await _chatService.loadModel(modelPath);
      
      if (!modelLoaded) {
        setState(() {
          _statusMessage = 'Failed to load model';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _statusMessage = 'Setting system prompt...';
      });

      // System prompt
      const systemPrompt = '''You are a helpful AI assistant. You provide clear, accurate, and concise answers.
Be friendly and professional. If you don't know something, admit it rather than making up information.''';

      final promptSet = await _chatService.setSystemPrompt(systemPrompt);
      
      if (!promptSet) {
        setState(() {
          _statusMessage = 'Failed to set system prompt';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _isLoading = false;
        _statusMessage = 'Ready to chat!';
      });

      print('System info: ${_chatService.getSystemInfo()}');
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: $e';
        _isLoading = false;
      });
      print('Initialization error: $e');
    }
  }

  Future<void> _requestPermissions() async {
    // Request storage permissions
    Map<Permission, PermissionStatus> statuses = await [
      Permission.storage,
      Permission.manageExternalStorage,
    ].request();

    if (statuses[Permission.storage]!.isGranted || 
        statuses[Permission.manageExternalStorage]!.isGranted) {
      print('Storage permissions granted');
    } else {
      print('Storage permissions denied');
      // On Android 11+, we might need to open settings for Manage External Storage
      if (await Permission.manageExternalStorage.isPermanentlyDenied) {
        openAppSettings();
      }
    }
  }

  void _handleSubmitted(String text) {
    _textController.clear();
    if (text.trim().isEmpty) return;

    _chatService.sendMessage(text.trim());
    _scrollToBottom();
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
        title: const Text('AI Chat'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () {
                _chatService.resetConversation();
              },
              tooltip: 'Reset conversation',
            ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_statusMessage),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<ChatMessage>>(
                    stream: _chatService.messages,
                    initialData: _chatService.currentMessages,
                    builder: (context, snapshot) {
                      final messages = snapshot.data ?? [];
                      
                      if (messages.isEmpty || messages.length == 1) {
                        return Center(
                          child: Text(
                            'Start chatting!',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        );
                      }

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _scrollToBottom();
                      });

                      return ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(8.0),
                        itemCount: messages.length,
                        itemBuilder: (context, index) {
                          final message = messages[index];
                          
                          // Don't show system message in UI
                          if (message.role == MessageRole.system) {
                            return const SizedBox.shrink();
                          }

                          return _buildMessageBubble(message);
                        },
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                _buildInputArea(),
              ],
            ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.role == MessageRole.user;
    
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          color: isUser 
              ? Colors.blue[700] 
              : Colors.grey[800],
          borderRadius: BorderRadius.circular(12.0),
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUser ? 'You' : 'AI',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.grey[300],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message.content,
              style: const TextStyle(fontSize: 16),
            ),
            if (!message.isComplete)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      child: Row(
        children: [
          if (_chatService.isGenerating)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: () {
                _chatService.stopGeneration();
              },
              tooltip: 'Stop generation',
            )
          else
            const SizedBox(width: 48),
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
              ),
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              enabled: !_chatService.isGenerating,
              onSubmitted: _handleSubmitted,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _chatService.isGenerating
                ? null
                : () => _handleSubmitted(_textController.text),
            tooltip: 'Send',
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _chatService.dispose();
    super.dispose();
  }
}