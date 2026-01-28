# Mobile Multi-Agent Voice Assistant System
**Architecture Plan for Offline Voice-Controlled Multi-Agent System on Android**

---

## 🎯 System Overview

### Vision
Build an **offline, voice-controlled multi-agent system** on mobile that can:
- ✅ Accept voice commands (VAD + STT)
- ✅ Plan and execute tasks using LLM reasoning
- ✅ Control phone functions (call, SMS, apps)
- ✅ Respond via Text-to-Speech (TTS)
- ✅ Run 100% offline and on-device

### Example Use Cases
1. **"Call my mom"** → Agent plans → Executes phone call
2. **"What's the weather?"** → Agent opens weather app → Reads result
3. **"Send message to John: I'll be late"** → Agent sends SMS
4. **"Set alarm for 6 AM"** → Agent controls system settings

---

## 🏗️ Architecture Design

```
┌─────────────────────────────────────────────────────────────┐
│                    FLUTTER UI LAYER                         │
│  (Voice Input Button, Agent Status Display, Chat History)  │
└──────────────────┬──────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────────────┐
│              ORCHESTRATOR LAYER (Dart)                      │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  AgentOrchestrator                                  │   │
│  │  - Task Planning (LLM-based)                        │   │
│  │  - Agent Selection & Coordination                   │   │
│  │  - Execution Flow Control                           │   │
│  └─────────────────────────────────────────────────────┘   │
└──────────────────┬──────────────────────────────────────────┘
                   │
    ┌──────────────┼──────────────┬────────────┐
    ▼              ▼              ▼            ▼
┌────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ Voice  │  │ Planning │  │ Executor │  │ Tool     │
│ Agent  │  │ Agent    │  │ Agent    │  │ Registry │
└────────┘  └──────────┘  └──────────┘  └──────────┘
    │             │             │             │
    └─────────────┴─────────────┼─────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────┐
│                    CORE SERVICES (C++)                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │   VAD    │→│   STT    │→│   LLM    │→│   TTS    │   │
│  │ (Silero) │  │(Whisper) │  │ (Llama)  │  │ (Piper)  │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
└─────────────────────────────────────────────────────────────┘
                                │
┌───────────────────────────────▼─────────────────────────────┐
│                ANDROID PLATFORM LAYER                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │  Phone   │  │   SMS    │  │  Apps    │  │ Settings │   │
│  │  API     │  │  API     │  │  Intent  │  │  API     │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 📦 Component Breakdown

### 1️⃣ Voice Agent
**Role**: Handle voice input/output pipeline

```dart
class VoiceAgent extends BaseAgent {
  final VoiceAgentHandle _nativeHandle; // C++ VoiceAgent
  
  @override
  Future<AgentResult> execute(AgentTask task) async {
    // 1. VAD: Detect speech
    final audioBuffer = await _recordAudio();
    
    // 2. STT: Transcribe
    final transcription = await _sttTranscribe(audioBuffer);
    
    // 3. Return to orchestrator
    return AgentResult(
      success: true,
      data: {'transcription': transcription}
    );
  }
  
  Future<void> speak(String text) async {
    // TTS output
    await _ttsSpeak(text);
  }
}
```

### 2️⃣ Planning Agent
**Role**: Use LLM to understand intent and create execution plan

```dart
class PlanningAgent extends BaseAgent {
  final LlamaService _llm;
  
  @override
  Future<AgentResult> execute(AgentTask task) async {
    final userInput = task.data['transcription'];
    
    // Build planning prompt
    final prompt = _buildPlanningPrompt(userInput);
    
    // LLM reasoning
    final response = await _llm.generate(prompt);
    
    // Parse plan (JSON format)
    final plan = _parsePlan(response);
    
    return AgentResult(
      success: true,
      data: {'plan': plan}
    );
  }
  
  String _buildPlanningPrompt(String input) {
    return '''
You are a mobile assistant. Given user input, create an execution plan.

Available Tools:
- phone_call(contact_name)
- send_sms(contact_name, message)
- open_app(app_name)
- get_weather(location)
- set_alarm(time)
- web_search(query)

User Input: "$input"

Respond in JSON:
{
  "intent": "...",
  "tool": "...",
  "parameters": {...}
}
''';
  }
}
```

### 3️⃣ Executor Agent
**Role**: Execute planned actions using tools

```dart
class ExecutorAgent extends BaseAgent {
  final ToolRegistry _toolRegistry;
  
