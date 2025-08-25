import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:animated_text_kit/animated_text_kit.dart';

class TrainingScreen extends StatefulWidget {
  @override
  _TrainingScreenState createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
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
  
  // 채점
  int _score = 0;
  Map<String, bool> _matchedWords = {};

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _loadNewScene();
  }

  // 새로운 장면 로드
  void _loadNewScene() {
    setState(() {
      // AI 생성 이미지 URL (실제로는 API 호출)
      _imageUrl = 'https://picsum.photos/400/250';
      
      // 핵심 단어들
      _keywords = ['running', 'park', 'sunny'];
      
      // 정답 문장
      _correctSentence = 'A man is running in the park on a sunny day';
      
      // 초기화
      _revealedWords = [];
      _matchedWords = {};
      _score = 0;
    });
  }

  // 음성 인식 시작
  void _startListening() async {
    bool available = await _speech.initialize(
      onStatus: (status) => print('Status: $status'),
      onError: (error) => print('Error: $error'),
    );
    
    if (available) {
      setState(() => _isListening = true);
      
      _speech.listen(
        onResult: (result) {
          setState(() {
            _userSpeech = result.recognizedWords;
            _confidence = result.confidence;
          });
          
          // 실시간 분석
          _analyzeUserSpeech(result.recognizedWords);
        },
        listenFor: Duration(seconds: 30),
        pauseFor: Duration(seconds: 3),
      );
    }
  }

  // 사용자 음성 분석
  void _analyzeUserSpeech(String speech) {
    final userWords = speech.toLowerCase().split(' ');
    final correctWords = _correctSentence.toLowerCase().split(' ');
    
    setState(() {
      // 키워드 매칭 체크
      for (String keyword in _keywords) {
        if (userWords.contains(keyword.toLowerCase())) {
          _matchedWords[keyword] = true;
          _score += 10;
        }
      }
      
      // 정답 문장 점진적 공개
      for (int i = 0; i < correctWords.length; i++) {
        if (userWords.contains(correctWords[i]) && 
            !_revealedWords.contains(correctWords[i])) {
          _revealedWords.add(correctWords[i]);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1E1E2E),
      body: SafeArea(
        child: Column(
          children: [
            // 점수 표시
            _buildScoreBar(),
            
            // AI 생성 이미지
            _buildSceneImage(),
            
            // 키워드 팝업
            _buildKeywordChips(),
            
            // "Think and Speak!" 프롬프트
            _buildPrompt(),
            
            // 사용자 음성 텍스트
            _buildUserSpeechDisplay(),
            
            // 정답 문장 (점진적 공개)
            _buildRevealingSentence(),
            
            // 녹음 버튼
            _buildRecordButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreBar() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Score', style: TextStyle(color: Colors.white70)),
          AnimatedContainer(
            duration: Duration(milliseconds: 500),
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$_score',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSceneImage() {
    return Container(
      height: 250,
      margin: EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              _imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: Colors.grey[800],
                  child: Icon(Icons.image, size: 50, color: Colors.white30),
                );
              },
            ),
            // 그라데이션 오버레이
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.3),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeywordChips() {
    return Container(
      height: 50,
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _keywords.length,
        itemBuilder: (context, index) {
          final keyword = _keywords[index];
          final isMatched = _matchedWords[keyword] ?? false;
          
          return AnimatedContainer(
            duration: Duration(milliseconds: 300),
            margin: EdgeInsets.only(right: 10),
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isMatched ? Colors.blue : Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isMatched ? Colors.blue : Colors.white30,
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                keyword,
                style: TextStyle(
                  color: isMatched ? Colors.white : Colors.white70,
                  fontWeight: isMatched ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPrompt() {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 20),
      child: AnimatedTextKit(
        animatedTexts: [
          TypewriterAnimatedText(
            'Think and describe the scene!',
            textStyle: TextStyle(
              fontSize: 20,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
            speed: Duration(milliseconds: 100),
          ),
        ],
        repeatForever: true,
        pause: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildUserSpeechDisplay() {
    if (_userSpeech.isEmpty) return SizedBox(height: 40);
    
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Text(
        _userSpeech,
        style: TextStyle(
          color: Colors.white70,
          fontSize: 16,
          height: 1.5,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildRevealingSentence() {
    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF2D2D3F).withOpacity(0.5),
            Color(0xFF1E1E2E).withOpacity(0.5),
          ],
        ),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: TextStyle(fontSize: 18, height: 1.5),
          children: _correctSentence.split(' ').map((word) {
            final isRevealed = _revealedWords.contains(word.toLowerCase());
            return TextSpan(
              text: word + ' ',
              style: TextStyle(
                color: isRevealed 
                  ? Colors.blue 
                  : Colors.white.withOpacity(0.1),
                fontWeight: isRevealed ? FontWeight.bold : FontWeight.normal,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildRecordButton() {
    return GestureDetector(
      onTap: _isListening ? _stopListening : _startListening,
      child: Container(
        width: 80,
        height: 80,
        margin: EdgeInsets.only(bottom: 30),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: _isListening 
              ? [Colors.red, Colors.redAccent]
              : [Color(0xFF6366F1), Color(0xFF8B5CF6)],
          ),
          boxShadow: [
            BoxShadow(
              color: _isListening 
                ? Colors.red.withOpacity(0.3)
                : Color(0xFF6366F1).withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Icon(
          _isListening ? Icons.stop : Icons.mic,
          color: Colors.white,
          size: 35,
        ),
      ),
    );
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
    
    // 최종 점수 계산 및 피드백
    _showFeedback();
  }

  void _showFeedback() {
    // 피드백 모달 표시
    showModalBottomSheet(
      context: context,
      backgroundColor: Color(0xFF2D2D3F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _score >= 70 ? 'Excellent!' : 'Good Try!',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Your Score: $_score/100',
              style: TextStyle(color: Colors.white70, fontSize: 18),
            ),
            SizedBox(height: 30),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _loadNewScene();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF6366F1),
                padding: EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: Text('Next Scene', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}