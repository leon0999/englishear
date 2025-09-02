import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/http_conversation_service.dart';
import '../core/logger.dart';
import 'realtime_conversation_screen.dart';

/// Enterprise-grade ChatGPT-level voice conversation screen V2
/// Google 20년차 수준의 Widget 생명주기 관리 패턴 적용
class ChatGPTLevelScreenV2 extends StatefulWidget {
  const ChatGPTLevelScreenV2({super.key});

  @override
  State<ChatGPTLevelScreenV2> createState() => _ChatGPTLevelScreenV2State();
}

class _ChatGPTLevelScreenV2State extends State<ChatGPTLevelScreenV2> 
    with TickerProviderStateMixin {
  
  // Core Service
  HTTPConversationService? _conversationService;
  
  // Initialization Future
  late Future<void> _initializationFuture;
  
  // Animation Controllers
  late AnimationController _waveController;
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _fadeAnimation;
  
  // UI State
  bool _isListening = false;
  bool _isConnected = false;
  String _currentTranscript = '';
  String _lastCompleteTranscript = '';
  double _audioLevel = 0.0;
  String _selectedMode = ''; // 'realtime' or 'http'
  
  // Message History
  final List<ConversationMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  
  // Stream Subscriptions
  StreamSubscription<String>? _transcriptSubscription;
  StreamSubscription<String>? _responseSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<double>? _audioLevelSubscription;
  
  // Waveform Data
  List<double> _waveformData = List.filled(50, 0.0);
  
  @override
  void initState() {
    super.initState();
    _setupAnimations();
    // Initialize services with FutureBuilder pattern
    _initializationFuture = _performInitialization();
  }
  
  /// Perform all initialization tasks
  Future<void> _performInitialization() async {
    try {
      // Initialize HTTP service first (as fallback)
      _conversationService = HTTPConversationService();
      
      // Small delay to ensure widget tree is ready
      await Future.delayed(Duration.zero);
      
      // Check if user has selected a mode before
      // For now, we'll show selection dialog
      _selectedMode = await _waitForModeSelection();
      
      if (_selectedMode == 'http') {
        await _initializeHTTPService();
      }
      // If 'realtime' is selected, navigation happens in dialog
      
    } catch (e) {
      AppLogger.error('Initialization failed', e);
      throw e; // Let FutureBuilder handle the error
    }
  }
  
  /// Wait for user to select API mode
  Future<String> _waitForModeSelection() async {
    final Completer<String> completer = Completer<String>();
    
    // Schedule dialog after current frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _showAPISelectionDialogWithCallback((String mode) {
          if (!completer.isCompleted) {
            completer.complete(mode);
          }
        });
      }
    });
    
    return completer.future;
  }
  
  /// Show API selection dialog with callback
  void _showAPISelectionDialogWithCallback(Function(String) onModeSelected) {
    if (!mounted) {
      onModeSelected('http'); // Default fallback
      return;
    }
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Choose Connection Mode'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select your preferred API mode:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildModeOption(
              icon: Icons.speed,
              title: 'Realtime API',
              subtitle: 'WebSocket streaming, lowest latency',
              requirements: 'Requires \$5+ credits',
              isRecommended: true,
            ),
            const SizedBox(height: 12),
            _buildModeOption(
              icon: Icons.cloud,
              title: 'HTTP API',
              subtitle: 'Traditional request-response',
              requirements: 'Works with any credit balance',
              isRecommended: false,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onModeSelected('http');
            },
            child: const Text('Use HTTP API'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onModeSelected('realtime');
              // Navigate to Realtime screen
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => const RealtimeConversationScreen(),
                ),
              );
            },
            child: const Text('Use Realtime API'),
          ),
        ],
      ),
    );
  }
  
  /// Build mode option widget
  Widget _buildModeOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required String requirements,
    required bool isRecommended,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(
          color: isRecommended ? Colors.green : Colors.grey,
          width: isRecommended ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 32, color: isRecommended ? Colors.green : Colors.grey),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isRecommended) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'RECOMMENDED',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  requirements,
                  style: TextStyle(
                    color: Colors.orange[700],
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  /// Initialize HTTP service
  Future<void> _initializeHTTPService() async {
    if (_conversationService == null) return;
    
    await _conversationService!.initialize();
    _setupStreamSubscriptions();
    
    if (mounted) {
      setState(() {
        _isConnected = true;
      });
    }
    
    _addSystemMessage('Connected to AI assistant (HTTP Mode). Tap the microphone to start.');
  }
  
  /// Setup animations
  void _setupAnimations() {
    _waveController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );
  }
  
  /// Setup stream subscriptions
  void _setupStreamSubscriptions() {
    if (_conversationService == null) return;
    
    _cancelSubscriptions();
    
    _transcriptSubscription = _conversationService!.transcriptStream.listen(
      (transcript) {
        if (mounted) {
          setState(() {
            _currentTranscript = transcript;
            if (transcript.trim().isNotEmpty) {
              _lastCompleteTranscript = transcript;
              _fadeController.forward();
            }
          });
        }
      },
      onError: (error) => AppLogger.error('Transcript stream error', error),
    );
    
    _responseSubscription = _conversationService!.responseStream.listen(
      (response) {
        if (mounted) {
          _addMessage(ConversationMessage(
            text: response,
            isUser: false,
            timestamp: DateTime.now(),
          ));
        }
      },
      onError: (error) => AppLogger.error('Response stream error', error),
    );
    
    _connectionSubscription = _conversationService!.connectionStatusStream.listen(
      (isConnected) {
        if (mounted) {
          setState(() {
            _isConnected = isConnected;
          });
        }
      },
      onError: (error) => AppLogger.error('Connection stream error', error),
    );
    
    _audioLevelSubscription = _conversationService!.audioLevelStream.listen(
      (level) {
        if (mounted) {
          setState(() {
            _audioLevel = level;
          });
          _updateWaveformData(level);
        }
      },
      onError: (error) => AppLogger.error('Audio level stream error', error),
    );
  }
  
  /// Cancel subscriptions
  void _cancelSubscriptions() {
    _transcriptSubscription?.cancel();
    _responseSubscription?.cancel();
    _connectionSubscription?.cancel();
    _audioLevelSubscription?.cancel();
  }
  
  /// Update waveform data
  void _updateWaveformData(double level) {
    if (mounted) {
      setState(() {
        final newData = List<double>.from(_waveformData);
        newData.removeAt(0);
        newData.add(level * 100);
        _waveformData = newData;
      });
    }
  }
  
  /// Toggle recording
  Future<void> _toggleRecording() async {
    if (_conversationService == null) return;
    
    try {
      HapticFeedback.mediumImpact();
      
      if (!_isListening) {
        setState(() {
          _isListening = true;
        });
        _pulseController.repeat(reverse: true);
        _fadeController.forward();
        await _conversationService!.startRecording();
      } else {
        setState(() {
          _isListening = false;
          _currentTranscript = '';
        });
        _pulseController.stop();
        _pulseController.reset();
        _fadeController.reverse();
        await _conversationService!.stopRecording();
      }
    } catch (e) {
      AppLogger.error('Failed to toggle recording', e);
      if (mounted) {
        _showErrorSnackBar('Recording error: ${e.toString()}');
      }
    }
  }
  
  /// Add message
  void _addMessage(ConversationMessage message) {
    if (mounted) {
      setState(() {
        _messages.add(message);
      });
      
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
  }
  
  /// Add system message
  void _addSystemMessage(String message) {
    _addMessage(ConversationMessage(
      text: message,
      isUser: false,
      timestamp: DateTime.now(),
      isSystem: true,
    ));
  }
  
  /// Show error snackbar
  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    
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
      body: FutureBuilder<void>(
        future: _initializationFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingView();
          }
          
          if (snapshot.hasError) {
            return _buildErrorView(snapshot.error.toString());
          }
          
          return _buildMainUI();
        },
      ),
    );
  }
  
  /// Build loading view
  Widget _buildLoadingView() {
    return Container(
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
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.purple),
            ),
            SizedBox(height: 20),
            Text(
              'Initializing AI Assistant...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// Build error view
  Widget _buildErrorView(String error) {
    return Container(
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
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            const Text(
              'Initialization Failed',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _initializationFuture = _performInitialization();
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              child: const Text(
                'Retry',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// Build main UI
  Widget _buildMainUI() {
    return Container(
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
    );
  }
  
  /// Build header
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          Column(
            children: [
              const Text(
                'AI Conversation',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _selectedMode == 'http' ? 'HTTP Mode' : 'Realtime Mode',
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                ),
              ),
            ],
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
    );
  }
  
  /// Build message list
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
  
  /// Build message bubble
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
              child: Text(
                message.text,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: isSystem ? FontWeight.w400 : FontWeight.w500,
                ),
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
  
  /// Build voice interface
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
          // Microphone button
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
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  /// Build transcript overlay
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
  
  @override
  void dispose() {
    _cancelSubscriptions();
    _waveController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    _conversationService?.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

/// Waveform painter
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
    
    paint.color = Colors.white24;
    _drawWave(canvas, path, size, waveformData.map((e) => e * 0.3).toList(), paint);
    
    if (isActive) {
      paint.color = Colors.blue.shade400.withOpacity(0.8);
      final animatedData = waveformData.map((e) => 
        e * (0.8 + 0.4 * sin(animation.value * 2 * pi))).toList();
      _drawWave(canvas, Path(), size, animatedData, paint);
      
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

/// Conversation message model
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