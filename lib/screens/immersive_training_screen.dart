import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'dart:math';
import 'dart:ui';  // ImageFilter 사용
import '../services/image_generation_service.dart' as ai_service;

class ImmersiveTrainingScreen extends StatefulWidget {
  const ImmersiveTrainingScreen({super.key});

  @override
  _ImmersiveTrainingScreenState createState() => _ImmersiveTrainingScreenState();
}

class _ImmersiveTrainingScreenState extends State<ImmersiveTrainingScreen>
    with TickerProviderStateMixin {
  // 서비스
  final ai_service.ImageGenerationService _imageService =
      ai_service.ImageGenerationService();

  // 음성 인식
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _userSpeech = '';
  double _audioLevel = 0.0;

  // 학습 데이터
  String _imageUrl = '';
  String _scenario = 'street'; // 현재 시나리오
  String _nativePrompt = "Look at this busy street scene!";
  List<String> _keywords = ['street', 'busy']; // 핵심 단어 2개만
  String _correctSentence = 'The street is busy with people and cars';
  Map<String, bool> _matchedWords = {};

  // 애니메이션
  late AnimationController _pulseController;
  late AnimationController _fadeController;
  
  // 레벨 시스템
  String _currentLevel = 'beginner';
  int _score = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    
    // 애니메이션 초기화
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    // 권한 요청 및 초기 장면 로드
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _requestMicrophonePermission();
    _loadNewScene();
  }

  // 웹/모바일 마이크 권한 처리
  Future<bool> _requestMicrophonePermission() async {
    if (kIsWeb) {
      // 웹에서는 브라우저가 자동으로 권한 요청
      return true;
    }
    
    // 모바일 권한 처리
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('마이크 권한이 필요합니다'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return status.isGranted;
  }

  // 새로운 장면 로드
  Future<void> _loadNewScene() async {
    setState(() {
      _isLoading = true;
      _matchedWords = {};
      _userSpeech = '';
    });

    // 시나리오 순환
    final scenarios = ['street', 'restaurant', 'park', 'office', 'home'];
    final currentIndex = scenarios.indexOf(_scenario);
    _scenario = scenarios[(currentIndex + 1) % scenarios.length];

    // 시나리오별 데이터 설정
    final scenarioData = _getScenarioData(_scenario);
    
    try {
      // Stable Diffusion으로 이미지 생성 (시나리오 테마 전달)
      final content = await _imageService.generateLearningContent(
        level: _currentLevel,
        userId: 'user',
        isPremium: true,
        theme: _scenario,  // 시나리오 테마 전달
        provider: ai_service.AIImageProvider.stableDiffusion,
      );

      setState(() {
        _imageUrl = content['imageUrl'] ?? 'https://picsum.photos/1024/1024';
        _nativePrompt = scenarioData['prompt'];
        _keywords = scenarioData['keywords'];
        _correctSentence = scenarioData['sentence'];
        _isLoading = false;
      });

      // 페이드인 애니메이션
      _fadeController.forward();
    } catch (e) {
      print('Error loading scene: $e');
      setState(() {
        _isLoading = false;
        // 폴백 데이터 사용
        _imageUrl = 'https://picsum.photos/1024/1024?random=${DateTime.now().millisecondsSinceEpoch}';
      });
    }
  }

  // 시나리오별 데이터
  Map<String, dynamic> _getScenarioData(String scenario) {
    final data = {
      'street': {
        'prompt': 'Look at this busy street scene!',
        'keywords': ['street', 'people'],
        'sentence': 'The street is busy with people and cars',
      },
      'restaurant': {
        'prompt': 'What do you see in this restaurant?',
        'keywords': ['eating', 'waiter'],
        'sentence': 'People are eating and the waiter is serving',
      },
      'park': {
        'prompt': 'Describe what\'s happening in the park!',
        'keywords': ['trees', 'playing'],
        'sentence': 'Children are playing under the trees',
      },
      'office': {
        'prompt': 'Tell me about this office scene.',
        'keywords': ['working', 'computer'],
        'sentence': 'Everyone is working at their computers',
      },
      'home': {
        'prompt': 'What\'s happening in this home?',
        'keywords': ['family', 'dinner'],
        'sentence': 'The family is having dinner together',
      },
    };
    
    return data[scenario] ?? data['street']!;
  }

  // 음성 인식 토글
  void _toggleListening() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (status) {
          print('Status: $status');
          if (status == 'done') {
            setState(() => _isListening = false);
            _evaluateSpeech();
          }
        },
        onError: (error) => print('Error: $error'),
      );

      if (available) {
        setState(() => _isListening = true);
        
        _speech.listen(
          onResult: (result) {
            setState(() {
              _userSpeech = result.recognizedWords;
              _checkKeywords(result.recognizedWords);
            });
          },
          onSoundLevelChange: (level) {
            setState(() {
              _audioLevel = level / 10; // Normalize audio level
            });
          },
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
      _evaluateSpeech();
    }
  }

  // 키워드 체크
  void _checkKeywords(String speech) {
    final spokenWords = speech.toLowerCase().split(' ');
    
    for (String keyword in _keywords) {
      if (spokenWords.any((word) => word.contains(keyword.toLowerCase()))) {
        setState(() {
          _matchedWords[keyword] = true;
        });
      }
    }
  }

  // 발화 평가
  void _evaluateSpeech() {
    int matchedCount = _matchedWords.values.where((v) => v).length;
    int newScore = (matchedCount / _keywords.length * 100).round();
    
    setState(() {
      _score = newScore;
    });

    // 피드백 표시
    String feedback;
    Color feedbackColor;
    
    if (newScore >= 80) {
      feedback = 'Excellent! 🎉';
      feedbackColor = Colors.green;
    } else if (newScore >= 50) {
      feedback = 'Good try! 👍';
      feedbackColor = Colors.orange;
    } else {
      feedback = 'Keep practicing! 💪';
      feedbackColor = Colors.blue;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(feedback),
        backgroundColor: feedbackColor,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        children: [
          // 배경 이미지
          _buildBackgroundImage(),
          
          // 그라데이션 오버레이
          _buildGradientOverlay(),
          
          // 메인 콘텐츠
          if (!_isLoading) ...[
            // 상단: 원어민 프롬프트
            _buildNativePrompt(),
            
            // 중앙: 키워드 표시
            _buildKeywords(),
            
            // 하단: 음성 인식 UI
            _buildVoiceControls(),
            
            // 사용자 발화 표시
            if (_userSpeech.isNotEmpty) _buildUserSpeech(),
          ],
          
          // 로딩 인디케이터
          if (_isLoading) _buildLoadingIndicator(),
          
          // 상단 툴바
          _buildTopBar(),
        ],
      ),
    );
  }

  Widget _buildBackgroundImage() {
    return AnimatedOpacity(
      duration: Duration(milliseconds: 500),
      opacity: _imageUrl.isNotEmpty ? 1.0 : 0.0,
      child: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: NetworkImage(_imageUrl),
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  Widget _buildGradientOverlay() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.8),
            Colors.transparent,
            Colors.black.withOpacity(0.9),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
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
              icon: Icon(Icons.arrow_back, color: Colors.white),
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
              icon: Icon(Icons.refresh, color: Colors.white),
              onPressed: _loadNewScene,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNativePrompt() {
    return Positioned(
      top: 120,
      left: 20,
      right: 20,
      child: FadeTransition(
        opacity: _fadeController,
        child: Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
            backdropFilter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🎯 Listen and describe:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              SizedBox(height: 8),
              Text(
                _nativePrompt,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeywords() {
    return Center(
      child: Wrap(
        spacing: 20,
        children: _keywords.map((keyword) {
          final isMatched = _matchedWords[keyword] ?? false;
          
          return AnimatedBuilder(
            animation: _pulseController,
            builder: (context, child) {
              return Transform.scale(
                scale: isMatched ? 1.0 : 0.9 + (_pulseController.value * 0.1),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  decoration: BoxDecoration(
                    color: isMatched
                        ? Colors.green.withOpacity(0.3)
                        : Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                      color: isMatched ? Colors.green : Colors.white54,
                      width: 2,
                    ),
                    boxShadow: [
                      if (isMatched)
                        BoxShadow(
                          color: Colors.green.withOpacity(0.5),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isMatched)
                        Icon(Icons.check_circle, color: Colors.green, size: 20),
                      if (isMatched) SizedBox(width: 8),
                      Text(
                        keyword,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildVoiceControls() {
    return Positioned(
      bottom: 80,
      left: 0,
      right: 0,
      child: Column(
        children: [
          // 음성 레벨 인디케이터
          if (_isListening)
            Container(
              height: 40,
              margin: EdgeInsets.symmetric(horizontal: 60),
              child: AnimatedContainer(
                duration: Duration(milliseconds: 100),
                height: _audioLevel * 40,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue, Colors.blueAccent],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          
          SizedBox(height: 30),
          
          // 마이크 버튼
          GestureDetector(
            onTap: _toggleListening,
            child: AnimatedContainer(
              duration: Duration(milliseconds: 300),
              width: _isListening ? 100 : 80,
              height: _isListening ? 100 : 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: _isListening
                      ? [Colors.red, Colors.redAccent]
                      : [Colors.blue, Colors.blueAccent],
                ),
                boxShadow: [
                  BoxShadow(
                    color: (_isListening ? Colors.red : Colors.blue)
                        .withOpacity(0.5),
                    blurRadius: 30,
                    spreadRadius: 10,
                  ),
                ],
              ),
              child: Icon(
                _isListening ? Icons.stop : Icons.mic,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
          
          SizedBox(height: 16),
          
          Text(
            _isListening ? 'Listening...' : 'Tap to speak',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserSpeech() {
    return Positioned(
      bottom: 280,
      left: 20,
      right: 20,
      child: AnimatedOpacity(
        duration: Duration(milliseconds: 300),
        opacity: _userSpeech.isNotEmpty ? 1.0 : 0.0,
        child: Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You said:',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
              ),
              SizedBox(height: 4),
              Text(
                _userSpeech,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Colors.white),
          SizedBox(height: 16),
          Text(
            'Generating scene...',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _fadeController.dispose();
    _speech.stop();
    super.dispose();
  }
}