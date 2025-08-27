// lib/screens/enhanced_conversation_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lottie/lottie.dart';
import '../services/voice_conversation_service.dart';
import '../services/upgrade_replay_service.dart';
import '../services/enhanced_subscription_service.dart';
import '../services/audio_playback_service.dart';
import 'upgrade_replay_screen.dart';

class EnhancedConversationScreen extends StatefulWidget {
  const EnhancedConversationScreen({Key? key}) : super(key: key);

  @override
  _EnhancedConversationScreenState createState() => _EnhancedConversationScreenState();
}

class _EnhancedConversationScreenState extends State<EnhancedConversationScreen> 
    with TickerProviderStateMixin {
  
  // Services
  final VoiceConversationService _conversationService = VoiceConversationService();
  final AudioPlaybackService _audioService = AudioPlaybackService();
  late AnimationController _pulseController;
  late AnimationController _waveController;
  late AnimationController _breathingController;
  
  // State
  bool _isConversationActive = false;
  bool _isListening = false;
  bool _canUpgradeReplay = false;
  bool _isProcessing = false;
  String _currentStatus = 'Ready to practice';
  String _currentSpeaker = '';
  String _displayText = '';
  int _conversationTurns = 0;
  
  // UI State
  double _microphoneScale = 1.0;
  Color _statusColor = Colors.white54;
  
  @override
  void initState() {
    super.initState();
    
    // Animation controllers
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    
    _waveController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    
    _breathingController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    
    _setupConversationCallbacks();
  }
  
  void _setupConversationCallbacks() {
    _conversationService.onAISpeaking = (text) {
      setState(() {
        _currentSpeaker = 'AI';
        _displayText = text;
        _currentStatus = 'AI is speaking...';
        _statusColor = Colors.blue;
      });
    };
    
    _conversationService.onUserSpeaking = (text) {
      setState(() {
        _currentSpeaker = 'You';
        _displayText = text;
        _currentStatus = 'Great job! Processing...';
        _statusColor = Colors.green;
        _conversationTurns++;
      });
    };
    
    _conversationService.onListeningStateChanged = (isListening) {
      setState(() {
        _isListening = isListening;
        _currentStatus = isListening ? 'Listening... Speak now!' : 'Processing...';
        _statusColor = isListening ? Colors.red : Colors.orange;
        _microphoneScale = isListening ? 1.2 : 1.0;
      });
    };
    
    _conversationService.onConversationEnd = () {
      setState(() {
        _canUpgradeReplay = true;
        _currentStatus = 'Excellent! Ready for Upgrade Replay ✨';
        _statusColor = Colors.purple;
      });
    };
    
    _conversationService.onError = (error) {
      _showErrorSnackBar(error);
    };
  }
  
  Future<void> _startConversation() async {
    setState(() {
      _isConversationActive = true;
      _canUpgradeReplay = false;
      _displayText = '';
      _conversationTurns = 0;
      _currentStatus = 'Starting conversation...';
      _statusColor = Colors.blue;
    });
    
    await _conversationService.startConversation();
  }
  
  Future<void> _handleUpgradeReplay() async {
    final subscriptionService = Provider.of<EnhancedSubscriptionService>(context, listen: false);
    
    // Check daily limit
    if (!await subscriptionService.useUpgradeReplay()) {
      _showUpgradeDialog();
      return;
    }
    
    // Navigate to replay screen
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => UpgradeReplayScreen(
          conversation: _conversationService.getConversationHistory(),
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: animation.drive(
              Tween(begin: const Offset(0, 1), end: Offset.zero).chain(
                CurveTween(curve: Curves.easeOut),
              ),
            ),
            child: child,
          );
        },
      ),
    );
  }
  
  void _showUpgradeDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: _buildUpgradeSheet(),
      ),
    );
  }
  
  Widget _buildUpgradeSheet() {
    final subscriptionService = Provider.of<EnhancedSubscriptionService>(context);
    
    return Column(
      children: [
        // Handle bar
        Container(
          width: 50,
          height: 5,
          margin: const EdgeInsets.only(top: 12),
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.purple, Colors.blue],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.rocket_launch, size: 40, color: Colors.white),
                ).animate().scale(duration: 500.ms),
                
                const SizedBox(height: 24),
                
                // Title
                const Text(
                  'Unlock Unlimited Practice',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ).animate().slideY(begin: 0.2, duration: 300.ms),
                
                const SizedBox(height: 12),
                
                // Subtitle
                Text(
                  'You\'ve used all ${subscriptionService.dailyLimit} free Upgrade Replays today',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white60,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 32),
                
                // Pro features
                _buildFeaturesList(),
                
                const SizedBox(height: 32),
                
                // Pricing options
                _buildPricingOptions(),
                
                const SizedBox(height: 24),
                
                // Timer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer, size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(
                        'Resets in ${subscriptionService.getTimeUntilReset()}',
                        style: const TextStyle(color: Colors.orange, fontSize: 14),
                      ),
                    ],
                  ),
                ).animate().fade(delay: 500.ms),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildFeaturesList() {
    final features = [
      {'icon': Icons.all_inclusive, 'text': '30 Upgrade Replays per day'},
      {'icon': Icons.speed, 'text': 'Priority AI responses'},
      {'icon': Icons.analytics, 'text': 'Advanced progress tracking'},
      {'icon': Icons.star, 'text': 'Premium voice options'},
      {'icon': Icons.support, 'text': 'Priority support'},
    ];
    
    return Column(
      children: features.asMap().entries.map((entry) {
        final index = entry.key;
        final feature = entry.value;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  feature['icon'] as IconData,
                  color: Colors.purple,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  feature['text'] as String,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ).animate()
          .slideX(
            begin: -0.2,
            delay: Duration(milliseconds: 100 * index),
            duration: 300.ms,
          )
          .fade();
      }).toList(),
    );
  }
  
  Widget _buildPricingOptions() {
    return Column(
      children: [
        // Monthly option
        _buildPricingCard(
          title: 'Monthly',
          price: '₩9,900',
          period: '/month',
          isPopular: true,
          onTap: () => _purchaseSubscription('pro_monthly'),
        ),
        
        const SizedBox(height: 12),
        
        // Yearly option
        _buildPricingCard(
          title: 'Yearly',
          price: '₩99,000',
          period: '/year',
          savings: 'Save 17%',
          onTap: () => _purchaseSubscription('pro_yearly'),
        ),
      ],
    );
  }
  
  Widget _buildPricingCard({
    required String title,
    required String price,
    required String period,
    String? savings,
    bool isPopular = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: isPopular
              ? LinearGradient(colors: [Colors.purple, Colors.blue])
              : null,
          color: isPopular ? null : Colors.white10,
          borderRadius: BorderRadius.circular(15),
          border: isPopular ? null : Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isPopular ? Colors.white : Colors.white70,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isPopular) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'POPULAR',
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
                if (savings != null)
                  Text(
                    savings,
                    style: const TextStyle(
                      color: Colors.green,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  price,
                  style: TextStyle(
                    color: isPopular ? Colors.white : Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  period,
                  style: TextStyle(
                    color: isPopular ? Colors.white70 : Colors.white54,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _purchaseSubscription(String productId) async {
    // TODO: Implement purchase logic
    Navigator.pop(context);
    _showSuccessMessage('Purchase initiated');
  }
  
  @override
  Widget build(BuildContext context) {
    return Consumer<EnhancedSubscriptionService>(
      builder: (context, subscriptionService, child) {
        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(subscriptionService),
                Expanded(
                  child: _buildMainContent(),
                ),
                _buildBottomControls(subscriptionService),
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildHeader(EnhancedSubscriptionService subscriptionService) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Status badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: subscriptionService.isPro
                  ? LinearGradient(colors: [Colors.purple, Colors.blue])
                  : null,
              color: subscriptionService.isPro ? null : Colors.white10,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  subscriptionService.isPro ? Icons.star : Icons.lock,
                  size: 14,
                  color: subscriptionService.isPro ? Colors.white : Colors.white54,
                ),
                const SizedBox(width: 6),
                Text(
                  subscriptionService.isPro ? 'PRO' : 'FREE',
                  style: TextStyle(
                    color: subscriptionService.isPro ? Colors.white : Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ).animate().slideX(begin: -0.2, duration: 300.ms),
          
          // Usage counter
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.replay, size: 14, color: Colors.white54),
                const SizedBox(width: 6),
                Text(
                  '${subscriptionService.remainingReplays} left',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ).animate().slideX(begin: 0.2, duration: 300.ms),
        ],
      ),
    );
  }
  
  Widget _buildMainContent() {
    if (!_isConversationActive) {
      return _buildStartScreen();
    }
    
    return _buildConversationScreen();
  }
  
  Widget _buildStartScreen() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'English Conversation',
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.bold,
          ),
        ).animate().slideY(begin: -0.2, duration: 500.ms),
        
        const SizedBox(height: 8),
        
        const Text(
          'Practice with AI, Get Instant Feedback',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 16,
          ),
        ).animate().fadeIn(delay: 200.ms),
        
        const SizedBox(height: 60),
        
        // Start button
        GestureDetector(
          onTap: _startConversation,
          child: Container(
            width: 180,
            height: 180,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.blue.shade600, Colors.purple.shade600],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.4),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.mic, size: 60, color: Colors.white),
                const SizedBox(height: 8),
                const Text(
                  'START',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ).animate(
            controller: _breathingController,
            onPlay: (controller) => controller.repeat(reverse: true),
          ).scale(
            begin: const Offset(1.0, 1.0),
            end: const Offset(1.05, 1.05),
          ),
        ),
      ],
    );
  }
  
  Widget _buildConversationScreen() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Status
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _statusColor.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _currentStatus,
            style: TextStyle(
              color: _statusColor,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ).animate().fadeIn(duration: 300.ms),
        
        const SizedBox(height: 40),
        
        // Visual indicator
        _buildVisualIndicator(),
        
        const SizedBox(height: 40),
        
        // Display text
        if (_displayText.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 30),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _currentSpeaker == 'AI' 
                  ? Colors.blue.withOpacity(0.1)
                  : Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: _currentSpeaker == 'AI'
                    ? Colors.blue.withOpacity(0.3)
                    : Colors.green.withOpacity(0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentSpeaker,
                  style: TextStyle(
                    color: _currentSpeaker == 'AI' ? Colors.blue : Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _displayText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ).animate().slideY(begin: 0.1, duration: 300.ms).fade(),
        
        const SizedBox(height: 20),
        
        // Turn counter
        if (_conversationTurns > 0)
          Text(
            'Turn $_conversationTurns/6',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 12,
            ),
          ),
      ],
    );
  }
  
  Widget _buildVisualIndicator() {
    if (_isListening) {
      // Listening animation
      return Stack(
        alignment: Alignment.center,
        children: [
          // Ripple effect
          ...List.generate(3, (index) {
            return Container(
              width: 150 + (index * 30.0),
              height: 150 + (index * 30.0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.red.withOpacity(0.3 - (index * 0.1)),
                  width: 2,
                ),
              ),
            ).animate(
              controller: _waveController,
              onPlay: (controller) => controller.repeat(),
            ).scale(
              begin: const Offset(0.8, 0.8),
              end: const Offset(1.2, 1.2),
              delay: Duration(milliseconds: index * 200),
            ).fade(
              begin: 1.0,
              end: 0.0,
              delay: Duration(milliseconds: index * 200),
            );
          }),
          
          // Center mic
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [Colors.red.shade400, Colors.red.shade700],
              ),
            ),
            child: const Icon(Icons.mic, size: 50, color: Colors.white),
          ).animate().scale(
            begin: const Offset(1.0, 1.0),
            end: Offset(_microphoneScale, _microphoneScale),
            duration: 200.ms,
          ),
        ],
      );
    } else if (_isProcessing) {
      // Processing animation
      return Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Colors.orange.shade400, Colors.purple.shade400],
          ),
        ),
        child: const Icon(Icons.psychology, size: 50, color: Colors.white),
      ).animate(
        onPlay: (controller) => controller.repeat(),
      ).rotate(duration: const Duration(seconds: 2));
    } else {
      // Idle state
      return Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [Colors.blue.shade400, Colors.purple.shade400],
          ),
        ),
        child: const Icon(Icons.headphones, size: 50, color: Colors.white),
      );
    }
  }
  
  Widget _buildBottomControls(EnhancedSubscriptionService subscriptionService) {
    if (!_canUpgradeReplay) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Upgrade Replay button
          GestureDetector(
            onTap: _handleUpgradeReplay,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade600, Colors.teal.shade600],
                ),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.green.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.replay, color: Colors.white),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Upgrade Replay',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${subscriptionService.remainingReplays} remaining today',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ).animate().slideY(begin: 1, duration: 500.ms).fade(),
          
          const SizedBox(height: 12),
          
          // New conversation button
          TextButton(
            onPressed: () {
              setState(() {
                _isConversationActive = false;
                _canUpgradeReplay = false;
                _displayText = '';
                _conversationTurns = 0;
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
  
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }
  
  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green.shade700,
      ),
    );
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _waveController.dispose();
    _breathingController.dispose();
    _audioService.dispose();
    super.dispose();
  }
}