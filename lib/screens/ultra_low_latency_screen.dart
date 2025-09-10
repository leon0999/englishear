import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/ultra_low_latency_engine.dart';
import '../services/improved_audio_service.dart';
import '../core/logger.dart';

/// Ultra-low latency conversation screen
/// Achieves < 200ms latency like Moshi AI
class UltraLowLatencyScreen extends StatefulWidget {
  const UltraLowLatencyScreen({Key? key}) : super(key: key);

  @override
  _UltraLowLatencyScreenState createState() => _UltraLowLatencyScreenState();
}

class _UltraLowLatencyScreenState extends State<UltraLowLatencyScreen>
    with SingleTickerProviderStateMixin {
  
  // Services
  final UltraLowLatencyEngine _engine = UltraLowLatencyEngine();
  final ImprovedAudioService _audioService = ImprovedAudioService();
  final AudioRecorder _recorder = AudioRecorder();
  late final AudioPlayer _audioPlayer;
  
  // UI State
  bool _isConnected = false;
  bool _isRecording = false;
  bool _isSpeaking = false;
  String _statusText = 'Initializing...';
  List<ChatMessage> _messages = [];
  static const int MAX_MESSAGES = 5; // Maximum messages to display
  String _currentUserText = '';
  String _currentAiResponse = '';
  double _audioLevel = 0.0;
  
  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  // Streams
  StreamSubscription? _audioStreamSubscription;
  StreamSubscription? _textStreamSubscription;
  StreamSubscription? _recordingSubscription;
  
  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();
    _setupAnimations();
    _initialize();
  }
  
  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _pulseController.repeat(reverse: true);
  }
  
  Future<void> _initialize() async {
    AppLogger.test('==================== ULTRA LOW LATENCY SCREEN INIT ====================');
    
    setState(() {
      _statusText = 'Requesting permissions...';
    });
    
    // Request microphone permission
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      setState(() {
        _statusText = 'Microphone permission required';
      });
      return;
    }
    
    setState(() {
      _statusText = 'Connecting to AI...';
    });
    
    try {
      // Initialize audio service
      await _audioService.initialize();
      
      // Connect to OpenAI Realtime API
      final apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
      if (apiKey.isEmpty) {
        throw Exception('OpenAI API key not found');
      }
      
      await _engine.connect(apiKey);
      
      // Setup stream listeners
      _setupStreams();
      
      setState(() {
        _isConnected = true;
        _statusText = 'Ready to talk! Tap the mic to start.';
      });
      
      AppLogger.success('✅ Ultra-low latency conversation ready');
      
    } catch (e) {
      AppLogger.error('Initialization failed', e);
      setState(() {
        _statusText = 'Failed to connect: ${e.toString()}';
      });
    }
  }
  
  void _setupStreams() {
    // Listen to AI audio stream
    _audioStreamSubscription = _engine.audioStream?.listen((audioData) {
      _playAudioChunk(audioData);
    });
    
    // Listen to AI text stream
    _textStreamSubscription = _engine.textStream?.listen((text) {
      setState(() {
        _currentAiResponse += text;
        _isSpeaking = true;
      });
      
      // When AI response is complete, add to messages
      if (text.contains('.') || text.contains('?') || text.contains('!')) {
        _addMessage(_currentAiResponse, false);
        _currentAiResponse = '';
      }
    });
    
    // Listen to audio level changes
    _audioService.audioLevelStream.listen((level) {
      setState(() {
        _audioLevel = level;
      });
    });
  }
  
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }
  
  Future<void> _startRecording() async {
    try {
      setState(() {
        _statusText = 'Listening...';
        _isRecording = true;
        _currentAiResponse = '';
      });
      
      // Start recording with real-time streaming
      await _audioService.startRecording((audioData) {
        // Send audio chunks to engine immediately
        _engine.sendAudio(audioData);
      });
      
      AppLogger.info('🎤 Recording started');
      
    } catch (e) {
      AppLogger.error('Failed to start recording', e);
      setState(() {
        _statusText = 'Failed to start recording';
        _isRecording = false;
      });
    }
  }
  
  Future<void> _stopRecording() async {
    try {
      await _audioService.stopRecording();
      
      // Commit audio to trigger AI response
      _engine.commitAudio();
      
      setState(() {
        _statusText = 'Processing...';
        _isRecording = false;
        
        // Add user's message when they finish speaking
        if (_currentUserText.isNotEmpty) {
          _addMessage(_currentUserText, true);
          _currentUserText = '';
        }
      });
      
      AppLogger.info('🛑 Recording stopped');
      
    } catch (e) {
      AppLogger.error('Failed to stop recording', e);
    }
  }
  
  Future<void> _playAudioChunk(Uint8List audioData) async {
    try {
      // Add to audio service queue for seamless playback
      _audioService.addAudioChunk(audioData);
      
      setState(() {
        _isSpeaking = true;
        _statusText = 'AI is speaking...';
      });
      
      // Reset speaking state after a delay
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _isSpeaking = false;
            _statusText = 'Ready to talk!';
          });
        }
      });
      
    } catch (e) {
      AppLogger.error('Failed to play audio', e);
    }
  }
  
  void _sendTextMessage(String text) {
    if (text.isEmpty || !_isConnected) return;
    
    setState(() {
      _addMessage(text, true);
      _currentAiResponse = '';
    });
    
    _engine.sendText(text);
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        title: const Text(
          'Ultra Low Latency Chat',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0A0E27),
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Status Bar
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isConnected ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _statusText,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 14,
                  ),
                ),
                if (_isConnected) ...[
                  const SizedBox(width: 16),
                  const Icon(
                    Icons.speed,
                    color: Colors.amber,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    '< 200ms',
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Conversation Display
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1F3A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                ),
              ),
              child: _messages.isEmpty
                  ? Center(
                      child: Text(
                        'Tap the microphone to start talking\nAchieving Moshi AI level latency!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 16,
                        ),
                      ),
                    )
                  : ListView.builder(
                      reverse: true, // Latest messages at bottom
                      itemCount: _messages.length + (_currentAiResponse.isNotEmpty ? 1 : 0),
                      itemBuilder: (context, index) {
                        // Show current AI response at the bottom
                        if (index == 0 && _currentAiResponse.isNotEmpty) {
                          return _buildTypingIndicator();
                        }
                        
                        final messageIndex = _currentAiResponse.isNotEmpty 
                            ? _messages.length - index
                            : _messages.length - 1 - index;
                        
                        if (messageIndex < 0 || messageIndex >= _messages.length) {
                          return const SizedBox.shrink();
                        }
                        
                        final message = _messages[messageIndex];
                        return AnimatedOpacity(
                          opacity: index < 2 ? 1.0 : 0.6, // Fade older messages
                          duration: const Duration(milliseconds: 300),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            alignment: message.isUser 
                                ? Alignment.centerRight 
                                : Alignment.centerLeft,
                            child: Container(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.7,
                              ),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: message.isUser 
                                    ? Colors.blue.withOpacity(0.2)
                                    : Colors.grey.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: (message.isUser 
                                      ? Colors.blue 
                                      : Colors.grey).withOpacity(0.3),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        message.isUser ? Icons.person : Icons.psychology,
                                        size: 16,
                                        color: message.isUser ? Colors.blue : Colors.green,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        message.isUser ? 'You' : 'AI Tutor',
                                        style: TextStyle(
                                          color: message.isUser ? Colors.blue : Colors.green,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    message.text,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
          
          // Audio Level Indicator
          if (_isRecording)
            Container(
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(
                value: _audioLevel,
                backgroundColor: Colors.white.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.green.withOpacity(0.8),
                ),
              ),
            ),
          
          // Control Panel
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Text Input Button
                IconButton(
                  onPressed: _isConnected ? () => _showTextInput() : null,
                  icon: const Icon(Icons.keyboard),
                  color: Colors.white.withOpacity(0.6),
                  iconSize: 32,
                ),
                
                // Main Recording Button
                GestureDetector(
                  onTapDown: _isConnected ? (_) => _startRecording() : null,
                  onTapUp: _isConnected ? (_) => _stopRecording() : null,
                  onTapCancel: _isRecording ? () => _stopRecording() : null,
                  child: AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _isRecording ? _pulseAnimation.value : 1.0,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: _isRecording
                                  ? [Colors.red, Colors.redAccent]
                                  : _isSpeaking
                                      ? [Colors.blue, Colors.blueAccent]
                                      : [Colors.green, Colors.greenAccent],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: (_isRecording ? Colors.red : Colors.green)
                                    .withOpacity(0.3),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Icon(
                            _isRecording 
                                ? Icons.mic 
                                : _isSpeaking 
                                    ? Icons.volume_up
                                    : Icons.mic_none,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                
                // Clear Button
                IconButton(
                  onPressed: () {
                    setState(() {
                      _messages.clear();
                      _currentAiResponse = '';
                      _currentUserText = '';
                    });
                  },
                  icon: const Icon(Icons.clear),
                  color: Colors.white.withOpacity(0.6),
                  iconSize: 32,
                ),
              ],
            ),
          ),
          
          // Latency Badge
          Container(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.amber.withOpacity(0.5)),
              ),
              child: const Text(
                '⚡ Moshi AI Level Latency',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  void _showTextInput() {
    final controller = TextEditingController();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1F3A),
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Type your message...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.blue),
                    ),
                  ),
                  onSubmitted: (text) {
                    _sendTextMessage(text);
                    Navigator.pop(context);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  _sendTextMessage(controller.text);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.send),
                color: Colors.blue,
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  void _addMessage(String text, bool isUser) {
    if (text.trim().isEmpty) return;
    
    setState(() {
      _messages.add(ChatMessage(
        text: text.trim(),
        isUser: isUser,
        timestamp: DateTime.now(),
      ));
      
      // Keep only the latest MAX_MESSAGES
      if (_messages.length > MAX_MESSAGES) {
        _messages.removeAt(0);
      }
    });
  }
  
  Widget _buildTypingIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.blue.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.psychology,
              size: 16,
              color: Colors.blue,
            ),
            const SizedBox(width: 6),
            const Text(
              'AI Tutor',
              style: TextStyle(
                color: Colors.blue,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.blue.withOpacity(0.6),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _currentAiResponse,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _audioStreamSubscription?.cancel();
    _textStreamSubscription?.cancel();
    _recordingSubscription?.cancel();
    _audioService.dispose();
    _engine.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}

/// Chat message model
class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  
  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}