  @override
  Future<AgentResult> execute(AgentTask task) async {
    final plan = task.data['plan'];
    
    // Get tool
    final tool = _toolRegistry.getTool(plan['tool']);
    
    // Execute
    final result = await tool.execute(plan['parameters']);
    
    return AgentResult(
      success: true,
      data: {'execution_result': result}
    );
  }
}
```

### 4️⃣ Tool Registry
**Role**: Manage available tools and permissions

```dart
class ToolRegistry {
  final Map<String, Tool> _tools = {};
  
  void registerTool(Tool tool) {
    _tools[tool.name] = tool;
  }
  
  Tool? getTool(String name) => _tools[name];
  
  List<String> getAvailableTools() => _tools.keys.toList();
}

// Base Tool Interface
abstract class Tool {
  String get name;
  String get description;
  Map<String, dynamic> get parameterSchema;
  
  Future<dynamic> execute(Map<String, dynamic> params);
}
```

---

## 🛠️ Mobile Tools Implementation

### Phone Call Tool
```dart
class PhoneCallTool extends Tool {
  @override
  String get name => 'phone_call';
  
  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final contactName = params['contact_name'];
    
    // 1. Search contact in phone
    final contact = await ContactsService.getContact(contactName);
    
    if (contact == null) {
      return {'error': 'Contact not found'};
    }
    
    // 2. Initiate call
    final uri = Uri.parse('tel:${contact.phoneNumber}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return {'success': true, 'action': 'Call initiated'};
    }
    
    return {'error': 'Cannot make call'};
  }
}
```

### SMS Tool
```dart
class SMSTool extends Tool {
  @override
  String get name => 'send_sms';
  
  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final contactName = params['contact_name'];
    final message = params['message'];
    
    final contact = await ContactsService.getContact(contactName);
    
    final uri = Uri.parse('sms:${contact.phoneNumber}?body=$message');
    await launchUrl(uri);
    
    return {'success': true};
  }
}
```

### Weather Tool
```dart
class WeatherTool extends Tool {
  @override
  String get name => 'get_weather';
  
  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    // Option 1: Open weather app
    const weatherPackage = 'com.google.android.googlequicksearchbox';
    final intent = AndroidIntent(
      action: 'android.intent.action.VIEW',
      package: weatherPackage,
      // Or use deep link
    );
    await intent.launch();
    
    // Option 2: Local weather data (if available)
    // Return mock for now
    return {
      'temperature': '25°C',
      'condition': 'Sunny',
      'location': 'Hanoi'
    };
  }
}
```

### App Launcher Tool
```dart
class AppLauncherTool extends Tool {
  @override
  String get name => 'open_app';
  
  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final appName = params['app_name'];
    
    // Map app names to package IDs
    final packageMap = {
      'youtube': 'com.google.android.youtube',
      'maps': 'com.google.android.apps.maps',
      'camera': 'com.android.camera',
      // ... more apps
    };
    
    final packageId = packageMap[appName.toLowerCase()];
    if (packageId != null) {
      await DeviceApps.openApp(packageId);
      return {'success': true};
    }
    
    return {'error': 'App not found'};
  }
}
```

### Alarm Tool
```dart
class AlarmTool extends Tool {
  @override
  String get name => 'set_alarm';
  
  @override
  Future<dynamic> execute(Map<String, dynamic> params) async {
    final time = params['time']; // "6:00 AM"
    
    final intent = AndroidIntent(
      action: 'android.intent.action.SET_ALARM',
      arguments: {
        'android.intent.extra.alarm.HOUR': 6,
        'android.intent.extra.alarm.MINUTES': 0,
      },
    );
    await intent.launch();
    
    return {'success': true};
  }
}
```

---

## 🔄 Agent Orchestration Flow

```dart
class AgentOrchestrator {
  final VoiceAgent _voiceAgent;
  final PlanningAgent _planningAgent;
  final ExecutorAgent _executorAgent;
  final ToolRegistry _toolRegistry;
  
  Future<void> processVoiceCommand() async {
    try {
      // 1. Voice Input
      _updateStatus('Listening...');
      final voiceResult = await _voiceAgent.execute(
        AgentTask(type: TaskType.listen)
      );
      
      final transcription = voiceResult.data['transcription'];
      _updateStatus('Heard: "$transcription"');
      
      // 2. Planning
      _updateStatus('Planning...');
      final planResult = await _planningAgent.execute(
        AgentTask(
          type: TaskType.plan,
          data: {'transcription': transcription}
        )
      );
      
      final plan = planResult.data['plan'];
      _updateStatus('Plan: ${plan['intent']}');
      
      // 3. Execution
      _updateStatus('Executing...');
      final execResult = await _executorAgent.execute(
        AgentTask(
          type: TaskType.execute,
          data: {'plan': plan}
        )
      );
      
      // 4. Voice Response
      final responseText = _buildResponse(execResult);
      await _voiceAgent.speak(responseText);
      _updateStatus('Done!');
      
    } catch (e) {
      _updateStatus('Error: $e');
      await _voiceAgent.speak('Sorry, I encountered an error.');
    }
  }
  
