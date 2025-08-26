import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:animated_text_kit/animated_text_kit.dart';
import '../services/image_generation_service.dart' as ai_service;

class TrainingScreen extends StatefulWidget {
  @override
  _TrainingScreenState createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  // 서비스
  final ai_service.ImageGenerationService _imageService = ai_service.ImageGenerationService();
  
  // 음성 인식
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _userSpeech = '';
  double _confidence = 0.0;
  
  // 학습 데이터
  String _imageUrl = '';
  List<String> _keywords = [];
  String _correctSentence = '';
  List<String> _revealedWords = [];
  String _currentLevel = 'beginner';
  bool _isLoading = false;
  
  // 채점
  int _score = 0;
  Map<String, bool> _matchedWords = {};
  Map<String, dynamic>? _evaluationResult;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _loadNewScene();
  }

  // 새로운 장면 로드 (API 연동)
  Future<void> _loadNewScene() async {
    setState(() {
      _isLoading = true;
      _revealedWords = [];
      _matchedWords = {};
      _score = 0;
      _evaluationResult = null;
    });

    try {
      // API를 통해 학습 콘텐츠 생성
      final content = await _imageService.generateLearningContent(
        level: _currentLevel,
        userId: 'test_user', // 실제로는 로그인한 사용자 ID
        isPremium: false, // 실제로는 구독 상태 확인
        provider: ai_service.AIImageProvider.fallback, // 테스트용으로 fallback 사용
      );

      setState(() {
        _imageUrl = content['imageUrl'] ?? '';
        _correctSentence = content['sentence'] ?? '';
        _keywords = List<String>.from(content['keywords'] ?? []);
        _isLoading = false;
      });

      // 디버그 출력
      print('Loaded scene - Image: $_imageUrl');
      print('Sentence: $_correctSentence');
      print('Keywords: $_keywords');
    } catch (e) {
      print('Error loading scene: $e');
      setState(() {
        _isLoading = false;
        // 폴백 데이터
        _imageUrl = 'https://picsum.photos/400/250';
        _keywords = ['running', 'park', 'sunny'];
        _correctSentence = 'A man is running in the park on a sunny day';
      });
    }
  }

  // 음성 인식 시작/중지
  void _toggleListening() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) => print('onStatus: $val'),
        onError: (val) => print('onError: $val'),
      );
      
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) => setState(() {
            _userSpeech = val.recognizedWords;
            _confidence = val.confidence;
            _checkKeywords(val.recognizedWords);
          }),
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
      _evaluatePronunciation();
    }
  }

  // 키워드 체크
  void _checkKeywords(String speech) {
    final spokenWords = speech.toLowerCase().split(' ');
    
    for (String keyword in _keywords) {
      if (spokenWords.contains(keyword.toLowerCase())) {
        setState(() {
          _matchedWords[keyword] = true;
          if (!_revealedWords.contains(keyword)) {
            _revealedWords.add(keyword);
            _score += 10;
          }
        });
      }
    }
  }

  // 발음 평가 (API 연동)
  Future<void> _evaluatePronunciation() async {
    if (_userSpeech.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final evaluation = await _imageService.evaluatePronunciation(
        userSpeech: _userSpeech,
        correctSentence: _correctSentence,
        keywords: _keywords,
      );

      setState(() {
        _evaluationResult = evaluation;
        _score = evaluation['overall_score'] ?? _score;
        _isLoading = false;
      });

      _showFeedbackDialog(evaluation);
    } catch (e) {
      print('Error evaluating pronunciation: $e');
      setState(() => _isLoading = false);
      
      // 간단한 폴백 평가
      _showFeedbackDialog({
        'overall_score': _score,
        'feedback': 'Good effort! Keep practicing!',
        'improvement_tips': ['Speak more clearly', 'Try to match the sentence structure'],
      });
    }
  }

  // 피드백 다이얼로그
  void _showFeedbackDialog(Map<String, dynamic> evaluation) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        final score = evaluation['overall_score'] ?? 0;
        final feedback = evaluation['feedback'] ?? 'Keep practicing!';
        final tips = List<String>.from(evaluation['improvement_tips'] ?? []);

        return AlertDialog(
          title: Text(
            'Score: $score/100',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: score >= 70 ? Colors.green : Colors.orange,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                feedback,
                style: TextStyle(fontSize: 16),
              ),
              if (tips.isNotEmpty) ...[
                SizedBox(height: 16),
                Text(
                  'Tips for improvement:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                ...tips.map((tip) => Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ', style: TextStyle(fontSize: 14)),
                      Expanded(
                        child: Text(tip, style: TextStyle(fontSize: 14)),
                      ),
                    ],
                  ),
                )),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _loadNewScene(); // 새로운 장면 로드
              },
              child: Text('Next'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _userSpeech = '';
                  _matchedWords = {};
                  _revealedWords = [];
                  _score = 0;
                });
              },
              child: Text('Try Again'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Visual Speaking Practice',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          // 레벨 선택
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                _currentLevel = value;
              });
              _loadNewScene();
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'beginner', child: Text('Beginner')),
              PopupMenuItem(value: 'intermediate', child: Text('Intermediate')),
              PopupMenuItem(value: 'advanced', child: Text('Advanced')),
            ],
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.signal_cellular_alt, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    _currentLevel.substring(0, 1).toUpperCase() + 
                    _currentLevel.substring(1),
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: _isLoading 
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: Colors.blue),
                SizedBox(height: 16),
                Text(
                  'Generating learning content...',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          )
        : SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              // AI 생성 이미지
              Container(
                height: 250,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white.withAlpha(25),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _imageUrl.isNotEmpty 
                    ? Image.network(
                        _imageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Center(
                            child: CircularProgressIndicator(
                              value: loadingProgress.expectedTotalBytes != null
                                ? loadingProgress.cumulativeBytesLoaded /
                                    loadingProgress.expectedTotalBytes!
                                : null,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.broken_image, 
                                     color: Colors.white54, size: 48),
                                Text('Failed to load image',
                                     style: TextStyle(color: Colors.white54)),
                              ],
                            ),
                          );
                        },
                      )
                    : Center(
                        child: Icon(
                          Icons.image,
                          size: 48,
                          color: Colors.white.withAlpha(76),
                        ),
                      ),
                ),
              ),
              
              SizedBox(height: 24),
              
              // 핵심 단어들
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withAlpha(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Keywords to include:',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: _keywords.map((word) {
                        final isMatched = _matchedWords[word] ?? false;
                        return Chip(
                          label: Text(word),
                          backgroundColor: isMatched 
                            ? Colors.green.withAlpha(76)
                            : Colors.blue.withAlpha(76),
                          labelStyle: TextStyle(
                            color: isMatched ? Colors.greenAccent : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 24),
              
              // 점진적으로 공개되는 문장
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withAlpha(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sentence hint:',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      _getRevealedSentence(),
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              
              SizedBox(height: 24),
              
              // 사용자 음성 텍스트
              if (_userSpeech.isNotEmpty)
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.purple.withAlpha(25),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'You said:',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 8),
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
              
              SizedBox(height: 32),
              
              // 점수
              Text(
                'Score: $_score',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              SizedBox(height: 32),
              
              // 마이크 버튼
              GestureDetector(
                onTap: _toggleListening,
                child: Container(
                  width: 80,
                  height: 80,
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
                            .withAlpha(76),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isListening ? Icons.mic : Icons.mic_none,
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

              // 새 장면 버튼
              SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _loadNewScene,
                icon: Icon(Icons.refresh),
                label: Text('New Scene'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.withAlpha(76),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
        ),
    );
  }

  String _getRevealedSentence() {
    if (_revealedWords.isEmpty) {
      return _correctSentence.split(' ').map((_) => '___').join(' ');
    }
    
    List<String> words = _correctSentence.split(' ');
    List<String> result = [];
    
    for (String word in words) {
      bool revealed = false;
      for (String revealedWord in _revealedWords) {
        if (word.toLowerCase().contains(revealedWord.toLowerCase())) {
          revealed = true;
          break;
        }
      }
      result.add(revealed ? word : '___');
    }
    
    return result.join(' ');
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }
}