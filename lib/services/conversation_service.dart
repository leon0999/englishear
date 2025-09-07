import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'openai_service_simple.dart';
import '../core/logger.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

// 대화 턴 모델
class ConversationTurn {
  final String speaker; // 'ai' or 'user'
  final String originalText;
  final String? improvedText; // Upgrade Replay 시 개선된 텍스트
  final DateTime timestamp;
  final Map<String, dynamic>? analysis; // 분석 결과

  ConversationTurn({
    required this.speaker,
    required this.originalText,
    this.improvedText,
    required this.timestamp,
    this.analysis,
  });

  Map<String, dynamic> toJson() => {
    'speaker': speaker,
    'originalText': originalText,
    'improvedText': improvedText,
    'timestamp': timestamp.toIso8601String(),
    'analysis': analysis,
  };
}

// 대화 세션 모델
class ConversationSession {
  final String id;
  final DateTime startTime;
  DateTime? endTime;
  final List<ConversationTurn> turns;
  final String scenario;
  Map<String, dynamic>? finalReport;
  bool isReplayed = false;

  ConversationSession({
    required this.id,
    required this.startTime,
    required this.scenario,
    this.endTime,
    List<ConversationTurn>? turns,
    this.finalReport,
  }) : turns = turns ?? [];

  int get userTurnCount => turns.where((t) => t.speaker == 'user').length;
  bool get canReplay => userTurnCount >= 6 && !isReplayed;
}

class ConversationService extends ChangeNotifier {
  final OpenAIServiceSimple _openAI = OpenAIServiceSimple();
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _stt = stt.SpeechToText();
  
  ConversationSession? _currentSession;
  bool _isListening = false;
  bool _isSpeaking = false;
  String _currentTranscript = '';
  
  ConversationSession? get currentSession => _currentSession;
  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  String get currentTranscript => _currentTranscript;

  ConversationService() {
    _initializeTTS();
    _initializeSTT();
  }

  // TTS 초기화 - 고품질 음성 설정
  Future<void> _initializeTTS() async {
    try {
      // iOS/macOS 고품질 음성 설정
      if (defaultTargetPlatform == TargetPlatform.iOS || 
          defaultTargetPlatform == TargetPlatform.macOS) {
        await _tts.setVoice({'name': 'Samantha', 'locale': 'en-US'});
      } else {
        // Android/Web 설정
        await _tts.setLanguage('en-US');
        await _tts.setVoice({'locale': 'en-US'});
      }
      
      await _tts.setSpeechRate(0.52); // 자연스러운 속도
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      
      // TTS 완료 콜백
      _tts.setCompletionHandler(() {
        _isSpeaking = false;
        notifyListeners();
      });
      
      Logger.info('TTS initialized successfully');
    } catch (e) {
      Logger.error('Failed to initialize TTS', error: e);
    }
  }

  // STT 초기화
  Future<void> _initializeSTT() async {
    try {
      bool available = await _stt.initialize(
        onStatus: (status) {
          Logger.debug('STT Status: $status');
        },
        onError: (error) {
          Logger.error('STT Error', error: error);
          _isListening = false;
          notifyListeners();
        },
      );
      
      if (available) {
        Logger.info('STT initialized successfully');
      } else {
        Logger.warning('STT not available');
      }
    } catch (e) {
      Logger.error('Failed to initialize STT', error: e);
    }
  }