  String _buildResponse(AgentResult execResult) {
    // Convert execution result to natural language
    if (execResult.success) {
      return 'Done! I completed the task.';
    } else {
      return 'Sorry, I could not complete that.';
    }
  }
}
```

---

## 📁 Project Structure

```
lib/
├── agents/
│   ├── base/
│   │   ├── agent.dart              # Base Agent interface
│   │   ├── agent_task.dart         # Task definition
│   │   └── agent_result.dart       # Result wrapper
│   ├── voice_agent.dart            # VoiceAgent
│   ├── planning_agent.dart         # PlanningAgent
│   └── executor_agent.dart         # ExecutorAgent
│
├── orchestrator/
│   └── agent_orchestrator.dart     # Main orchestrator
│
├── tools/
│   ├── tool.dart                   # Tool interface
│   ├── tool_registry.dart          # Tool registry
│   ├── phone_call_tool.dart
│   ├── sms_tool.dart
│   ├── weather_tool.dart
│   ├── app_launcher_tool.dart
│   └── alarm_tool.dart
│
├── services/
│   ├── llama_service.dart          # LLM wrapper
│   ├── stt_service.dart            # STT wrapper
│   └── tts_service.dart            # TTS wrapper
│
└── ui/
    └── agent_chat_screen.dart      # UI for agent interaction
```

---

## 🔐 Permissions Required (AndroidManifest.xml)

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO"/>
<uses-permission android:name="android.permission.READ_CONTACTS"/>
<uses-permission android:name="android.permission.CALL_PHONE"/>
<uses-permission android:name="android.permission.SEND_SMS"/>
<uses-permission android:name="android.permission.SET_ALARM"/>
<uses-permission android:name="android.permission.INTERNET"/> <!-- For weather API if online -->
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
```

---

## 📦 Dependencies (pubspec.yaml)

```yaml
dependencies:
  # Flutter basics
  flutter:
    sdk: flutter
  
  # Phone integration
  url_launcher: ^6.2.2
  contacts_service: ^0.6.3
  android_intent_plus: ^4.0.3
  device_apps: ^2.2.0
  permission_handler: ^11.1.0
  
  # State management
  provider: ^6.1.1
  
  # JSON parsing
  json_annotation: ^4.8.1
```

---

## 🚀 Implementation Roadmap

### Phase 1: Foundation (Week 1-2)
- [ ] Setup agent base classes
- [ ] Integrate existing VAD+STT+LLM+TTS from C++ layer
- [ ] Build basic orchestrator
- [ ] Create tool registry

### Phase 2: Core Tools (Week 3-4)
- [ ] Phone call tool
- [ ] SMS tool
- [ ] App launcher tool
- [ ] Alarm tool
- [ ] Test each tool independently

### Phase 3: LLM Planning (Week 5-6)
- [ ] Design planning prompts
- [ ] Implement plan parser
- [ ] Test intent recognition accuracy
- [ ] Fine-tune LLM prompts

### Phase 4: Integration (Week 7-8)
- [ ] Connect all agents in orchestrator
- [ ] Build UI for agent status
- [ ] Add conversation history
- [ ] Error handling and retry logic

### Phase 5: Optimization (Week 9-10)
- [ ] Optimize LLM inference speed
- [ ] Reduce latency in tool execution
- [ ] Add caching for common queries
- [ ] Battery optimization

---

## 🎓 Next Steps

1. **Create base agent framework**
   ```bash
   mkdir -p lib/agents/base
   # Create agent.dart, agent_task.dart, agent_result.dart
   ```

2. **Wrap existing C++ services**
   ```dart
   // lib/services/llama_service.dart
   class LlamaService {
     Future<String> generate(String prompt) {
       // Call existing C++ LlamaCPP backend
     }
   }
   ```

3. **Build first tool**
   ```bash
   # Start with simplest: AppLauncherTool
   touch lib/tools/app_launcher_tool.dart
   ```

Would you like me to start implementing any specific component? I can create:
- Base agent classes
- Tool registry implementation  
- Sample phone call tool
- Orchestrator skeleton

Just let me know which part to begin with! 🚀
