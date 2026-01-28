# AI Chat với Flutter FFI + llama.cpp

## Tổng quan

Ứng dụng chat AI sử dụng Flutter FFI để gọi trực tiếp llama.cpp C++ library, không qua JNI.

## Cấu trúc thư mục

```
lib/
  ffi/
    ai_chat_ffi.dart    # FFI bindings cho libai_chat.so
    chat_message.dart   # Chat message model
    chat_service.dart   # Service wrapper với streaming
  main.dart             # UI chat

android/app/src/main/cpp/
  ai_chat.cpp           # FFI wrapper C++
  CMakeLists.txt        # Build config cho llama.cpp

assets/models/
  your-model.gguf       # Đặt model GGUF ở đây
```

## Cách setup model

### Bước 1: Download model GGUF

Download một model GGUF nhỏ để test, ví dụ:
- TinyLlama 1.1B: https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF
- Phi-2 2.7B: https://huggingface.co/TheBloke/phi-2-GGUF

Chọn file có `-Q4_K_M.gguf` (quantized 4-bit)

### Bước 2: Đặt model vào assets

```bash
# Tạo thư mục assets/models (đã tạo rồi)
mkdir -p assets/models

# Copy model vào assets
cp /path/to/downloaded-model.gguf assets/models/
```

### Bước 3: Update main.dart

Sửa dòng 59 trong `lib/main.dart`:

```dart
// Thay 'your-model.gguf' bằng tên file model của bạn
const modelPath = 'assets/models/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf';
```

## Build và Run

```bash
# Clean build cũ
flutter clean

# Build APK debug
flutter build apk --debug

# Hoặc run trên device
flutter run
```

## System Prompt

System prompt mặc định (có thể sửa trong `main.dart` dòng 73):

```
You are a helpful AI assistant. You provide clear, accurate, and concise answers.
Be friendly and professional. If you don't know something, admit it rather than making up information.
```

## API FFI

File `ai_chat_ffi.dart` cung cấp các function:

- `AIChatFFI.initialize()` - Load libai_chat.so
- `AIChatFFI.loadModel(path)` - Load GGUF model
- `AIChatFFI.prepareSession()` - Tạo context
- `AIChatFFI.processSystemPrompt(prompt)` - Set system prompt
- `AIChatFFI.processUserPrompt(prompt, maxTokens)` - Process user input
- `AIChatFFI.generateNextToken()` - Generate (streaming)
- `AIChatFFI.stopGeneration()` - Dừng generation
- `AIChatFFI.resetConversation()` - Reset chat
- `AIChatFFI.unload()` - Free memory

## Giao diện Chat

- Hiển thị tin nhắn user và AI
- Streaming tokens real-time
- Nút stop generation
- Nút reset conversation
- Dark theme

## Troubleshooting

### Model không load được

- Kiểm tra file có trong `assets/models/`
- Kiểm tra tên file trong `main.dart`
- Kiểm tra `pubspec.yaml` có `assets/models/`

### Build failed

- Đảm bảo C++ build đã complete
- Check file `libai_chat.so` có trong APK:
  ```bash
  unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep libai_chat
  ```

### App crash khi load model

- Model size quá lớn (thử model nhỏ hơn)
- Device RAM không đủ
- Check Android logs:
  ```bash
  adb logcat | grep AIChatFFI
  ```

## TODO future enhancements

- [ ] Chọn model từ UI
- [ ] Adjust generation parameters (temperature, max_tokens)
- [ ] Save/load conversations
- [ ] Export chat to text file
- [ ] Model download manager