  // 새 대화 세션 시작
  Future<void> startNewConversation() async {
    try {
      // 랜덤 시나리오 생성
      final scenarios = [
        'At a coffee shop ordering drinks',
        'Asking for directions in a new city',
        'Job interview for a tech company',
        'Making a hotel reservation',
        'Discussing weekend plans with a friend',
        'Shopping for clothes at a store',
        'Ordering food at a restaurant',
        'At the airport check-in counter',
        'Meeting a new colleague at work',
        'Calling customer service for help',
        'At the doctor\'s office',
        'Renting an apartment',
        'Planning a vacation trip',
        'At the gym with a personal trainer',
        'Small talk at a party',
      ];
      
      final scenario = scenarios[Random().nextInt(scenarios.length)];
      
      _currentSession = ConversationSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        startTime: DateTime.now(),
        scenario: scenario,
      );
      
      // AI가 먼저 대화 시작
      final openingLine = await _generateAIOpening(scenario);
      
      _currentSession!.turns.add(ConversationTurn(
        speaker: 'ai',
        originalText: openingLine,
        timestamp: DateTime.now(),
      ));
      
      // AI 음성으로 말하기
      await speakText(openingLine);
      
      notifyListeners();
      Logger.info('New conversation started: $scenario');
      
    } catch (e) {
      Logger.error('Failed to start conversation', error: e);
      rethrow;
    }
  }

  // AI 오프닝 대사 생성
  Future<String> _generateAIOpening(String scenario) async {
    try {
      final response = await _openAI.getAITutorResponse(
        userMessage: '',
        context: '''You are in this scenario: $scenario
        Start a natural conversation as if you are really in that situation.
        Keep it friendly, casual, and realistic. 
        Your opening line should be 1-2 sentences max.
        Do NOT mention that this is practice or learning.
        Be the character in the scenario naturally.''',
      );
      
      return response;
    } catch (e) {
      Logger.error('Failed to generate AI opening', error: e);
      // Fallback opening
      return _getFallbackOpening(scenario);
    }
  }

  // Fallback 오프닝 (API 실패 시)
  String _getFallbackOpening(String scenario) {
    final fallbacks = {
      'coffee shop': 'Hi! What can I get started for you today?',
      'directions': 'Excuse me, you look lost. Can I help you find something?',
      'job interview': 'Good morning! Thanks for coming in today. How was your journey here?',
      'hotel': 'Good evening! Welcome to Grand Hotel. Do you have a reservation?',
      'weekend plans': 'Hey! Do you have any plans for this weekend?',
    };
    
    for (var key in fallbacks.keys) {
      if (scenario.toLowerCase().contains(key)) {
        return fallbacks[key]!;
      }
    }
    
    return 'Hello! How are you doing today?';
  }

  // 음성 인식 시작/중지
  Future<void> toggleListening() async {
    if (_isListening) {
      await stopListening();
    } else {
      await startListening();
    }
  }

  // 음성 인식 시작
  Future<void> startListening() async {
    try {
      _currentTranscript = '';
      _isListening = true;
      notifyListeners();
      
      await _stt.listen(
        onResult: (result) {
          _currentTranscript = result.recognizedWords;
          notifyListeners();
          
          if (result.finalResult) {
            _processUserInput(result.recognizedWords);
          }
        },
        localeId: 'en_US',
        cancelOnError: true,
      );
      
      Logger.info('Started listening');
    } catch (e) {
      Logger.error('Failed to start listening', error: e);
      _isListening = false;
      notifyListeners();
    }
  }

  // 음성 인식 중지
  Future<void> stopListening() async {
    try {
      await _stt.stop();
      _isListening = false;
      notifyListeners();
      Logger.info('Stopped listening');
    } catch (e) {
      Logger.error('Failed to stop listening', error: e);
    }
  }

  // 사용자 입력 처리
  Future<void> _processUserInput(String userText) async {
    if (userText.trim().isEmpty || _currentSession == null) return;
    
    try {
      // 사용자 턴 추가
      _currentSession!.turns.add(ConversationTurn(
        speaker: 'user',
        originalText: userText,
        timestamp: DateTime.now(),
      ));
      
      notifyListeners();
      
      // AI 응답 생성
      final aiResponse = await _generateAIResponse(userText);
      
      // AI 턴 추가
      _currentSession!.turns.add(ConversationTurn(
        speaker: 'ai',
        originalText: aiResponse,
        timestamp: DateTime.now(),
      ));
      
      // AI 음성으로 말하기
      await speakText(aiResponse);
      
      notifyListeners();
      
    } catch (e) {
      Logger.error('Failed to process user input', error: e);
    }
  }

  // AI 응답 생성
  Future<String> _generateAIResponse(String userText) async {
    try {
      // 대화 컨텍스트 구성
      final conversationContext = _buildConversationContext();
      
      final response = await _openAI.getAITutorResponse(
        userMessage: userText,
        context: '''Scenario: ${_currentSession!.scenario}
        
        Continue this natural conversation. You are the character in the scenario.
        Respond naturally and realistically to what the user just said.
        Keep your response 1-2 sentences, natural and conversational.
        Do NOT correct grammar or pronunciation - just continue the conversation.
        
        Previous conversation:
        $conversationContext''',
      );
      
      return response;
    } catch (e) {
      Logger.error('Failed to generate AI response', error: e);
      return "I'm sorry, could you repeat that?";
    }
  }

  // 대화 컨텍스트 구성
  String _buildConversationContext() {
    if (_currentSession == null) return '';
    
    // 최근 6턴만 컨텍스트로 사용
    final recentTurns = _currentSession!.turns.take(6);
    return recentTurns.map((turn) => 
      '${turn.speaker == 'ai' ? 'Assistant' : 'User'}: ${turn.originalText}'
    ).join('\n');
  }

  // TTS로 텍스트 말하기
  Future<void> speakText(String text) async {
    // 빈 문자열 체크
    if (text == null || text.trim().isEmpty) {
      Logger.warning('TTS skipped - empty text');
      return;
    }
    
    try {
      _isSpeaking = true;
      notifyListeners();
      
      await _tts.speak(text);
      Logger.debug('Speaking: $text');
      
    } catch (e) {
      Logger.error('Failed to speak text', error: e);
      _isSpeaking = false;
      notifyListeners();
    }
  }

  // Upgrade Replay 실행
  Future<void> executeUpgradeReplay() async {
    if (_currentSession == null || !_currentSession!.canReplay) {
      throw Exception('Cannot replay this session');
    }
    
    try {
      Logger.info('Starting Upgrade Replay');
      
      // 1. 사용자 대화 개선
      final improvedTurns = await _improveUserTurns();
      
      // 2. 개선된 대화 재생
      await _replayImprovedConversation(improvedTurns);
      
      // 3. 최종 리포트 생성
      final report = await _generateFinalReport(improvedTurns);
      
      _currentSession!.finalReport = report;
      _currentSession!.isReplayed = true;
      
      // 4. 리포트 음성으로 읽어주기
      await speakText(report['summary'] as String);
      
      notifyListeners();
      Logger.info('Upgrade Replay completed');
      
    } catch (e) {
      Logger.error('Failed to execute Upgrade Replay', error: e);
      rethrow;
    }
  }

  // 사용자 턴 개선
  Future<List<ConversationTurn>> _improveUserTurns() async {
    final improvedTurns = <ConversationTurn>[];
    
    for (var turn in _currentSession!.turns) {
      if (turn.speaker == 'user') {
        final improved = await _improveUserText(turn.originalText);
        improvedTurns.add(ConversationTurn(
          speaker: turn.speaker,
          originalText: turn.originalText,
          improvedText: improved['improvedText'],
          timestamp: turn.timestamp,
          analysis: improved,
        ));
      } else {
        improvedTurns.add(turn);
      }
    }
    
    return improvedTurns;
  }

  // 개별 사용자 텍스트 개선
  Future<Map<String, dynamic>> _improveUserText(String originalText) async {
    try {
      final response = await _openAI.getAITutorResponse(
        userMessage: originalText,
        context: '''Improve this English sentence to sound more natural and native.
        Keep the same meaning but make it grammatically perfect and more fluent.
        
        Original: "$originalText"
        
        Return JSON format:
        {
          "improvedText": "the improved version",
          "changes": ["change 1", "change 2"],
          "grammarNotes": "brief explanation"
        }''',
      );
      
      // Parse response (간단한 처리)
      return {
        'improvedText': response,
        'changes': ['Grammar corrected', 'More natural phrasing'],
        'grammarNotes': 'Improved for native-like expression',
      };
      
    } catch (e) {
      Logger.error('Failed to improve user text', error: e);
      return {
        'improvedText': originalText,
        'changes': [],
        'grammarNotes': 'No changes needed',
      };
    }
  }

  // 개선된 대화 재생
  Future<void> _replayImprovedConversation(List<ConversationTurn> improvedTurns) async {
    for (var turn in improvedTurns) {
      final textToSpeak = turn.speaker == 'user' 
        ? (turn.improvedText ?? turn.originalText)
        : turn.originalText;
      
      await speakText(textToSpeak);
      
      // 턴 사이 짧은 대기
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  // 최종 리포트 생성
  Future<Map<String, dynamic>> _generateFinalReport(List<ConversationTurn> improvedTurns) async {
    try {
      final userTurns = improvedTurns.where((t) => t.speaker == 'user').toList();
      
      final improvements = userTurns.map((t) => {
        'original': t.originalText,
        'improved': t.improvedText,
        'analysis': t.analysis,
      }).toList();
      
      final summary = '''Great job completing this conversation! 
      You successfully engaged in ${userTurns.length} turns of natural dialogue.
      Your speaking showed good effort, and with the improvements shown, 
      you're on your way to sounding more natural and fluent.
      Keep practicing daily to build your confidence!''';
      
      return {
        'summary': summary,
        'totalTurns': _currentSession!.turns.length,
        'userTurns': userTurns.length,
        'improvements': improvements,
        'scenario': _currentSession!.scenario,
        'duration': DateTime.now().difference(_currentSession!.startTime).inSeconds,
      };
      
    } catch (e) {
      Logger.error('Failed to generate final report', error: e);
      return {
        'summary': 'Great practice session! Keep up the good work.',
        'totalTurns': _currentSession!.turns.length,
      };
    }
  }

  @override
  void dispose() {
    _tts.stop();
    _stt.stop();
    super.dispose();
  }
}