import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/http_conversation_service.dart';
import '../core/logger.dart';

/// Enterprise-grade ChatGPT-level voice conversation screen
/// Features: Real-time voice streaming, waveform visualization, natural conversation flow
class ChatGPTLevelScreen extends StatefulWidget {
  const ChatGPTLevelScreen({super.key});

  @override
  State<ChatGPTLevelScreen> createState() => _ChatGPTLevelScreenState();
}

class _ChatGPTLevelScreenState extends State<ChatGPTLevelScreen> 
    with TickerProviderStateMixin {
  
  // Core Service - HTTP-based conversation service
  late final HTTPConversationService _conversationService;
  
  // Animation Controllers - Smooth UI transitions
  late AnimationController _waveController;
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  
  // Animation Values
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;
  
  // UI State Management
  bool _isListening = false;
  bool _isSpeaking = false;
  bool _isConnected = false;
  bool _isInitialized = false;
  String _currentTranscript = '';
  String _lastCompleteTranscript = '';
  double _audioLevel = 0.0;
  
  // Message History - Conversation flow management
  final List<ConversationMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  
  // Stream Subscriptions - Reactive programming pattern
  StreamSubscription<String>? _transcriptSubscription;
  StreamSubscription<String>? _responseSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<double>? _audioLevelSubscription;
  
  // Waveform Data - Real-time visualization
  List<double> _waveformData = List.filled(50, 0.0);
  Timer? _waveformUpdateTimer;
  
  @override
  void initState() {
    super.initState();
    _initializeServices();
    _setupAnimations();
    _initializeConversationService();
  }

  /// Initialize core services with proper error handling
  void _initializeServices() {
    try {
      _conversationService = HTTPConversationService();
      AppLogger.info('ChatGPT Level Screen: HTTP Conversation Service initialized');
    } catch (e) {
      AppLogger.error('Failed to initialize services', e);
      _showErrorDialog('Service Initialization Error', 'Failed to initialize conversation service. Please restart the app.');
    }
  }

  /// Setup smooth animations for enhanced UX
  void _setupAnimations() {
    // Wave animation for waveform visualization
    _waveController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    
    // Pulse animation for microphone button
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Fade animation for transcript overlay
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
  }

  /// Setup reactive stream subscriptions
  void _setupStreamSubscriptions() {
    // Cancel any existing subscriptions first
    _cancelSubscriptions();
    
    _transcriptSubscription = _conversationService.transcriptStream.listen(
      _handleTranscriptUpdate,
      onError: (error) => AppLogger.error('Transcript stream error', error),
      cancelOnError: false,
    );
    
    _responseSubscription = _conversationService.responseStream.listen(
      _handleAIResponse,
      onError: (error) => AppLogger.error('Response stream error', error),
      cancelOnError: false,
    );
    
    _connectionSubscription = _conversationService.connectionStatusStream.listen(
      _handleConnectionStatusChange,
      onError: (error) => AppLogger.error('Connection status stream error', error),
      cancelOnError: false,
    );
    
    _audioLevelSubscription = _conversationService.audioLevelStream.listen(
      _handleAudioLevelUpdate,
      onError: (error) => AppLogger.error('Audio level stream error', error),
      cancelOnError: false,
    );
  }
  
  /// Cancel all stream subscriptions
  void _cancelSubscriptions() {
    _transcriptSubscription?.cancel();
    _responseSubscription?.cancel();
    _connectionSubscription?.cancel();
    _audioLevelSubscription?.cancel();
    _transcriptSubscription = null;
    _responseSubscription = null;
    _connectionSubscription = null;
    _audioLevelSubscription = null;
  }

  /// Initialize conversation service
  Future<void> _initializeConversationService() async {
    try {
      await _conversationService.initialize();
      _setupStreamSubscriptions();
      setState(() {
        _isInitialized = true;
        _isConnected = true;
      });
      AppLogger.info('Conversation service initialized successfully');
      _addSystemMessage('Connected to AI assistant. Tap the microphone to start conversation.');
    } catch (e) {
      AppLogger.error('Failed to initialize conversation service', e);
      _showRetryDialog();
    }
  }

  /// Handle real-time transcript updates
  void _handleTranscriptUpdate(String transcript) {
    setState(() {
      _currentTranscript = transcript;
      if (transcript.trim().isNotEmpty) {
        _lastCompleteTranscript = transcript;
        _fadeController.forward();
      }
    });
  }

  /// Handle AI response with natural conversation flow
  void _handleAIResponse(String response) {
    _addMessage(ConversationMessage(
      text: response,
      isUser: false,
      timestamp: DateTime.now(),
    ));
    setState(() {
      _isSpeaking = false;
    });
  }

  /// Handle connection status changes with visual feedback
  void _handleConnectionStatusChange(bool isConnected) {
    setState(() {
      _isConnected = isConnected;
    });
    
    if (!isConnected) {
      _addSystemMessage('Connection lost. Attempting to reconnect...');
      _attemptReconnection();
    }
  }

  /// Handle audio level updates for waveform visualization
  void _handleAudioLevelUpdate(double level) {
    setState(() {
      _audioLevel = level;
    });
    _updateWaveformData(level);
  }

  /// Update waveform data for real-time visualization
  void _updateWaveformData(double level) {
    setState(() {
      // Create a new list to avoid fixed-length list issues
      final newData = List<double>.from(_waveformData);
      newData.removeAt(0);
      newData.add(level * 100);
      _waveformData = newData;
    });
  }

  /// Attempt reconnection with exponential backoff
  Future<void> _attemptReconnection() async {
    int retryCount = 0;
    const maxRetries = 3;
    
    while (retryCount < maxRetries && !_isConnected) {
      retryCount++;
      final delay = Duration(seconds: retryCount * 2);
      
      AppLogger.info('Attempting reconnection $retryCount/$maxRetries in ${delay.inSeconds}s');
      await Future.delayed(delay);
      
      try {
        await _conversationService.initialize();
        if (_isConnected) {
          _addSystemMessage('Reconnected successfully!');
          break;
        }
      } catch (e) {
        AppLogger.error('Reconnection attempt $retryCount failed', e);
      }
    }
    
    if (!_isConnected) {
      _showRetryDialog();
    }
  }

  /// Toggle voice recording with haptic feedback
  Future<void> _toggleRecording() async {
    try {
      // Haptic feedback for better UX
      HapticFeedback.mediumImpact();
      
      if (!_isListening) {
        await _startListening();
      } else {
        await _stopListening();
      }
    } catch (e) {
      AppLogger.error('Failed to toggle recording', e);
      _showErrorSnackBar('Recording error: ${e.toString()}');
    }
  }

  /// Start listening with visual feedback
  Future<void> _startListening() async {
    if (!_isConnected) {
      _showErrorSnackBar('Not connected to AI assistant');
      return;
    }
    
    setState(() {
      _isListening = true;
    });
    
    _pulseController.repeat(reverse: true);
    _fadeController.forward();
    
    // Add user message placeholder
    if (_lastCompleteTranscript.trim().isNotEmpty) {
      _addMessage(ConversationMessage(
        text: _lastCompleteTranscript,
        isUser: true,
        timestamp: DateTime.now(),
      ));
    }
    
    await _conversationService.startRecording();
    AppLogger.info('Started listening for voice input');
  }

  /// Stop listening with cleanup
  Future<void> _stopListening() async {
    setState(() {
      _isListening = false;
      _currentTranscript = '';
    });
    
    _pulseController.stop();
    _pulseController.reset();
    _fadeController.reverse();
    
    await _conversationService.stopRecording();
    AppLogger.info('Stopped listening for voice input');
  }

  /// Add message to conversation with auto-scroll
  void _addMessage(ConversationMessage message) {
    setState(() {
      _messages.add(message);
    });
    
    // Auto-scroll to bottom with smooth animation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  /// Add system message for status updates
  void _addSystemMessage(String message) {
    _addMessage(ConversationMessage(
      text: message,
      isUser: false,
      timestamp: DateTime.now(),
      isSystem: true,
    ));
  }

  /// Show error dialog with retry option
  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Show retry dialog for connection issues
  void _showRetryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connection Failed'),
        content: const Text('Unable to connect to AI assistant. Would you like to retry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _initializeConversationService();
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  /// Show error snackbar for quick feedback
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0A0A0A),
              Color(0xFF1A0E2E),
              Color(0xFF2D1B4E),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildMessageList()),
              _buildVoiceInterface(),
              if (_isListening) _buildTranscriptOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  /// Build header with connection status
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              const Text(
                'AI Conversation',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _isConnected ? Colors.green.shade700 : Colors.red.shade700,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _isConnected ? 'Connected' : 'Offline',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_isListening) _buildVoiceLevelIndicator(),
        ],
      ),
    );
  }

  /// Build voice level indicator
  Widget _buildVoiceLevelIndicator() {
    return Container(
      height: 4,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: _audioLevel.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.blue.shade400,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  /// Build message list with conversation history
  Widget _buildMessageList() {
    if (_messages.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mic_none,
              size: 64,
              color: Colors.white38,
            ),
            SizedBox(height: 16),
            Text(
              'Tap the microphone to start\na conversation with AI',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white60,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _buildMessageBubble(message);
      },
    );
  }

  /// Build individual message bubble
  Widget _buildMessageBubble(ConversationMessage message) {
    final isUser = message.isUser;
    final isSystem = message.isSystem;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: isSystem ? Colors.grey.shade700 : Colors.purple.shade700,
              child: Icon(
                isSystem ? Icons.info_outline : Icons.smart_toy,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser 
                  ? Colors.blue.shade700 
                  : isSystem 
                    ? Colors.grey.shade800
                    : Colors.grey.shade700,
                borderRadius: BorderRadius.circular(16).copyWith(
                  topLeft: isUser ? const Radius.circular(16) : Radius.zero,
                  topRight: isUser ? Radius.zero : const Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: isSystem ? FontWeight.w400 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatTimestamp(message.timestamp),
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue,
              child: Icon(
                Icons.person,
                size: 16,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build voice interface with waveform and microphone button
  Widget _buildVoiceInterface() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Waveform visualization
          SizedBox(
            height: 80,
            width: double.infinity,
            child: CustomPaint(
              painter: WaveformPainter(
                waveformData: _waveformData,
                audioLevel: _audioLevel,
                isActive: _isListening,
                animation: _waveController,
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Microphone button with pulse animation
          GestureDetector(
            onTap: _toggleRecording,
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _isListening ? _pulseAnimation.value : 1.0,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: _isListening
                          ? [Colors.red.shade400, Colors.red.shade600]
                          : [Colors.blue.shade400, Colors.blue.shade600],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_isListening ? Colors.red : Colors.blue).withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Icon(
                      _isListening ? Icons.stop : Icons.mic,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _isListening ? 'Listening...' : 'Tap to speak',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Build real-time transcript overlay
  Widget _buildTranscriptOverlay() {
    return Positioned(
      bottom: 200,
      left: 16,
      right: 16,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.blue.shade700, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You\'re saying:',
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _currentTranscript.isNotEmpty ? _currentTranscript : 'Start speaking...',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Format timestamp for message display
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else {
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    }
  }

  @override
  void dispose() {
    // Cancel all subscriptions
    _cancelSubscriptions();
    
    // Dispose animation controllers
    _waveController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    
    // Dispose service
    _conversationService.dispose();
    
    // Dispose other resources
    _scrollController.dispose();
    _waveformUpdateTimer?.cancel();
    
    AppLogger.info('ChatGPT Level Screen disposed successfully');
    super.dispose();
  }
}

/// Custom painter for real-time waveform visualization
class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final double audioLevel;
  final bool isActive;
  final Animation<double> animation;
  
  WaveformPainter({
    required this.waveformData,
    required this.audioLevel,
    required this.isActive,
    required this.animation,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    final path = Path();
    final width = size.width;
    final height = size.height;
    final centerY = height / 2;
    
    // Draw background wave
    paint.color = Colors.white24;
    _drawWave(canvas, path, size, waveformData.map((e) => e * 0.3).toList(), paint);
    
    if (isActive) {
      // Draw active waveform with animation
      paint.color = Colors.blue.shade400.withOpacity(0.8);
      final animatedData = waveformData.map((e) => 
        e * (0.8 + 0.4 * sin(animation.value * 2 * pi))).toList();
      _drawWave(canvas, Path(), size, animatedData, paint);
      
      // Draw audio level indicator
      paint.color = Colors.red.shade400;
      paint.strokeWidth = 4;
      final levelHeight = audioLevel * height * 0.5;
      canvas.drawLine(
        Offset(width - 10, centerY - levelHeight),
        Offset(width - 10, centerY + levelHeight),
        paint,
      );
    }
  }
  
  void _drawWave(Canvas canvas, Path path, Size size, List<double> data, Paint paint) {
    path.reset();
    final width = size.width;
    final height = size.height;
    final centerY = height / 2;
    
    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * width;
      final y = centerY + (data[i] - 50) * height / 100;
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Data model for conversation messages
class ConversationMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isSystem;
  
  ConversationMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isSystem = false,
  });
}