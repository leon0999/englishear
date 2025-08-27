// lib/screens/voice_conversation_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/voice_conversation_service.dart';
import '../services/upgrade_replay_service.dart';
import '../services/subscription_service.dart';
import 'upgrade_replay_screen.dart';

class VoiceConversationScreen extends StatefulWidget {
  const VoiceConversationScreen({Key? key}) : super(key: key);

  @override
  _VoiceConversationScreenState createState() => _VoiceConversationScreenState();
}

class _VoiceConversationScreenState extends State<VoiceConversationScreen> 
    with TickerProviderStateMixin {
  final VoiceConversationService _conversationService = VoiceConversationService();
  late AnimationController _pulseController;
  late AnimationController _waveController;
  
  bool _isConversationActive = false;
  bool _isListening = false;
  bool _canUpgradeReplay = false;
  String _currentAIText = '';
  String _currentUserText = '';
  String _conversationStatus = 'Ready to start';
  
  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    
    _setupConversationCallbacks();
  }
  
  void _setupConversationCallbacks() {
    _conversationService.onAISpeaking = (text) {
      setState(() {
        _currentAIText = text;
        _conversationStatus = 'AI is speaking...';
      });
    };
    
    _conversationService.onUserSpeaking = (text) {
      setState(() {
        _currentUserText = text;
        _conversationStatus = 'Processing your response...';
      });
    };
    
    _conversationService.onListeningStateChanged = (isListening) {
      setState(() {
        _isListening = isListening;
        _conversationStatus = isListening ? 'Listening...' : 'Processing...';
      });
    };
    
    _conversationService.onConversationEnd = () {
      setState(() {
        _canUpgradeReplay = true;
        _conversationStatus = 'Conversation complete! Ready for Upgrade Replay.';
      });
    };
    
    _conversationService.onError = (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    };
  }
  
  Future<void> _startConversation() async {
    setState(() {
      _isConversationActive = true;
      _canUpgradeReplay = false;
      _currentAIText = '';
      _currentUserText = '';
      _conversationStatus = 'Starting conversation...';
    });
    
    await _conversationService.startConversation();
  }
  
  Future<void> _handleUpgradeReplay() async {
    final subscriptionService = Provider.of<SubscriptionService>(context, listen: false);
    
    // 사용량 체크
    if (!subscriptionService.canUseReplay) {
      _showUpgradeDialog();
      return;
    }
    
    // 사용량 기록
    final recorded = await subscriptionService.recordReplayUsage();
    if (!recorded) {
      _showUpgradeDialog();
      return;
    }
    
    // Upgrade Replay 화면으로 이동
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UpgradeReplayScreen(
          conversation: _conversationService.getConversationHistory(),
        ),
      ),
    );
  }
  
  void _showUpgradeDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Daily Limit Reached',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'You\'ve used all your free Upgrade Replays for today.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.purple.shade400, Colors.blue.shade400],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: const [
                  Text(
                    'Upgrade to Pro',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '₩9,900/month',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• 30 Upgrade Replays per day\n• Priority AI responses\n• Advanced analytics',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Maybe Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _purchasePro();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
            ),
            child: const Text('Upgrade Now'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _purchasePro() async {
    final subscriptionService = Provider.of<SubscriptionService>(context, listen: false);
    await subscriptionService.purchaseProSubscription();
  }
  
  @override
  Widget build(BuildContext context) {
    return Consumer<SubscriptionService>(
      builder: (context, subscriptionService, child) {
        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: SafeArea(
            child: Column(
              children: [
                // Header with usage info
                _buildHeader(subscriptionService),
                
                // Main content
                Expanded(
                  child: Center(
                    child: _buildMainContent(),
                  ),
                ),
                
                // Bottom controls
                _buildBottomControls(subscriptionService),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildHeader(SubscriptionService subscriptionService) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                subscriptionService.isPro ? 'Pro Member' : 'Free Plan',
                style: TextStyle(
                  color: subscriptionService.isPro ? Colors.amber : Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Replays: ${subscriptionService.remainingReplays}/${subscriptionService.dailyLimit}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (!subscriptionService.isPro)
            ElevatedButton(
              onPressed: _purchasePro,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              child: const Text('Upgrade'),
            ),
        ],
      ),
    );
  }
  
  Widget _buildMainContent() {
    if (!_isConversationActive) {
      return _buildStartButton();
    }
    
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Conversation status
        Text(
          _conversationStatus,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 14,
          ),
        ).animate().fade(duration: 500.ms),
        
        const SizedBox(height: 30),
        
        // Visual indicator
        _buildVisualIndicator(),
        
        const SizedBox(height: 40),
        
        // Current text display
        if (_currentAIText.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 30),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Text(
              _currentAIText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ).animate().slideY(begin: 0.2, duration: 300.ms).fade(),
        
        if (_currentUserText.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 30),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Text(
              _currentUserText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
          ).animate().slideY(begin: -0.2, duration: 300.ms).fade(),
        ],
      ],
    );
  }
  
  Widget _buildStartButton() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'Ready to practice English?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Tap to start a conversation',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 50),
        GestureDetector(
          onTap: _startConversation,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.blue.shade400,
                  Colors.purple.shade400,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.5),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: const Icon(
              Icons.mic,
              size: 70,
              color: Colors.white,
            ),
          ).animate(
            controller: _pulseController,
            onPlay: (controller) => controller.repeat(),
          ).scale(
            begin: const Offset(1.0, 1.0),
            end: const Offset(1.1, 1.1),
            curve: Curves.easeInOut,
          ),
        ),
      ],
    );
  }
  
  Widget _buildVisualIndicator() {
    if (_isListening) {
      return Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.red.withOpacity(0.1),
          border: Border.all(
            color: Colors.red,
            width: 2,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.mic,
              size: 50,
              color: Colors.red,
            ),
            ...List.generate(3, (index) {
              return Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.red.withOpacity(0.3),
                    width: 1,
                  ),
                ),
              ).animate(
                controller: _waveController,
                onPlay: (controller) => controller.repeat(),
              ).scale(
                begin: const Offset(1.0, 1.0),
                end: const Offset(1.5, 1.5),
                delay: Duration(milliseconds: index * 200),
              ).fade(
                begin: 0.5,
                end: 0.0,
                delay: Duration(milliseconds: index * 200),
              );
            }),
          ],
        ),
      );
    } else {
      return Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Colors.blue.shade400, Colors.purple.shade400],
          ),
        ),
        child: const Icon(
          Icons.psychology,
          size: 60,
          color: Colors.white,
        ),
      ).animate(
        onPlay: (controller) => controller.repeat(),
      ).rotate(
        duration: const Duration(seconds: 3),
      );
    }
  }
  
  Widget _buildBottomControls(SubscriptionService subscriptionService) {
    if (!_canUpgradeReplay) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          ElevatedButton(
            onPressed: _handleUpgradeReplay,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.replay),
                const SizedBox(width: 10),
                Text(
                  'Upgrade Replay (${subscriptionService.remainingReplays} left)',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ).animate().slideY(begin: 1, duration: 500.ms).fade(),
          
          const SizedBox(height: 10),
          
          TextButton(
            onPressed: () {
              setState(() {
                _isConversationActive = false;
                _canUpgradeReplay = false;
              });
            },
            child: const Text(
              'Start New Conversation',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    super.dispose();
  }
}