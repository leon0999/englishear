import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/openai_realtime_websocket.dart';
import '../services/enhanced_audio_streaming_service.dart';
import '../services/conversation_improver_service.dart';
import '../core/logger.dart';

/// Simplified Conversation Screen
/// Clean UI with audio visualization and Upgrade Replay
class SimplifiedConversationScreen extends StatefulWidget {
  const SimplifiedConversationScreen({super.key});

  @override
  State<SimplifiedConversationScreen> createState() => _SimplifiedConversationScreenState();
}

class _SimplifiedConversationScreenState extends State<SimplifiedConversationScreen>
    with TickerProviderStateMixin {
  
  // Core Services
  late final OpenAIRealtimeWebSocket _websocket;
  late final EnhancedAudioStreamingService _audioService;
  late final ConversationImproverService _improverService;
  
  // Animation Controllers
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late Animation<double> _pulseAnimation;
  
  // UI State
  bool _isConnected = false;
  bool _isConnecting = false;
  double _audioLevel = 0.0;
  ConversationState? _conversationState;
  bool _hasConversationHistory = false;
  bool _isProcessingUpgrade = false;
  
  // Stream Subscriptions
  final List<StreamSubscription> _subscriptions = [];
  
  // Waveform visualization
  final List<double> _waveformData = List.filled(30, 0.0);
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
    _audioService = EnhancedAudioStreamingService(_websocket);
    _improverService = ConversationImproverService();
    
    // Listen to connection status
    _subscriptions.add(
      _websocket.connectionStatusStream.listen((isConnected) {
        if (mounted) {
          setState(() {
            _isConnected = isConnected;
            _isConnecting = false;
          });
        }
      }),
    );
    
    // Listen to audio level changes
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
    
    // Listen to conversation state
    _subscriptions.add(
      _audioService.conversationStateStream.listen((state) {
        if (mounted) {
          setState(() {
            _conversationState = state;
            _hasConversationHistory = _audioService.getConversationHistory().isNotEmpty;
          });
        }
      }),
    );
  }
  
  void _setupAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    // Update waveform periodically
    _waveformTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _animateWaveform();
    });
  }
  
  void _updateWaveform(double level) {
    // Shift waveform data
    for (int i = _waveformData.length - 1; i > 0; i--) {
      _waveformData[i] = _waveformData[i - 1];
    }
    _waveformData[0] = level;
  }
  
  void _animateWaveform() {
    if (!mounted) return;
    setState(() {
      // Add subtle random variation for visual interest
      for (int i = 0; i < _waveformData.length; i++) {
        if (_conversationState?.isUserSpeaking ?? false) {
          _waveformData[i] = (_waveformData[i] + (math.Random().nextDouble() * 0.1 - 0.05))
              .clamp(0.0, 1.0);
        } else if (_conversationState?.isAiResponding ?? false) {
          _waveformData[i] = (_waveformData[i] + (math.Random().nextDouble() * 0.05 - 0.025))
              .clamp(0.0, 1.0);
        } else {
          _waveformData[i] *= 0.95; // Decay when not speaking
        }
      }
    });
  }
  
  Future<void> _connectToRealtimeAPI() async {
    setState(() {
      _isConnecting = true;
    });
    
    try {
      await _websocket.connect();
      AppLogger.info('Connected to Realtime API');
    } catch (e) {
      AppLogger.error('Failed to connect', e);
      if (mounted) {
        _showError('Connection failed. Please check your internet connection.');
      }
    }
  }
  
  Future<void> _toggleRecording() async {
    HapticFeedback.lightImpact();
    
    try {
      await _audioService.toggleRecording();
    } catch (e) {
      AppLogger.error('Failed to toggle recording', e);
      _showError('Failed to access microphone');
    }
  }
  
  Future<void> _upgradeReplay() async {
    final history = _audioService.getConversationHistory();
    
    if (history.isEmpty) {
      _showError('No conversation to improve');
      return;
    }
    
    setState(() {
      _isProcessingUpgrade = true;
    });
    
    try {
      final improved = await _improverService.upgradeReplay(history);
      
      // Show improvement dialog
      if (mounted) {
        await _showImprovementDialog(improved);
      }
      
      // Play improved conversation
      await _improverService.playImprovedConversation(improved);
      
    } catch (e) {
      AppLogger.error('Failed to upgrade replay', e);
      _showError('Failed to improve conversation');
    } finally {
      setState(() {
        _isProcessingUpgrade = false;
      });
    }
  }
  
  Future<void> _showImprovementDialog(ImprovedConversation improved) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Conversation Improved',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${improved.improvements.length} improvements made',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            ...improved.improvements.take(3).map((suggestion) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '• ${suggestion.explanation}',
                    style: const TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ],
              ),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Play Improved'),
          ),
        ],
      ),
    );
  }
  
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
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
            // Minimal header
            _buildHeader(),
            
            // Main content
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Audio visualization
                    _buildAudioVisualizer(),
                    
                    const SizedBox(height: 60),
                    
                    // Control buttons
                    _buildControls(),
                    
                    const SizedBox(height: 40),
                    
                    // Upgrade Replay button
                    if (_hasConversationHistory && !_isProcessingUpgrade)
                      _buildUpgradeReplayButton(),
                  ],
                ),
              ),
            ),
            
            // Status indicator
            _buildStatusIndicator(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white54),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _isConnected ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: _isConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 6),
                Text(
                  _isConnected ? 'Connected' : 'Disconnected',
                  style: TextStyle(
                    color: _isConnected ? Colors.green : Colors.red,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAudioVisualizer() {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: (_conversationState?.isUserSpeaking ?? false) ? _pulseAnimation.value : 1.0,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  (_conversationState?.isUserSpeaking ?? false)
                      ? Colors.blue.withOpacity(0.3)
                      : (_conversationState?.isAiResponding ?? false)
                          ? Colors.purple.withOpacity(0.3)
                          : Colors.white.withOpacity(0.1),
                  Colors.transparent,
                ],
              ),
            ),
            child: CustomPaint(
              painter: WaveformPainter(
                waveformData: _waveformData,
                color: (_conversationState?.isUserSpeaking ?? false)
                    ? Colors.blue
                    : (_conversationState?.isAiResponding ?? false)
                        ? Colors.purple
                        : Colors.white54,
              ),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildControls() {
    final isRecording = _conversationState?.isRecording ?? false;
    
    return GestureDetector(
      onTapDown: (_) => _toggleRecording(),
      onTapUp: (_) => _toggleRecording(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isRecording ? Colors.red : Colors.blue,
          boxShadow: [
            BoxShadow(
              color: (isRecording ? Colors.red : Colors.blue).withOpacity(0.5),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          isRecording ? Icons.mic : Icons.mic_none,
          color: Colors.white,
          size: 36,
        ),
      ),
    );
  }
  
  Widget _buildUpgradeReplayButton() {
    return AnimatedOpacity(
      opacity: _hasConversationHistory ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          gradient: const LinearGradient(
            colors: [Colors.purple, Colors.deepPurple],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isProcessingUpgrade ? null : _upgradeReplay,
            borderRadius: BorderRadius.circular(25),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: _isProcessingUpgrade
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_fix_high, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Upgrade Replay',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildStatusIndicator() {
    String status = 'Ready';
    Color color = Colors.white54;
    
    if (_conversationState?.isUserSpeaking ?? false) {
      status = 'Listening...';
      color = Colors.blue;
    } else if (_conversationState?.isAiResponding ?? false) {
      status = 'AI Speaking...';
      color = Colors.purple;
    }
    
    return Container(
      padding: const EdgeInsets.all(16),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 14,
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _waveformTimer?.cancel();
    _pulseController.dispose();
    _waveController.dispose();
    
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    
    _audioService.dispose();
    _websocket.disconnect();
    _improverService.dispose();
    
    super.dispose();
  }
}

/// Custom painter for waveform visualization
class WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final Color color;
  
  WaveformPainter({
    required this.waveformData,
    required this.color,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.6)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 3;
    
    for (int i = 0; i < waveformData.length; i++) {
      final angle = (i / waveformData.length) * 2 * math.pi;
      final amplitude = radius + (waveformData[i] * 30);
      
      final start = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      
      final end = Offset(
        center.dx + math.cos(angle) * amplitude,
        center.dy + math.sin(angle) * amplitude,
      );
      
      canvas.drawLine(start, end, paint);
    }
  }
  
  @override
  bool shouldRepaint(WaveformPainter oldDelegate) {
    return true;
  }
}