import 'package:flutter/material.dart';
import 'dart:async';
import '../services/openai_realtime_websocket.dart';
import '../services/audio_streaming_service.dart';
import '../services/http_conversation_service.dart';
import '../core/logger.dart';

/// Realtime Conversation Screen with WebSocket API
/// Falls back to HTTP API if Realtime access is unavailable
class RealtimeConversationScreen extends StatefulWidget {
  const RealtimeConversationScreen({Key? key}) : super(key: key);

  @override
  State<RealtimeConversationScreen> createState() => _RealtimeConversationScreenState();
}

class _RealtimeConversationScreenState extends State<RealtimeConversationScreen>
    with TickerProviderStateMixin {
  // Services
  late OpenAIRealtimeWebSocket _websocket;
  AudioStreamingService? _audioService;
  HTTPConversationService? _httpService;  // Fallback service
  
  // State
  bool _isConnected = false;
  bool _isConnecting = true;
  bool _isRecording = false;
  bool _useRealtimeAPI = true;
  String _connectionStatus = 'Connecting...';
  String _userTranscript = '';
  String _aiResponse = '';
  
  // Audio visualization
  List<double> _waveformData = List.filled(50, 0.0);
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  // Text input
  final TextEditingController _textController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _initializeAnimation();
    _initializeRealtime();
  }
  
  void _initializeAnimation() {
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
  
  Future<void> _initializeRealtime() async {
    setState(() {
      _isConnecting = true;
      _connectionStatus = 'Initializing Realtime API...';
    });
    
    _websocket = OpenAIRealtimeWebSocket();
    
    // Setup stream listeners
    _setupStreamListeners();
    
    try {
      // Test Realtime API access first
      AppLogger.info('Testing Realtime API access...');
      final hasAccess = await _websocket.testConnection();
      
      if (hasAccess) {
        // Connect to Realtime API
        await _websocket.connect();
        _audioService = AudioStreamingService(_websocket);
        
        // Setup audio level listener
        _audioService!.audioLevelStream.listen((level) {
          _updateWaveformData(level);
        });
        
        setState(() {
          _isConnected = true;
          _isConnecting = false;
          _useRealtimeAPI = true;
          _connectionStatus = 'Connected to Realtime API';
        });
        
        AppLogger.info('Successfully connected to Realtime API');
      } else {
        // Fallback to HTTP API
        _showFallbackDialog();
      }
    } catch (e) {
      AppLogger.error('Realtime connection failed', e);
      _showFallbackDialog();
    }
  }
  
  void _setupStreamListeners() {
    // Connection status
    _websocket.connectionStatusStream.listen((connected) {
      setState(() {
        _isConnected = connected;
        _connectionStatus = connected ? 'Connected' : 'Disconnected';
      });
    });
    
    // User transcript
    _websocket.transcriptStream.listen((transcript) {
      setState(() {
        _userTranscript = transcript;
      });
    });
    
    // AI response
    _websocket.responseStream.listen((response) {
      setState(() {
        _aiResponse = response;
      });
    });
    
    // Errors
    _websocket.errorStream.listen((error) {
      _showErrorSnackBar(error);
      
      // Check if it's an auth error
      if (error.contains('access denied') || error.contains('unauthorized')) {
        _showFallbackDialog();
      }
    });
  }
  
  void _showFallbackDialog() {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Realtime API Unavailable'),
        content: const Text(
          'Realtime API access is not available with your API key.\n\n'
          'This may be due to:\n'
          '• Insufficient credits (minimum \$5 required)\n'
          '• API key without Realtime access\n'
          '• Quota limits exceeded\n\n'
          'Would you like to use the HTTP-based conversation instead?'
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);  // Go back
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _useHTTPFallback();
            },
            child: const Text('Use HTTP API'),
          ),
        ],
      ),
    );
  }
  
  void _useHTTPFallback() async {
    setState(() {
      _isConnecting = true;
      _useRealtimeAPI = false;
      _connectionStatus = 'Switching to HTTP API...';
    });
    
    // Initialize HTTP service
    _httpService = HTTPConversationService();
    await _httpService!.initialize();
    
    // Setup HTTP service listeners
    _httpService!.transcriptStream.listen((transcript) {
      setState(() {
        _userTranscript = transcript;
      });
    });
    
    _httpService!.responseStream.listen((response) {
      setState(() {
        _aiResponse = response;
      });
    });
    
    _httpService!.audioLevelStream.listen((level) {
      _updateWaveformData(level);
    });
    
    setState(() {
      _isConnected = true;
      _isConnecting = false;
      _connectionStatus = 'Connected (HTTP Mode)';
    });
  }
  
  void _toggleRecording() async {
    if (_useRealtimeAPI && _audioService != null) {
      // Realtime API recording
      await _audioService!.toggleRecording();
      setState(() {
        _isRecording = _audioService!.isRecording;
      });
      
      if (_isRecording) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
      }
    } else if (_httpService != null) {
      // HTTP API recording
      if (_isRecording) {
        await _httpService!.stopRecording();
      } else {
        await _httpService!.startRecording();
      }
      
      setState(() {
        _isRecording = _httpService!.isRecording;
      });
      
      if (_isRecording) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
      }
    }
  }
  
  void _sendTextMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    
    _textController.clear();
    
    if (_useRealtimeAPI) {
      _websocket.sendText(text);
    } else if (_httpService != null) {
      _httpService!.sendTextMessage(text);
    }
  }
  
  void _updateWaveformData(double level) {
    setState(() {
      final newData = List<double>.from(_waveformData);
      newData.removeAt(0);
      newData.add(level * 100);
      _waveformData = newData;
    });
  }
  
  void _showErrorSnackBar(String error) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 3),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Realtime Voice Conversation',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _isConnecting
            ? _buildLoadingView()
            : _buildConversationView(),
      ),
    );
  }
  
  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blueAccent),
          ),
          const SizedBox(height: 20),
          Text(
            _connectionStatus,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildConversationView() {
    return Column(
      children: [
        // Connection status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isConnected ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _connectionStatus,
                style: TextStyle(
                  color: _isConnected ? Colors.green : Colors.red,
                  fontSize: 14,
                ),
              ),
              if (!_useRealtimeAPI) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Text(
                    'HTTP',
                    style: TextStyle(
                      color: Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        
        // Conversation display
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_userTranscript.isNotEmpty) ...[
                  const Text(
                    'You said:',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _userTranscript,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                if (_aiResponse.isNotEmpty) ...[
                  const Text(
                    'AI Response:',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _aiResponse,
                    style: const TextStyle(
                      color: Colors.blueAccent,
                      fontSize: 18,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        
        // Waveform visualization
        Container(
          height: 100,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _waveformData.map((height) {
              return Container(
                width: 4,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: _isRecording
                      ? Colors.redAccent
                      : Colors.blueAccent.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(2),
                ),
                height: height.clamp(5.0, 100.0),
              );
            }).toList(),
          ),
        ),
        
        // Recording button
        Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              GestureDetector(
                onTapDown: (_) => _toggleRecording(),
                onTapUp: (_) => _toggleRecording(),
                onTapCancel: () {
                  if (_isRecording) _toggleRecording();
                },
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _isRecording ? _pulseAnimation.value : 1.0,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: _isRecording
                                ? [Colors.red, Colors.red.shade900]
                                : [Colors.blue, Colors.blue.shade900],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _isRecording
                                  ? Colors.red.withOpacity(0.5)
                                  : Colors.blue.withOpacity(0.5),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Icon(
                          _isRecording ? Icons.stop : Icons.mic,
                          color: Colors.white,
                          size: 50,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _isRecording
                    ? (_useRealtimeAPI ? 'Release to send' : 'Recording... Tap to stop')
                    : 'Hold to speak',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        
        // Text input option
        Container(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Or type your message...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => _sendTextMessage(),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: _sendTextMessage,
                icon: const Icon(Icons.send, color: Colors.blueAccent),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _textController.dispose();
    _websocket.dispose();
    _audioService?.dispose();
    _httpService?.dispose();
    super.dispose();
  }
}