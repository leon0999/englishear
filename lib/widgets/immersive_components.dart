// lib/widgets/immersive_components.dart

import 'package:flutter/material.dart';
import 'dart:math' as math;

class ImmersiveComponents {
  
  // 마지막 문장 팝업 (말풍선 스타일)
  static Widget buildLastSentencePopup({
    required String sentence,
    required Animation<double> animation,
  }) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -1),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.elasticOut,
      )),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 20),
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.blue.withOpacity(0.5),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.blue.withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 2,
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person,
                    color: Colors.blue,
                    size: 24,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Native Speaker',
                        style: TextStyle(
                          color: Colors.blue[300],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        sentence,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 15),
            // 응답 프롬프트
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.green.withOpacity(0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.mic, color: Colors.green, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'Your turn to respond',
                    style: TextStyle(
                      color: Colors.green[300],
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // 사용자 응답 입력 UI (향상된 버전)
  static Widget buildResponseInput({
    required String userSpeech,
    required List<String> matchedWords,
    required String expectedResponse,
    required bool isListening,
    required Animation<double> pulseAnimation,
  }) {
    return Container(
      margin: EdgeInsets.all(20),
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.blue.withOpacity(0.1),
            blurRadius: 30,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 진행 상태 표시
          _buildProgressIndicator(matchedWords.length, expectedResponse.split(' ').length),
          SizedBox(height: 20),
          
          // 응답 텍스트 표시
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: _buildAdvancedResponseText(
                  userSpeech,
                  matchedWords,
                  expectedResponse,
                ),
              ),
            ),
          ),
          SizedBox(height: 24),
          
          // 마이크 버튼
          _buildAnimatedMicButton(isListening, pulseAnimation),
          
          SizedBox(height: 12),
          
          // 힌트 텍스트
          Text(
            isListening ? 'Listening...' : 'Tap to speak',
            style: TextStyle(
              color: isListening ? Colors.blue : Colors.grey[600],
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  // 진행 상태 표시기
  static Widget _buildProgressIndicator(int matched, int total) {
    final progress = total > 0 ? matched / total : 0.0;
    
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Progress',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '$matched/$total words',
              style: TextStyle(
                color: Colors.blue,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(
              progress >= 0.8 ? Colors.green : 
              progress >= 0.5 ? Colors.orange : Colors.blue,
            ),
          ),
        ),
      ],
    );
  }
  
  // 향상된 응답 텍스트 빌더
  static List<InlineSpan> _buildAdvancedResponseText(
    String userSpeech,
    List<String> matchedWords,
    String expectedResponse,
  ) {
    List<InlineSpan> spans = [];
    
    if (userSpeech.isEmpty) {
      // 빈칸 표시 (예상 응답 힌트)
      final expectedWords = expectedResponse.split(' ');
      for (int i = 0; i < expectedWords.length; i++) {
        final word = expectedWords[i];
        final underscoreLength = math.min(word.length, 8);
        
        spans.add(
          TextSpan(
            text: '_' * underscoreLength,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 20,
              letterSpacing: 2,
              fontFamily: 'monospace',
            ),
          ),
        );
        
        if (i < expectedWords.length - 1) {
          spans.add(TextSpan(text: '  ')); // 단어 간격
        }
      }
    } else {
      // 사용자 음성 표시
      final words = userSpeech.split(' ');
      
      for (int i = 0; i < words.length; i++) {
        final word = words[i];
        final isMatched = matchedWords.contains(word.toLowerCase());
        
        spans.add(
          WidgetSpan(
            child: AnimatedContainer(
              duration: Duration(milliseconds: 300),
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: isMatched ? Colors.green.withOpacity(0.1) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isMatched ? Colors.green.withOpacity(0.3) : Colors.transparent,
                  width: 1,
                ),
              ),
              child: Text(
                word,
                style: TextStyle(
                  color: isMatched ? Colors.green[700] : Colors.grey[800],
                  fontSize: 20,
                  fontWeight: isMatched ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
        
        if (i < words.length - 1) {
          spans.add(TextSpan(text: ' '));
        }
      }
    }
    
    return spans;
  }
  
  // 애니메이션 마이크 버튼
  static Widget _buildAnimatedMicButton(bool isListening, Animation<double> pulseAnimation) {
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        final scale = isListening ? 1.0 + (pulseAnimation.value * 0.1) : 1.0;
        final glowRadius = isListening ? 20 + (pulseAnimation.value * 10) : 0;
        
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: isListening 
                  ? [Colors.blue[600]!, Colors.blue[400]!]
                  : [Colors.grey[500]!, Colors.grey[400]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: isListening 
                    ? Colors.blue.withOpacity(0.4)
                    : Colors.grey.withOpacity(0.3),
                  blurRadius: glowRadius.toDouble(),
                  spreadRadius: 2,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              isListening ? Icons.mic : Icons.mic_none,
              color: Colors.white,
              size: 36,
            ),
          ),
        );
      },
    );
  }
  
  // 타이핑 애니메이션 컴포넌트
  static Widget buildTypingAnimation({
    required String text,
    required AnimationController controller,
    bool showCheckmark = true,
  }) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final progress = controller.value;
        final visibleLength = (text.length * progress).round();
        final visibleText = text.substring(0, visibleLength);
        
        return Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.blue[700]!,
                Colors.blue[500]!,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 15,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            children: [
              if (showCheckmark) ...[
                Icon(
                  Icons.check_circle,
                  color: Colors.white,
                  size: 32,
                ),
                SizedBox(height: 12),
                Text(
                  'Correct Answer',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 8),
              ],
              Text(
                visibleText,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              if (progress < 1.0)
                Container(
                  width: 2,
                  height: 20,
                  color: Colors.white.withOpacity(0.8),
                  margin: EdgeInsets.only(left: 4),
                ),
            ],
          ),
        );
      },
    );
  }
  
  // 피드백 카드
  static Widget buildFeedbackCard({
    required int score,
    required String message,
    required Color color,
  }) {
    IconData icon;
    String title;
    
    if (score >= 80) {
      icon = Icons.star;
      title = 'Excellent!';
    } else if (score >= 60) {
      icon = Icons.thumb_up;
      title = 'Good Job!';
    } else if (score >= 40) {
      icon = Icons.sentiment_satisfied;
      title = 'Keep Going!';
    } else {
      icon = Icons.refresh;
      title = 'Try Again';
    }
    
    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: 48,
          ),
          SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Score: $score%',
            style: TextStyle(
              color: color.withOpacity(0.8),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  // 스몰톡 표시 UI
  static Widget buildSmallTalkDisplay({
    required List<String> sentences,
    required int currentIndex,
  }) {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.record_voice_over,
                color: Colors.white70,
                size: 24,
              ),
              SizedBox(width: 12),
              Text(
                'Conversation in progress...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          // 문장 리스트
          ...sentences.asMap().entries.map((entry) {
            final index = entry.key;
            final sentence = entry.value;
            final isActive = index == currentIndex;
            final isPast = index < currentIndex;
            
            return Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: EdgeInsets.only(top: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? Colors.blue : 
                             isPast ? Colors.green : 
                             Colors.grey[600],
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      sentence,
                      style: TextStyle(
                        color: isActive ? Colors.white : 
                               isPast ? Colors.white70 : 
                               Colors.white38,
                        fontSize: 16,
                        fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}