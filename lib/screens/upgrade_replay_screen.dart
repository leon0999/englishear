// lib/screens/upgrade_replay_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:html' as html;
import '../services/voice_conversation_service.dart';
import '../services/upgrade_replay_service.dart';

class UpgradeReplayScreen extends StatefulWidget {
  final List<ConversationTurn> conversation;
  
  const UpgradeReplayScreen({
    Key? key,
    required this.conversation,
  }) : super(key: key);

  @override
  _UpgradeReplayScreenState createState() => _UpgradeReplayScreenState();
}

class _UpgradeReplayScreenState extends State<UpgradeReplayScreen> 
    with TickerProviderStateMixin {
  final UpgradeReplayService _replayService = UpgradeReplayService();
  
  ConversationReplay? _replay;
  bool _isAnalyzing = true;
  bool _isPlayingReplay = false;
  int _currentReplayIndex = -1;
  late AnimationController _progressController;
  
  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _analyzeConversation();
  }
  
  Future<void> _analyzeConversation() async {
    try {
      final replay = await _replayService.analyzeAndUpgrade(widget.conversation);
      setState(() {
        _replay = replay;
        _isAnalyzing = false;
      });
    } catch (e) {
      print('Error analyzing conversation: $e');
      setState(() {
        _isAnalyzing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to analyze conversation')),
      );
    }
  }
  
  Future<void> _playUpgradedConversation() async {
    if (_replay == null) return;
    
    setState(() {
      _isPlayingReplay = true;
      _currentReplayIndex = 0;
    });
    
    // Generate audio for each turn
    final audioUrls = await _replayService.generateReplayAudio(
      _replay!.upgradedConversation,
    );
    
    // Play each audio in sequence
    for (int i = 0; i < audioUrls.length; i++) {
      setState(() {
        _currentReplayIndex = i;
      });
      
      if (audioUrls[i].isNotEmpty) {
        final audio = html.AudioElement()
          ..src = audioUrls[i]
          ..autoplay = false;
        
        await audio.play();
        await audio.onEnded.first;
      }
      
      // Small pause between turns
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    setState(() {
      _isPlayingReplay = false;
      _currentReplayIndex = -1;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Upgrade Replay'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isAnalyzing ? _buildLoadingView() : _buildResultView(),
    );
  }
  
  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          ).animate(
            onPlay: (controller) => controller.repeat(),
          ).rotate(duration: const Duration(seconds: 2)),
          
          const SizedBox(height: 30),
          
          const Text(
            'Analyzing your conversation...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
            ),
          ).animate().fade(duration: 500.ms),
          
          const SizedBox(height: 10),
          
          const Text(
            'Creating personalized improvements',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
            ),
          ).animate().fade(delay: 200.ms, duration: 500.ms),
        ],
      ),
    );
  }
  
  Widget _buildResultView() {
    if (_replay == null) {
      return const Center(
        child: Text(
          'No analysis available',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Score Card
          _buildScoreCard(),
          
          const SizedBox(height: 30),
          
          // Play Button
          _buildPlayButton(),
          
          const SizedBox(height: 30),
          
          // Improvements Section
          _buildImprovementsSection(),
          
          const SizedBox(height: 30),
          
          // Conversation Comparison
          _buildConversationComparison(),
          
          const SizedBox(height: 30),
          
          // Feedback Section
          _buildFeedbackSection(),
        ],
      ),
    );
  }
  
  Widget _buildScoreCard() {
    return Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.blue.shade900,
            Colors.purple.shade900,
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Your Native Score',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_replay!.overallScore}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 60,
                  fontWeight: FontWeight.bold,
                ),
              ).animate().scale(delay: 300.ms, duration: 500.ms),
              const Text(
                '/100',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 24,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LinearProgressIndicator(
            value: _replay!.overallScore / 100,
            backgroundColor: Colors.white.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(
              _replay!.overallScore >= 80 ? Colors.green :
              _replay!.overallScore >= 60 ? Colors.orange :
              Colors.red,
            ),
          ).animate().scaleX(
            begin: 0,
            delay: 500.ms,
            duration: 1000.ms,
            curve: Curves.easeOut,
          ),
        ],
      ),
    ).animate().slideX(begin: -0.2, duration: 500.ms).fade();
  }
  
  Widget _buildPlayButton() {
    return Center(
      child: ElevatedButton.icon(
        onPressed: _isPlayingReplay ? null : _playUpgradedConversation,
        icon: Icon(_isPlayingReplay ? Icons.volume_up : Icons.play_arrow),
        label: Text(
          _isPlayingReplay ? 'Playing Upgraded Conversation...' : 'Play Upgraded Conversation',
          style: const TextStyle(fontSize: 16),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
      ),
    ).animate().scale(delay: 600.ms, duration: 300.ms);
  }
  
  Widget _buildImprovementsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Key Improvements',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 15),
        ..._replay!.improvements.asMap().entries.map((entry) {
          final index = entry.key;
          final improvement = entry.value;
          
          return Container(
            margin: const EdgeInsets.only(bottom: 15),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.blue.withOpacity(0.3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Text(
                        'Turn ${index + 1}',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Icon(
                          Icons.trending_up,
                          color: Colors.green,
                          size: 16,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '+${improvement.nativeScore - 50} points',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Original: "${improvement.original}"',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Improved: "${improvement.improved}"',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (improvement.improvements.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  ...improvement.improvements.map((imp) => Padding(
                    padding: const EdgeInsets.only(left: 10, top: 5),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            imp,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),
                ],
              ],
            ),
          ).animate()
            .slideX(
              begin: 0.1,
              delay: Duration(milliseconds: 700 + index * 100),
              duration: 300.ms,
            )
            .fade();
        }),
      ],
    );
  }
  
  Widget _buildConversationComparison() {
    if (_isPlayingReplay && _currentReplayIndex >= 0) {
      final turn = _replay!.upgradedConversation[_currentReplayIndex];
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: turn.speaker == 'AI' ? 
            Colors.blue.withOpacity(0.1) : 
            Colors.green.withOpacity(0.1),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: turn.speaker == 'AI' ? 
              Colors.blue.withOpacity(0.3) : 
              Colors.green.withOpacity(0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              turn.speaker == 'AI' ? 'AI' : 'You (Improved)',
              style: TextStyle(
                color: turn.speaker == 'AI' ? Colors.blue : Colors.green,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              turn.text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ).animate().scale(duration: 200.ms);
    }
    
    return const SizedBox.shrink();
  }
  
  Widget _buildFeedbackSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.amber.withOpacity(0.1),
            Colors.orange.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: Colors.amber.withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(
                Icons.lightbulb,
                color: Colors.amber,
                size: 20,
              ),
              SizedBox(width: 10),
              Text(
                'Personalized Feedback',
                style: TextStyle(
                  color: Colors.amber,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            _replay!.feedback,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    ).animate()
      .slideY(begin: 0.1, delay: 1000.ms, duration: 500.ms)
      .fade();
  }
  
  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }
}