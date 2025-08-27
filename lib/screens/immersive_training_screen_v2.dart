import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui';
import 'dart:convert';
import '../services/image_generation_service.dart' as ai_service;
import '../services/content_generation_service.dart';
import '../services/audio_service.dart';

// 학습 단계 정의
enum LearningPhase {
  loading,           // 로딩
  ambience,          // 배경음 재생
  smallTalk,         // 스몰톡 재생 (10-20초)
  lastSentence,      // 마지막 문장 표시
  userResponse,      // 사용자 응답 대기
  feedback,          // 피드백 표시
  completion         // 완료 및 다음 준비
}

class ImmersiveTrainingScreenV2 extends StatefulWidget {
  const ImmersiveTrainingScreenV2({super.key});

  @override
  _ImmersiveTrainingScreenV2State createState() => _ImmersiveTrainingScreenV2State();
}

class _ImmersiveTrainingScreenV2State extends State<ImmersiveTrainingScreenV2>
    with TickerProviderStateMixin {
  
  // 서비스
  final ai_service.ImageGenerationService _imageService =
      ai_service.ImageGenerationService();
  final ContentGenerationService _contentService = ContentGenerationService();
  final AudioService _audioService = AudioService();
  
  // 음성 인식
  late stt.SpeechToText _speech;
  bool _isListening = false;
  
  // 학습 단계
  LearningPhase currentPhase = LearningPhase.loading;
  
  // 컨텐츠 데이터
  String _imageUrl = '';
  String _scenario = 'street';
  String _currentLevel = 'beginner';
  String backgroundMusicUrl = '';
  List<String> smallTalkSentences = [];
  String lastSentence = '';
  String expectedResponse = '';
  List<String> alternativeResponses = [];
  String userSpeech = '';
  List<String> matchedWords = [];
  int _score = 0;
  
  // 애니메이션
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late AnimationController _typingController;
  late AnimationController _scaleController;
  
  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    
    // 애니메이션 초기화
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _typingController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    // 학습 시퀀스 시작
    _startLearningSequence();
  }
  
  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    _typingController.dispose();
    _scaleController.dispose();
    _audioService.dispose();
    super.dispose();
  }
  
  Future<void> _startLearningSequence() async {
    setState(() => currentPhase = LearningPhase.loading);
    
    try {
      // 1. 이미지와 컨텐츠 생성
      final imageContent = await _imageService.generateLearningContent(
        level: _currentLevel,
        userId: 'user',
        isPremium: true,
        theme: _scenario,
        provider: ai_service.AIImageProvider.stableDiffusion,
      );
      
      _imageUrl = imageContent['imageUrl'] ?? '';
      
      // GPT로 몰입형 컨텐츠 생성
      final content = await _contentService.generateImmersiveContent(
        imageUrl: _imageUrl,
        scenario: _scenario,
        level: _currentLevel,
      );
      
      setState(() {
        smallTalkSentences = List<String>.from(content['smallTalk'] ?? []);
        lastSentence = content['lastSentence']?.toString() ?? '';
        expectedResponse = content['expectedResponse']?.toString() ?? '';
        alternativeResponses = List<String>.from(content['alternatives'] ?? []);
      });
      
      // 2. 배경음악 시작 (페이드 인)
      setState(() => currentPhase = LearningPhase.ambience);
      _fadeController.forward();
      
      // 시나리오 기반 배경음악 재생
      try {
        await _audioService.playBackgroundMusic(_scenario);
      } catch (e) {
        print('Background music failed: $e');
        // 배경음악 없이 계속 진행
      }
      
      await Future.delayed(Duration(seconds: 2));
      
      // 3. 스몰톡 시작 (10-20초)
      setState(() => currentPhase = LearningPhase.smallTalk);
      await _playSmallTalk(content['smallTalkAudio'] ?? smallTalkSentences);
      
      // 4. 마지막 문장 팝업 표시
      setState(() => currentPhase = LearningPhase.lastSentence);
      _scaleController.forward();
      
      // 2초 대기 후 자동 음성 인식 시작
      await Future.delayed(Duration(seconds: 2));
      
      // 5. 사용자 응답 단계
      setState(() => currentPhase = LearningPhase.userResponse);
      _startAutoListening();
      
    } catch (e) {
      print('Error in learning sequence: $e');
      // 폴백 처리
      setState(() {
        currentPhase = LearningPhase.completion;
        _imageUrl = 'https://picsum.photos/1024/1024?random=${DateTime.now().millisecondsSinceEpoch}';
      });
    }
  }
  
  Future<void> _playSmallTalk(dynamic audioData) async {
    if (audioData is List<String>) {
      // TTS로 재생
      for (String sentence in audioData) {
        await _audioService.playTTS(sentence);
        await Future.delayed(Duration(milliseconds: 800));
      }
    } else {
      // 오디오 URL 재생
      await _audioService.playAudioUrl(audioData);
    }
  }
  
  void _startAutoListening() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
            _processFinalResponse();
          }
        },
        onError: (error) {
          print('Speech recognition error: $error');
          setState(() => _isListening = false);
        },
      );
      
      if (available) {
        setState(() => _isListening = true);
        
        _speech.listen(
          onResult: (result) {
            setState(() {
              userSpeech = result.recognizedWords;
              // 실시간 단어 매칭
              matchedWords = _findMatchedWords(userSpeech, expectedResponse);
            });
          },
          listenFor: Duration(seconds: 10),
          pauseFor: Duration(seconds: 3),
        );
      }
    }
  }
  
  List<String> _findMatchedWords(String userText, String expectedText) {
    final userWords = userText.toLowerCase().split(' ');
    final expectedWords = expectedText.toLowerCase().split(' ');
    
    return userWords
        .where((word) => expectedWords.contains(word))
        .toList();
  }
  
  void _processFinalResponse() {
    setState(() => currentPhase = LearningPhase.feedback);
    
    // 점수 계산
    final accuracy = matchedWords.length / expectedResponse.split(' ').length;
    _score = (accuracy * 100).round();
    
    // 타이핑 애니메이션 시작
    _typingController.forward();
    
    // 5초 후 다음 시나리오
    Future.delayed(Duration(seconds: 5), () {
      _loadNextScenario();
    });
  }
  
  void _loadNextScenario() {
    // 시나리오 순환
    final scenarios = ['street', 'restaurant', 'park', 'office', 'home'];
    final currentIndex = scenarios.indexOf(_scenario);
    _scenario = scenarios[(currentIndex + 1) % scenarios.length];
    
    // 애니메이션 리셋
    _fadeController.reset();
    _scaleController.reset();
    _typingController.reset();
    
    // 새로운 학습 시퀀스 시작
    _startLearningSequence();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),  // 다크 배경
      body: Stack(
        children: [
          // 중앙 이미지 컨테이너
          Center(
            child: _buildCentralImageContainer(),
          ),
          
          // UI 오버레이
          if (currentPhase != LearningPhase.loading) ...[
            _buildPhaseUI(),
          ],
          
          // 로딩 인디케이터
          if (currentPhase == LearningPhase.loading)
            _buildLoadingIndicator(),
          
          // 상단 툴바
          _buildTopBar(),
        ],
      ),
    );
  }
  
  Widget _buildCentralImageContainer() {
    return AnimatedOpacity(
      duration: Duration(milliseconds: 800),
      opacity: _imageUrl.isNotEmpty ? 1.0 : 0.0,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 800,   // 데스크톱 최대 너비
          maxHeight: 600,  // 최대 높이 제한
        ),
        margin: EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              // 이미지 레이어 (Base64와 URL 둘 다 지원)
              if (_imageUrl.isNotEmpty)
                _buildImageWidget(),
              
              // 이미지 로딩 중이면 스켈레톤 표시
              if (_imageUrl.isEmpty && currentPhase == LearningPhase.loading)
                Container(
                  color: Colors.grey[900],
                  child: Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                  ),
                ),
              
              // 그라데이션 오버레이
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.3),
                      Colors.transparent,
                      Colors.black.withOpacity(0.5),
                    ],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildPhaseUI() {
    switch (currentPhase) {
      case LearningPhase.ambience:
        return _buildAmbienceUI();
        
      case LearningPhase.smallTalk:
        return _buildSmallTalkUI();
        
      case LearningPhase.lastSentence:
        return _buildLastSentenceUI();
        
      case LearningPhase.userResponse:
        return _buildUserResponseUI();
        
      case LearningPhase.feedback:
        return _buildFeedbackUI();
        
      case LearningPhase.completion:
        return _buildCompletionUI();
        
      default:
        return Container();
    }
  }
  
  Widget _buildAmbienceUI() {
    return Center(
      child: FadeTransition(
        opacity: _fadeController,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.music_note, color: Colors.white70, size: 20),
              SizedBox(width: 8),
              Text(
                'Setting the scene...',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildSmallTalkUI() {
    return Positioned(
      bottom: 150,
      left: 20,
      right: 20,
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          children: [
            Icon(Icons.record_voice_over, color: Colors.white70, size: 30),
            SizedBox(height: 10),
            Text(
              'Listening to conversation...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 10),
            // 현재 재생 중인 문장 표시
            if (smallTalkSentences.isNotEmpty)
              Text(
                smallTalkSentences.first,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLastSentenceUI() {
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.3,
      left: 20,
      right: 20,
      child: Center(
        child: ScaleTransition(
          scale: CurvedAnimation(
            parent: _scaleController,
            curve: Curves.elasticOut,
          ),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white24, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.blue.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person, color: Colors.white70, size: 20),
                SizedBox(width: 12),
                Flexible(
                  child: Text(
                    lastSentence,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildUserResponseUI() {
    return Positioned(
      bottom: 50,
      left: 20,
      right: 20,
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.95),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          children: [
            // 빈칸 문장 또는 사용자 음성 표시
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: _buildResponseText(userSpeech, matchedWords, expectedResponse),
              ),
            ),
            SizedBox(height: 20),
            // 마이크 애니메이션
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: _isListening ? 70 + (_pulseController.value * 10) : 60,
                  height: _isListening ? 70 + (_pulseController.value * 10) : 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isListening ? Colors.blue : Colors.grey[400],
                    boxShadow: _isListening ? [
                      BoxShadow(
                        color: Colors.blue.withOpacity(0.3 + _pulseController.value * 0.2),
                        blurRadius: 20 + (_pulseController.value * 10),
                        spreadRadius: 5,
                      ),
                    ] : [],
                  ),
                  child: Icon(
                    Icons.mic,
                    color: Colors.white,
                    size: _isListening ? 35 : 30,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildFeedbackUI() {
    final Color feedbackColor = _score >= 80 
        ? Colors.green 
        : _score >= 50 
            ? Colors.orange 
            : Colors.blue;
    
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.4,
      left: 20,
      right: 20,
      child: Column(
        children: [
          // 점수 표시
          Container(
            padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            decoration: BoxDecoration(
              color: feedbackColor.withOpacity(0.9),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Text(
              'Score: $_score%',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(height: 20),
          // 정답 타이핑 애니메이션
          _buildTypingAnimation(expectedResponse),
        ],
      ),
    );
  }
  
  Widget _buildCompletionUI() {
    return Center(
      child: Container(
        padding: EdgeInsets.all(30),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 50),
            SizedBox(height: 10),
            Text(
              'Great job! Moving to next scene...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  List<InlineSpan> _buildResponseText(String userText, List<String> matched, String expected) {
    List<InlineSpan> spans = [];
    
    if (userText.isEmpty) {
      // 빈칸 표시
      final expectedWords = expected.split(' ');
      for (int i = 0; i < expectedWords.length; i++) {
        spans.add(
          TextSpan(
            text: '______ ',
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 20,
              letterSpacing: 1,
            ),
          ),
        );
      }
      return spans;
    }
    
    // 사용자 음성을 단어별로 분리
    final words = userText.split(' ');
    
    for (String word in words) {
      final isMatched = matched.contains(word.toLowerCase());
      
      spans.add(
        TextSpan(
          text: word + ' ',
          style: TextStyle(
            color: isMatched ? Colors.green : Colors.grey[700],
            fontSize: 20,
            fontWeight: isMatched ? FontWeight.bold : FontWeight.normal,
            backgroundColor: isMatched ? Colors.green.withOpacity(0.1) : null,
          ),
        ),
      );
    }
    
    return spans;
  }
  
  Widget _buildTypingAnimation(String text) {
    return AnimatedBuilder(
      animation: _typingController,
      builder: (context, child) {
        final progress = _typingController.value;
        final visibleLength = (text.length * progress).round();
        final visibleText = text.substring(0, visibleLength);
        
        return Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue[700]!, Colors.blue[500]!],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 24),
              SizedBox(width: 12),
              Flexible(
                child: Text(
                  visibleText,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 뒤로가기
            IconButton(
              icon: Icon(Icons.arrow_back, color: Colors.white70),
              onPressed: () => Navigator.of(context).pop(),
            ),
            
            // 레벨 표시
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                _currentLevel.toUpperCase(),
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            
            // 새로고침
            IconButton(
              icon: Icon(Icons.refresh, color: Colors.white70),
              onPressed: () {
                _fadeController.reset();
                _scaleController.reset();
                _typingController.reset();
                _startLearningSequence();
              },
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
          ),
          SizedBox(height: 20),
          Text(
            'Creating immersive experience...',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
  
  // Base64 이미지와 URL 이미지 둘 다 처리하는 위젯
  Widget _buildImageWidget() {
    // Base64 데이터 URL인 경우
    if (_imageUrl.startsWith('data:image')) {
      try {
        final base64String = _imageUrl.split(',')[1];
        final imageBytes = base64Decode(base64String);
        
        return Image.memory(
          imageBytes,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (context, error, stackTrace) {
            print('Base64 image error: $error');
            return _buildImageErrorWidget();
          },
        );
      } catch (e) {
        print('Base64 decoding error: $e');
        return _buildImageErrorWidget();
      }
    }
    
    // 일반 URL 이미지인 경우
    return Image.network(
      _imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        
        return Container(
          color: Colors.grey[900],
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
                SizedBox(height: 20),
                Text(
                  'Loading image...',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        print('Network image error: $error');
        return _buildImageErrorWidget();
      },
    );
  }
  
  Widget _buildImageErrorWidget() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.grey[900]!, Colors.grey[800]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_not_supported,
              color: Colors.grey[600],
              size: 64,
            ),
            SizedBox(height: 16),
            Text(
              'Image unavailable',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Continuing with text only',
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}