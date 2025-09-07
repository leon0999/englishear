import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_session/audio_session.dart';
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  
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
  String _jupiterTranscript = '';  // Jupiter AI transcript
  String _speakingState = 'idle';  // 'user', 'ai', 'idle'
  
  // Stream Subscriptions
  final List<StreamSubscription> _subscriptions = [];
  
  // Waveform visualization
  final List<double> _waveformData = List.filled(50, 0.0);
  Timer? _waveformTimer;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);  // Add lifecycle observer
    _setupAnimations();
    
    // Immediately check and initialize
    _checkAndInitialize();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.resumed:
        AppLogger.info('📱 App resumed, reinitializing services...');
        await _handleAppResume();
        break;
        
      case AppLifecycleState.paused:
        AppLogger.info('⏸️ App paused - resetting states');
        _handleAppPause();
        break;
        
      case AppLifecycleState.inactive:
        AppLogger.debug('App inactive');
        break;
        
      case AppLifecycleState.detached:
        AppLogger.debug('App detached');
        break;
        
      case AppLifecycleState.hidden:
        AppLogger.debug('App hidden');
        break;
    }
  }
  
  Future<void> _handleAppResume() async {
    AppLogger.test('==================== APP RESUME START ====================');
    
    // 1. 오디오 세션 재활성화
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
      AppLogger.success('Audio session reactivated');
    } catch (e) {
      AppLogger.error('Failed to reactivate audio session', e);
    }
    
    // 2. 모든 상태 강제 리셋
    AppLogger.test('🔄 Force resetting all states...');
    
    // Audio service 상태 리셋
    _audioService.resetSpeakingState();
    AppLogger.test('✅ Audio service speaking state reset');
    
    // WebSocket 응답 상태 리셋
    _websocket.resetResponseState();
    AppLogger.test('✅ WebSocket response state reset');
    
    // 오디오 버퍼 클리어
    try {
      _websocket.sendEvent({
        'type': 'input_audio_buffer.clear'
      });
      AppLogger.test('✅ Audio buffer clear requested');
    } catch (e) {
      AppLogger.warning('Could not clear audio buffer: $e');
    }
    
    // 3. WebSocket 연결 상태 확인 및 재연결
    if (!_websocket.isConnected) {
      AppLogger.info('🔄 WebSocket disconnected - reconnecting...');
      _websocket.disconnect();  // void 반환이므로 await 제거
      await Future.delayed(const Duration(milliseconds: 500));
      await _initializeAndStart();
    } else {
      AppLogger.success('WebSocket still connected');
      
      // 연결은 되어 있지만 상태만 리셋
      AppLogger.test('🎯 WebSocket connected - resetting audio service state only');
      await _audioService.reinitialize();
    }
    
    // 4. 마이크 권한 재확인
    _checkPermissionAfterSettings();
    
    AppLogger.test('==================== APP RESUME COMPLETE ====================');
  }
  
  void _handleAppPause() {
    AppLogger.test('==================== APP PAUSE START ====================');
    
    // 1. 오디오 녹음 중지
    if (_audioService != null) {
      _audioService.stopListening();
      AppLogger.test('🛑 Audio recording stopped');
      
      // 사용자 말하기 상태 리셋
      _audioService.resetSpeakingState();
      AppLogger.test('✅ Speaking state reset');
    }
    
    // 2. WebSocket 상태 리셋
    if (_websocket != null) {
      _websocket.resetResponseState();
      AppLogger.test('✅ WebSocket response state reset');
      
      // 오디오 버퍼 클리어
      _websocket.sendEvent({
        'type': 'input_audio_buffer.clear'
      });
      AppLogger.test('✅ Audio buffer clear requested on pause');
    }
    
    // 3. 대화 상태 업데이트
    setState(() {
      _conversationState = null;  // Reset to null (idle state)
    });
    AppLogger.test('✅ Conversation state reset to idle');
    
    AppLogger.test('==================== APP PAUSE COMPLETE ====================');
  }
  
  Future<void> _checkPermissionAfterSettings() async {
    // Wait a bit for the system to update permission status
    await Future.delayed(const Duration(milliseconds: 500));
    
    final status = await Permission.microphone.status;
    AppLogger.info('🎤 Permission status after settings: $status');
    
    if (status.isGranted && !_isConnected) {
      setState(() {
        _permissionGranted = true;
      });
      await _initializeAndStart();
    } else if (status.isPermanentlyDenied) {
      setState(() {
        _permissionGranted = false;
        _isInitializing = false;
      });
    }
  }
  
  Future<void> _checkAndInitialize() async {
    AppLogger.info('🔄 Checking permissions and initializing...');
    
    // Check current permission status
    final status = await Permission.microphone.status;
    AppLogger.info('🎤 Current permission status: $status');
    
    if (status.isGranted) {
      // Permission granted, initialize services
      AppLogger.info('✅ Permission granted, initializing services...');
      await _initializeServices();
    } else if (status.isDenied) {
      // Request permission
      final result = await Permission.microphone.request();
      AppLogger.info('📱 Permission request result: $result');
      
      if (result.isGranted) {
        await _initializeServices();
      } else {
        setState(() {
          _permissionGranted = false;
          _isInitializing = false;
        });
        _showPermissionDeniedDialog();
      }
    } else if (status.isPermanentlyDenied) {
      setState(() {
        _permissionGranted = false;
        _isInitializing = false;
      });
      _showPermissionDeniedDialog();
    }
  }
  
  Future<void> _initializeServices() async {
    AppLogger.info('🚀 Starting service initialization...');
    
    setState(() {
      _isInitializing = true;
      _permissionGranted = true;
    });
    
    try {
      // Initialize services
      _websocket = OpenAIRealtimeWebSocket();
      _audioService = EnhancedAudioStreamingService(_websocket);
      _improverService = ConversationImproverService();
      
      AppLogger.info('✅ Services created');
      
      // Set up Jupiter AI callbacks
      _websocket.onAiTranscriptUpdate = (transcript) {
        if (mounted) {
          setState(() {
            _jupiterTranscript = transcript;
          });
        }
      };
      
      _websocket.onSpeakingStateChange = (state) {
        if (mounted) {
          setState(() {
            _speakingState = state;
          });
        }
      };
      
      // Listen to connection status
      _subscriptions.add(
        _websocket.connectionStatusStream.listen((isConnected) {
          AppLogger.info('🔌 Connection status changed: $isConnected');
          if (mounted) {
            setState(() {
              _isConnected = isConnected;
              if (isConnected) {
                // Start Jupiter greeting after connection
                _startJupiterGreeting();
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
      
      // Connect to WebSocket
      AppLogger.info('🔗 Connecting to OpenAI Realtime API...');
      await _websocket.connect();
      
      // Initialize audio service
      AppLogger.info('🎤 Initializing audio service...');
      await _audioService.initialize();
      
      setState(() {
        _isInitializing = false;
      });
      
      AppLogger.info('✅ All services initialized successfully');
      
    } catch (e) {
      AppLogger.error('❌ Error initializing services', e);
      setState(() {
        _isInitializing = false;
      });
      
      // Show error and retry
      _showError('Connection failed: ${e.toString()}');
      
      // Retry after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          _checkAndInitialize();
        }
      });
    }
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
      
      AppLogger.info('✅ Permission request result: $status');
      
      if (status.isGranted) {
        await _initializeAndStart();
      } else if (status.isPermanentlyDenied) {
        setState(() {
          _permissionGranted = false;
          _isInitializing = false;
        });
        _showPermissionDeniedDialog();
      } else {
        setState(() {
          _permissionGranted = false;
          _isInitializing = false;
        });
        _showError('Microphone permission is required for conversation');
      }
    } catch (e) {
      AppLogger.error('❌ Failed to request permission', e);
      setState(() {
        _isInitializing = false;
      });
      
      // Try to initialize anyway if permission might already be granted
      final status = await Permission.microphone.status;
      if (status.isGranted) {
        await _initializeAndStart();
      }
    }
  }
  
  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Microphone Permission Required',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'EnglishEar needs microphone access to practice English conversation. '
          'Please enable microphone permission in Settings.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await openAppSettings();
            },
            child: const Text(
              'Open Settings',
              style: TextStyle(color: Colors.blue),
            ),
          ),
        ],
      ),
    );
  }
  
  void _startJupiterGreeting() {
    Future.delayed(const Duration(seconds: 2), () {
      if (_isConnected) {
        AppLogger.info('🤖 Jupiter starting conversation...');
        
        // Start conversation with greeting
        _websocket.sendEvent({
          'type': 'conversation.item.create',
          'item': {
            'type': 'message',
            'role': 'user',
            'content': [{
              'type': 'input_text',
              'text': 'Start the conversation by saying hello and asking how I am doing today.'
            }]
          }
        });
        
        // Request response
        _websocket.sendEvent({
          'type': 'response.create'
        });
      }
    });
  }
  
  Future<void> _initializeAndStart() async {
    // This method now redirects to the new _initializeServices
    await _initializeServices();
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
        
        // Jupiter name and status
        _buildJupiterHeader(),
        
        // Main visualization
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              _buildAudioVisualizer(),
              // Jupiter transcript overlay
              if (_jupiterTranscript.isNotEmpty && _speakingState == 'ai')
                _buildJupiterTranscript(),
            ],
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
    final isActive = (_conversationState?.isUserSpeaking == true) || 
                     (_conversationState?.isAiResponding == true);
    
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
    
    if (_speakingState == 'user' || (_conversationState?.isUserSpeaking ?? false)) {
      status = 'Listening...';
      color = Colors.blue;
      icon = Icons.mic;
    } else if (_speakingState == 'ai' || (_conversationState?.isAiResponding ?? false)) {
      status = 'Jupiter is speaking...';
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
  
  Widget _buildJupiterHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Jupiter icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  Colors.purple.shade400,
                  Colors.deepPurple.shade600,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.purple.withOpacity(0.3),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(
              Icons.psychology,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Jupiter AI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                _speakingState == 'ai' ? 'Speaking...' : 'Your English Partner',
                style: TextStyle(
                  color: _speakingState == 'ai' 
                    ? Colors.purple.shade300 
                    : Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildJupiterTranscript() {
    return Positioned(
      bottom: 100,
      left: 20,
      right: 20,
      child: AnimatedOpacity(
        opacity: _jupiterTranscript.isNotEmpty ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: Colors.purple.withOpacity(0.3),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.purple.withOpacity(0.1),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.psychology,
                    color: Colors.purple.shade300,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Jupiter',
                    style: TextStyle(
                      color: Colors.purple.shade300,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _jupiterTranscript,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
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
    WidgetsBinding.instance.removeObserver(this);  // Remove lifecycle observer
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