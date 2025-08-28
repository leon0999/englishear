import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../services/conversation_service.dart';
import '../services/usage_limit_service.dart';
import '../services/enhanced_subscription_service.dart';
import '../core/logger.dart';

class VoiceChatScreen extends StatefulWidget {
  const VoiceChatScreen({super.key});

  @override
  State<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends State<VoiceChatScreen>
    with TickerProviderStateMixin {
  late ConversationService _conversationService;
  late UsageLimitService _usageLimitService;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  @override
  void initState() {
    super.initState();
    _conversationService = ConversationService();
    _usageLimitService = UsageLimitService();
    _usageLimitService.initialize();
    
    // 맥동 애니메이션 (음성 인식 중)
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
  }
  
  @override
  void dispose() {
    _pulseController.dispose();
    _conversationService.dispose();
    super.dispose();
  }
  
  // 대화 시작
  Future<void> _startConversation() async {
    try {
      await _conversationService.startNewConversation();
    } catch (e) {
      _showError('Failed to start conversation');
    }
  }
  
  // Upgrade Replay 실행
  Future<void> _executeUpgradeReplay() async {
    // 사용 제한 체크
    final canUse = await _usageLimitService.useReplay();
    if (!canUse) {
      _showLimitReached();
      return;
    }
    
    try {
      await _conversationService.executeUpgradeReplay();
      _showReplayComplete();
    } catch (e) {
      _showError('Failed to execute replay');
    }
  }
  
  // 제한 도달 알림
  void _showLimitReached() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Daily Limit Reached',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _usageLimitService.isPro
                  ? 'You\'ve used all 30 replays today.'
                  : 'You\'ve used all 10 free replays today.',
              style: TextStyle(color: Colors.grey[400]),
            ),
            if (!_usageLimitService.isPro) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _showUpgradeDialog,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: const Text('Upgrade to Pro'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }
  
