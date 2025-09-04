import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/openai_realtime_websocket.dart';
import '../services/enhanced_audio_streaming_service.dart';
import '../services/conversation_improver_service.dart';
import '../core/logger.dart';

/// Auto Conversation Screen - Automatically starts microphone
/// No buttons needed - just pure conversation
class AutoConversationScreen extends StatefulWidget {
  const AutoConversationScreen({super.key});

  @override
  State<AutoConversationScreen> createState() => _AutoConversationScreenState();
}

class _AutoConversationScreenState extends State<AutoConversationScreen>
    with TickerProviderStateMixin {
  
  // Core Services
  late final OpenAIRealtimeWebSocket _websocket;
  late final EnhancedAudioStreamingService _audioService;
  late final ConversationImproverService _improverService;
  
  // Animation Controllers
  late AnimationController _pulseController;
  late AnimationController _breathingController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _breathingAnimation;
  
  // UI State
  bool _isConnected = false;
  bool _isInitializing = true;
  bool _permissionGranted = false;
  double _audioLevel = 0.0;
  ConversationState? _conversationState;
  bool _hasConversationHistory = false;
  bool _isProcessingUpgrade = false;
  
  // Stream Subscriptions
  final List<StreamSubscription> _subscriptions = [];
  
  // Waveform visualization
  final List<double> _waveformData = List.filled(50, 0.0);
  Timer? _waveformTimer;
  
  @override
  void initState() {
    super.initState();
    _initializeServices();
    _setupAnimations();
    
    // Auto-start after frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermissionAndStart();
    });
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
            if (!isConnected) {
              _reconnect();
            }
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
    // Continuous pulse for active listening
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    
    // Breathing animation for idle state
    _breathingController = AnimationController(
      duration: const Duration(seconds: 4),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.3,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
    
    _breathingAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _breathingController,
      curve: Curves.easeInOut,
    ));
    
    // Update waveform periodically
    _waveformTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _animateWaveform();
    });
  }
  
  Future<void> _requestPermissionAndStart() async {
    setState(() {
      _isInitializing = true;
    });
    
    try {
      // Request microphone permission
      final status = await Permission.microphone.request();
      
      if (status.isGranted) {
        setState(() {
          _permissionGranted = true;
        });
        
        // Connect to WebSocket
        await _websocket.connect();
        
        // Initialize and auto-start audio service
        await _audioService.initialize();
        
        setState(() {
          _isInitializing = false;
        });
        
        AppLogger.info('Auto-started conversation mode');
      } else {
        setState(() {
          _permissionGranted = false;
          _isInitializing = false;
        });
        
        _showError('Microphone permission is required for conversation');
      }
    } catch (e) {
      AppLogger.error('Failed to initialize', e);
      setState(() {
        _isInitializing = false;
      });
      _showError('Failed to start conversation: ${e.toString()}');
    }
  }
  
  Future<void> _reconnect() async {
    await Future.delayed(const Duration(seconds: 3));
    if (!_isConnected && mounted) {
      try {
        await _websocket.connect();
        await _audioService.initialize();
      } catch (e) {
        AppLogger.error('Reconnection failed', e);
      }
    }
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
      // Add natural variation
      for (int i = 0; i < _waveformData.length; i++) {
        if (_conversationState?.isUserSpeaking ?? false) {
          _waveformData[i] = (_waveformData[i] + (math.Random().nextDouble() * 0.15 - 0.075))
              .clamp(0.0, 1.0);
        } else if (_conversationState?.isAiResponding ?? false) {
          _waveformData[i] = (_waveformData[i] + (math.Random().nextDouble() * 0.1 - 0.05))
              .clamp(0.0, 1.0);
        } else {
          _waveformData[i] *= 0.92; // Gradual decay
        }
      }
    });
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
      
      // Show improvements
      if (mounted) {
        await _showImprovements(improved);
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
  
  Future<void> _showImprovements(ImprovedConversation improved) async {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Conversation Improved',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            ...improved.improvements.take(3).map((suggestion) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Text(
                suggestion.explanation,
                style: const TextStyle(color: Colors.green),
              ),
            )),
          ],
        ),
      ),
    );
  }
  
  void _showError(String message) {
    if (!mounted) return;
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
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // Background gradient
            Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Colors.blue.withOpacity(0.05),
                    Colors.black,
                  ],
                  radius: 1.5,
                ),
              ),
            ),
            
            // Main content
            if (_isInitializing) 
              _buildInitializingView()
            else if (!_permissionGranted)
              _buildPermissionDeniedView()
            else
              _buildConversationView(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInitializingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Colors.blue),
          const SizedBox(height: 20),
          Text(
            'Initializing conversation...',
            style: TextStyle(color: Colors.white.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }
  
  Widget _buildPermissionDeniedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.mic_off,
            size: 60,
            color: Colors.red.withOpacity(0.7),
          ),
          const SizedBox(height: 20),
          const Text(
            'Microphone Permission Required',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 10),
          Text(
            'Please grant microphone access to start',
            style: TextStyle(color: Colors.white.withOpacity(0.5)),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () => openAppSettings(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildConversationView() {
    return Column(
      children: [
        // Connection indicator
        _buildConnectionIndicator(),
        
        // Main visualization
        Expanded(
          child: Center(
            child: _buildAudioVisualizer(),
          ),
        ),
        
        // Status text
        _buildStatusText(),
        
        // Upgrade Replay button
        if (_hasConversationHistory)
          _buildUpgradeReplayButton(),
        
        const SizedBox(height: 30),
      ],
    );
  }
  
  Widget _buildConnectionIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isConnected ? Colors.green : Colors.red,
              boxShadow: [
                BoxShadow(
                  color: (_isConnected ? Colors.green : Colors.red).withOpacity(0.8),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _isConnected ? 'Connected' : 'Connecting...',
            style: TextStyle(
              color: (_isConnected ? Colors.green : Colors.red).withOpacity(0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAudioVisualizer() {
    final isActive = _conversationState?.isUserSpeaking ?? false || 
                     _conversationState?.isAiResponding ?? false;
    
    return AnimatedBuilder(
      animation: isActive ? _pulseAnimation : _breathingAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: isActive ? _pulseAnimation.value : _breathingAnimation.value,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  (_conversationState?.isUserSpeaking ?? false)
                      ? Colors.blue.withOpacity(0.4)
                      : (_conversationState?.isAiResponding ?? false)
                          ? Colors.purple.withOpacity(0.4)
                          : Colors.white.withOpacity(0.1),
                  Colors.transparent,
                ],
              ),
            ),
            child: CustomPaint(
              painter: CircularWaveformPainter(
                waveformData: _waveformData,
                color: (_conversationState?.isUserSpeaking ?? false)
                    ? Colors.blue
                    : (_conversationState?.isAiResponding ?? false)
                        ? Colors.purple
                        : Colors.white24,
              ),
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildStatusText() {
    String status = 'Ready';
    Color color = Colors.white38;
    IconData icon = Icons.hearing;
    
    if (_conversationState?.isUserSpeaking ?? false) {
      status = 'Listening...';
      color = Colors.blue;
      icon = Icons.mic;
    } else if (_conversationState?.isAiResponding ?? false) {
      status = 'AI Speaking...';
      color = Colors.purple;
      icon = Icons.volume_up;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            status,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildUpgradeReplayButton() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isProcessingUpgrade ? null : _upgradeReplay,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: LinearGradient(
                colors: [
                  Colors.purple.withOpacity(0.3),
                  Colors.deepPurple.withOpacity(0.3),
                ],
              ),
              border: Border.all(
                color: Colors.purple.withOpacity(0.5),
                width: 1,
              ),
            ),
            child: _isProcessingUpgrade
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_fix_high,
                        color: Colors.white.withOpacity(0.9),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Upgrade Replay',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _waveformTimer?.cancel();
    _pulseController.dispose();
    _breathingController.dispose();
    
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    
    _audioService.dispose();
    _websocket.disconnect();
    _improverService.dispose();
    
    super.dispose();
  }
}

/// Circular waveform painter
class CircularWaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final Color color;
  
  CircularWaveformPainter({
    required this.waveformData,
    required this.color,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.6)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 3;
    
    for (int i = 0; i < waveformData.length; i++) {
      final angle = (i / waveformData.length) * 2 * math.pi;
      final amplitude = radius + (waveformData[i] * 40);
      
      final start = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      
      final end = Offset(
        center.dx + math.cos(angle) * amplitude,
        center.dy + math.sin(angle) * amplitude,
      );
      
      // Fade effect for older data
      paint.color = color.withOpacity(0.6 * (1 - i / waveformData.length));
      canvas.drawLine(start, end, paint);
    }
  }
  
  @override
  bool shouldRepaint(CircularWaveformPainter oldDelegate) {
    return true;
  }
}