import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/openai_realtime_websocket.dart';
import '../services/realtime_audio_service.dart';
import '../core/logger.dart';

/// Realtime API 전용 대화 화면
/// WebSocket 기반 실시간 음성 대화 인터페이스
class RealtimeOnlyScreen extends StatefulWidget {
  const RealtimeOnlyScreen({super.key});

  @override
  State<RealtimeOnlyScreen> createState() => _RealtimeOnlyScreenState();
}

class _RealtimeOnlyScreenState extends State<RealtimeOnlyScreen>
    with TickerProviderStateMixin {
  
  // Core Services
  late final OpenAIRealtimeWebSocket _websocket;
  late final RealtimeAudioService _audioService;
  
  // Animation Controllers
  late AnimationController _waveController;
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;
  
  // UI State
  bool _isListening = false;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _currentTranscript = '';
  String _aiResponse = '';
  double _audioLevel = 0.0;
  String _connectionStatus = 'Disconnected';
  
  // Message History
  final List<ConversationMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  
  // Stream Subscriptions
  final List<StreamSubscription> _subscriptions = [];
  
  // Waveform Data
  List<double> _waveformData = List.filled(50, 0.0);
  Timer? _waveformTimer;
  
  @override
  void initState() {
    super.initState();
    _initializeServices();
    _setupAnimations();
    _connectToRealtimeAPI();
  }
  
  void _initializeServices() {
    _websocket = OpenAIRealtimeWebSocket();
    _audioService = RealtimeAudioService();
    
    // Listen to WebSocket events
    _subscriptions.add(
      _websocket.connectionStatusStream.listen((isConnected) {
        if (mounted) {
          setState(() {
            _isConnected = isConnected;
            _connectionStatus = isConnected ? 'Connected' : 'Disconnected';
            if (!isConnected) {
              _isListening = false;
            }
          });
        }
      }),
    );
    
    _subscriptions.add(
      _websocket.transcriptStream.listen((transcript) {
        if (mounted) {
          setState(() {
            _currentTranscript = transcript;
            if (transcript.isNotEmpty) {
              _addMessage(ConversationMessage(
                text: transcript,
                isUser: true,
                timestamp: DateTime.now(),
              ));
            }
          });
        }
      }),
    );
    
    _subscriptions.add(
      _websocket.responseStream.listen((response) {
        if (mounted) {
          setState(() {
            _aiResponse = response;
            if (response.isNotEmpty) {
              _addMessage(ConversationMessage(
                text: response,
                isUser: false,
                timestamp: DateTime.now(),
              ));
            }
          });
        }
      }),
    );
    
    _subscriptions.add(
      _websocket.errorStream.listen((error) {
        if (mounted) {
          _showError(error);
        }
      }),
    );
    
    // Listen for audio data from WebSocket and play it
    _subscriptions.add(
      _websocket.audioDataStream.listen((audioData) {
        // Convert Uint8List to base64 for playback
        final base64Audio = base64Encode(audioData);
        _audioService.playAudioChunk(base64Audio);
      }),
    );
    
    _subscriptions.add(
      _audioService.audioLevelStream.listen((level) {
        if (mounted) {
          setState(() {
            _audioLevel = level;
            _updateWaveform(level);
          });
        }
      }),
    );
  }
  
  void _setupAnimations() {
    _waveController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));
    
    _waveformTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_isListening && mounted) {
        setState(() {
          _waveformData = List.generate(50, (i) {
            return _audioLevel * (0.5 + 0.5 * sin(i * 0.2 + _waveController.value * 2 * pi));
          });
        });
      }
    });
  }
  
  Future<void> _connectToRealtimeAPI() async {
    if (_isConnecting || _isConnected) return;
    
    setState(() {
      _isConnecting = true;
      _connectionStatus = 'Connecting...';
    });
    
    try {
      await _websocket.connect();
      _fadeController.forward();
      
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectionStatus = 'Connected';
        });
      }
    } catch (e) {
      AppLogger.error('Failed to connect to Realtime API', e);
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _connectionStatus = 'Connection failed';
        });
        _showError('Failed to connect: ${e.toString()}');
      }
    }
  }
  
  Future<void> _toggleListening() async {
    if (!_isConnected) {
      await _connectToRealtimeAPI();
      return;
    }
    
    setState(() {
      _isListening = !_isListening;
    });
    
    if (_isListening) {
      _pulseController.repeat(reverse: true);
      // Start recording and send audio to WebSocket
      await _audioService.startRecording((audioData) {
        // Send audio to Realtime API
        _websocket.sendAudioData(audioData);
      });
    } else {
      _pulseController.stop();
      _pulseController.reset();
      await _audioService.stopRecording();
    }
  }
  
  void _addMessage(ConversationMessage message) {
    setState(() {
      _messages.add(message);
    });
    
    // Scroll to bottom
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
  
  void _updateWaveform(double level) {
    // Update waveform visualization based on audio level
    if (_waveformData.isNotEmpty) {
      _waveformData = _waveformData.map((v) {
        return v * 0.9 + level * 0.1; // Smooth transition
      }).toList();
    }
  }
  
  void _showError(String message) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 4),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(),
            
            // Connection Status
            _buildConnectionStatus(),
            
            // Messages Area
            Expanded(
              child: _buildMessagesArea(),
            ),
            
            // Waveform Visualizer
            if (_isListening) _buildWaveform(),
            
            // Control Panel
            _buildControlPanel(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white70),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          const Text(
            'AI Voice Chat',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.purple.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.bolt,
                  size: 16,
                  color: Colors.purple.shade300,
                ),
                const SizedBox(width: 4),
                Text(
                  'Realtime API',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.purple.shade300,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildConnectionStatus() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _connectionStatus == 'Connected' ? 0 : 40,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isConnecting)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
            ),
          if (!_isConnecting)
            Icon(
              _isConnected ? Icons.check_circle : Icons.error_outline,
              size: 16,
              color: _isConnected ? Colors.green : Colors.orange,
            ),
          const SizedBox(width: 8),
          Text(
            _connectionStatus,
            style: TextStyle(
              fontSize: 12,
              color: _isConnected ? Colors.green : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMessagesArea() {
    if (_messages.isEmpty) {
      return Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.mic_none,
                size: 64,
                color: Colors.white.withOpacity(0.2),
              ),
              const SizedBox(height: 16),
              Text(
                'Tap the microphone to start',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.white.withOpacity(0.4),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Powered by OpenAI Realtime API',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.3),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(20),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _buildMessageBubble(message);
      },
    );
  }
  
  Widget _buildMessageBubble(ConversationMessage message) {
    final isUser = message.isUser;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.purple, Colors.blue],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.auto_awesome, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isUser ? Colors.blue.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isUser ? Colors.blue.withOpacity(0.5) : Colors.white.withOpacity(0.1),
                ),
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.person, size: 18, color: Colors.white),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildWaveform() {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_waveformData.length, (index) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            margin: const EdgeInsets.symmetric(horizontal: 1),
            width: 4,
            height: 20 + _waveformData[index] * 40,
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.7),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }
  
  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Microphone Button
          Center(
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _isListening ? _pulseAnimation.value : 1.0,
                  child: GestureDetector(
                    onTap: _toggleListening,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _isListening
                              ? [Colors.red.shade600, Colors.red.shade800]
                              : [Colors.blue.shade600, Colors.purple.shade600],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(40),
                        boxShadow: [
                          BoxShadow(
                            color: (_isListening ? Colors.red : Colors.blue).withOpacity(0.5),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Status Text
          Text(
            _isListening ? 'Listening...' : 'Tap to speak',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
          
          // Current Transcript (if speaking)
          if (_currentTranscript.isNotEmpty && _isListening)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _currentTranscript,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.8),
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    // Cancel all subscriptions
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    
    // Stop services
    _audioService.dispose();
    _websocket.disconnect();
    
    // Cancel timers
    _waveformTimer?.cancel();
    
    // Dispose animation controllers
    _waveController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    _scrollController.dispose();
    
    super.dispose();
  }
}

// Message Model
class ConversationMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  
  ConversationMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}