  // 업그레이드 다이얼로그
  void _showUpgradeDialog() {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Upgrade to Pro',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star, color: Colors.amber, size: 60),
            const SizedBox(height: 20),
            const Text(
              '₩9,900 / month',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            _buildFeatureItem('30 Upgrade Replays daily'),
            _buildFeatureItem('Priority AI responses'),
            _buildFeatureItem('Advanced pronunciation analysis'),
            _buildFeatureItem('No ads'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Later', style: TextStyle(color: Colors.grey[500])),
          ),
          ElevatedButton(
            onPressed: () async {
              // 구독 처리
              final subscriptionService = context.read<EnhancedSubscriptionService>();
              await subscriptionService.purchaseSubscription('pro_monthly');
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: const Text('Subscribe Now'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.grey[300]),
            ),
          ),
        ],
      ),
    );
  }
  
  // Replay 완료 알림
  void _showReplayComplete() {
    final report = _conversationService.currentSession?.finalReport;
    if (report == null) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[900],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Conversation Analysis',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              report['summary'] as String,
              style: TextStyle(color: Colors.grey[300], height: 1.5),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatItem('Turns', report['userTurns'].toString()),
                _buildStatItem('Duration', '${report['duration']}s'),
                _buildStatItem('Improvement', '85%'),
              ],
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _startConversation(); // 새 대화 시작
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: const Text('Start New Conversation'),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    );
  }
  
  // 에러 표시
  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[600],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _conversationService,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SafeArea(
          child: Consumer<ConversationService>(
            builder: (context, service, _) {
              final hasSession = service.currentSession != null;
              final canReplay = service.currentSession?.canReplay ?? false;
              
              return Column(
                children: [
                  // Header
                  _buildHeader(),
                  
                  // Conversation Display
                  Expanded(
                    child: hasSession
                        ? _buildConversationView(service)
                        : _buildWelcomeView(),
                  ),
                  
                  // Bottom Controls
                  _buildBottomControls(service, hasSession, canReplay),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
  
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'EnglishEar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Consumer<UsageLimitService>(
                builder: (context, limit, _) => Text(
                  'Replays: ${limit.remainingReplays}/${limit.dailyLimit}',
                  style: TextStyle(
                    color: limit.isPro ? Colors.purple : Colors.grey[500],
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            onPressed: () {
              // Settings
            },
          ),
        ],
      ),
    );
  }
  
  Widget _buildWelcomeView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Colors.blue[600]!, Colors.purple[600]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const Icon(
              Icons.mic_rounded,
              size: 60,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 30),
          const Text(
            'Ready to Practice?',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Start a conversation with AI',
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildConversationView(ConversationService service) {
    final turns = service.currentSession?.turns ?? [];
    
    return Column(
      children: [
        // Scenario Badge
        if (service.currentSession != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blue[900]?.withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.blue[700]!, width: 1),
            ),
            child: Text(
              '📍 ${service.currentSession!.scenario}',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        
        // Conversation Turns
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: turns.length,
            itemBuilder: (context, index) {
              final turn = turns[index];
              final isAI = turn.speaker == 'ai';
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment:
                      isAI ? MainAxisAlignment.start : MainAxisAlignment.end,
                  children: [
                    if (!isAI) const Spacer(),
                    Container(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isAI ? Colors.grey[800] : Colors.blue[700],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            turn.improvedText ?? turn.originalText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              height: 1.4,
                            ),
                          ),
                          if (!isAI && turn.improvedText != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Original: ${turn.originalText}',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isAI) const Spacer(),
                  ],
                ),
              );
            },
          ),
        ),
        
        // Current Transcript
        if (service.isListening && service.currentTranscript.isNotEmpty)
          Container(
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue, width: 1),
            ),
            child: Row(
              children: [
                const Icon(Icons.mic, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    service.currentTranscript,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
  
  Widget _buildBottomControls(
    ConversationService service,
    bool hasSession,
    bool canReplay,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Speaking indicator
          if (service.isSpeaking)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildSpeakingIndicator(),
                  const SizedBox(width: 12),
                  Text(
                    'AI is speaking...',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
          
          Row(
            children: [
              // Start/Mic Button
              Expanded(
                child: hasSession
                    ? _buildMicButton(service)
                    : _buildStartButton(),
              ),
              
              const SizedBox(width: 16),
              
              // Upgrade Replay Button
              _buildReplayButton(canReplay),
            ],
          ),
          
          // User turn counter
          if (hasSession)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${service.currentSession!.userTurnCount}/6 turns to unlock replay',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildStartButton() {
    return ElevatedButton(
      onPressed: _startConversation,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        minimumSize: const Size(double.infinity, 60),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.play_arrow, size: 28),
          SizedBox(width: 8),
          Text(
            'Start Conversation',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMicButton(ConversationService service) {
    final isListening = service.isListening;
    
    return GestureDetector(
      onTap: service.toggleListening,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          if (isListening) {
            _pulseController.repeat(reverse: true);
          } else {
            _pulseController.stop();
            _pulseController.reset();
          }
          
          return Container(
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isListening
                    ? [Colors.red[600]!, Colors.red[800]!]
                    : [Colors.blue[600]!, Colors.blue[800]!],
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: isListening
                  ? [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.5),
                        blurRadius: 20 * _pulseAnimation.value,
                        spreadRadius: 5 * _pulseAnimation.value,
                      ),
                    ]
                  : [],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isListening ? Icons.stop : Icons.mic,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  isListening ? 'Stop' : 'Speak',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildReplayButton(bool canReplay) {
    return Container(
      width: 120,
      height: 60,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: canReplay
              ? [Colors.purple[600]!, Colors.purple[800]!]
              : [Colors.grey[700]!, Colors.grey[800]!],
        ),
        borderRadius: BorderRadius.circular(30),
      ),
      child: ElevatedButton(
        onPressed: canReplay ? _executeUpgradeReplay : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.refresh, color: Colors.white),
            const Text(
              'Upgrade',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'Replay',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSpeakingIndicator() {
    return SizedBox(
      width: 30,
      height: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(
          3,
          (index) => AnimatedContainer(
            duration: Duration(milliseconds: 300 + (index * 100)),
            width: 4,
            height: _conversationService.isSpeaking ? 20 : 10,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }
}