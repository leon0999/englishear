// lib/services/voice_conversation_service.dart

import 'dart:convert';
import 'dart:async';
import 'dart:html' as html;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

// 대화 턴 모델
class ConversationTurn {
  final String speaker; // 'AI' or 'User'
  final String text;
  final DateTime timestamp;
  final String? improvedVersion; // Upgrade Replay시 개선된 버전

  ConversationTurn({
    required this.speaker,
    required this.text,
    required this.timestamp,
    this.improvedVersion,
  });

  Map<String, dynamic> toJson() => {
    'speaker': speaker,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
    'improvedVersion': improvedVersion,
  };
}

// 시나리오 모델
class ConversationScenario {
  final String title;
  final String description;
  final String context;
  final String openingLine;

  ConversationScenario({
    required this.title,
    required this.description,
    required this.context,
    required this.openingLine,
  });
}

class VoiceConversationService {
  late final Dio _dio;
  late final String _apiKey;
  final stt.SpeechToText speechToText = stt.SpeechToText();
  
  List<ConversationTurn> conversationHistory = [];
  ConversationScenario? currentScenario;
  int turnCount = 0;
  bool isListening = false;
  bool isProcessing = false;
  
  // 음성 목록
  static const List<String> aiVoices = ['nova', 'alloy', 'echo', 'fable', 'onyx', 'shimmer'];
  String currentAIVoice = 'nova';
  
  // 콜백
  Function(String)? onAISpeaking;
  Function(String)? onUserSpeaking;
  Function(bool)? onListeningStateChanged;
  Function()? onConversationEnd;
  Function(String)? onError;
  
  VoiceConversationService() {
    _apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
    _dio = Dio(BaseOptions(
      baseUrl: 'https://api.openai.com/v1',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
    ));
  }
  
  // 1. 대화 시작 - GPT가 상황 설정하고 먼저 말걸기
  Future<void> startConversation() async {
    try {
      // 초기화
      conversationHistory.clear();
      turnCount = 0;
      
      // 랜덤 시나리오 생성
      currentScenario = await _generateRandomScenario();
      print('🎭 Scenario: ${currentScenario!.title}');
      print('📝 Context: ${currentScenario!.description}');
      
      // 랜덤 음성 선택
      currentAIVoice = aiVoices[math.Random().nextInt(aiVoices.length)];
      
      // GPT 첫 인사 (시나리오 기반)
      final firstMessage = currentScenario!.openingLine;
      
      // 대화 기록에 추가
      conversationHistory.add(ConversationTurn(
        speaker: 'AI',
        text: firstMessage,
        timestamp: DateTime.now(),
      ));
      
      // 고품질 음성으로 재생
      await _speakWithPremiumVoice(firstMessage);
      
      // 사용자 음성 인식 시작
      await _startListening();
      
    } catch (e) {
      print('❌ Error starting conversation: $e');
      onError?.call('Failed to start conversation: $e');
    }
  }
  
  // 2. 랜덤 시나리오 생성 (개선된 버전)
  Future<ConversationScenario> _generateRandomScenario() async {
    try {
      final response = await _dio.post(
        '/chat/completions',
        data: {
          'model': 'gpt-4-turbo-preview',
          'messages': [
            {
              'role': 'system',
              'content': '''You're creating realistic conversation scenarios for English practice.
              Generate a specific, interesting everyday situation where two people might talk.
              Make it natural and engaging.
              
              Examples:
              - Ordering coffee with dietary restrictions
              - Asking for tech support about slow wifi
              - Chatting with a colleague about weekend plans
              - Returning an item at a store
              - Making small talk in an elevator
              - Discussing a movie with a friend
              
              Return JSON format:
              {
                "title": "short title",
                "description": "2-3 sentence context",
                "context": "your role and personality for this conversation",
                "openingLine": "natural first line to start the conversation"
              }'''
            },
            {
              'role': 'user',
              'content': 'Generate a random everyday conversation scenario.'
            }
          ],
          'temperature': 0.9,
          'response_format': {'type': 'json_object'},
        },
      );
      
      final content = response.data['choices'][0]['message']['content'];
      final json = jsonDecode(content);
      
      return ConversationScenario(
        title: json['title'] ?? 'Casual Chat',
        description: json['description'] ?? 'A friendly conversation',
        context: json['context'] ?? 'You are having a casual conversation',
        openingLine: json['openingLine'] ?? 'Hey! How are you doing today?',
      );
      
    } catch (e) {
      print('Error generating scenario: $e');
      // 폴백 시나리오
      return ConversationScenario(
        title: 'Coffee Shop',
        description: 'You\'re a barista at a busy coffee shop.',
        context: 'Friendly barista taking orders and making small talk',
        openingLine: 'Good morning! What can I get started for you today?',
      );
    }
  }
  
  // 3. 고품질 음성 출력 (OpenAI TTS HD)
  Future<void> _speakWithPremiumVoice(String text) async {
    try {
      onAISpeaking?.call(text);
      
      final response = await _dio.post(
        '/audio/speech',
        options: Options(responseType: ResponseType.bytes),
        data: {
          'model': 'tts-1-hd',
          'voice': currentAIVoice,
          'input': text,
          'speed': 0.95,
        },
      );
      
      if (kIsWeb) {
        // 웹에서 재생
        final bytes = response.data;
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        
        final audio = html.AudioElement()
          ..src = url
          ..autoplay = false;
        
        await audio.play();
        await audio.onEnded.first;
        html.Url.revokeObjectUrl(url);
      } else {
        // 모바일에서는 audioplayers 사용
        // TODO: Implement mobile audio playback
      }
      
    } catch (e) {
      print('❌ TTS Error: $e');
      // TTS 실패시 무시하고 진행
    }
  }
  
  // 4. 음성 인식 시작
  Future<void> _startListening() async {
    if (isListening) return;
    
    try {
      bool available = await speechToText.initialize(
        onStatus: (status) {
          print('Speech recognition status: $status');
          if (status == 'done' || status == 'notListening') {
            isListening = false;
            onListeningStateChanged?.call(false);
          }
        },
        onError: (error) {
          print('Speech recognition error: $error');
          isListening = false;
          onListeningStateChanged?.call(false);
        },
      );
      
      if (available) {
        isListening = true;
        onListeningStateChanged?.call(true);
        
        await speechToText.listen(
          onResult: (result) async {
            if (result.finalResult && result.recognizedWords.isNotEmpty) {
              final userText = result.recognizedWords;
              onUserSpeaking?.call(userText);
              
              // 대화 기록에 추가
              conversationHistory.add(ConversationTurn(
                speaker: 'User',
                text: userText,
                timestamp: DateTime.now(),
              ));
              
              turnCount++;
              
              // 음성 인식 중지
              await stopListening();
              
              // GPT 응답 생성
              await _generateAIResponse(userText);
            }
          },
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          partialResults: true,
          localeId: 'en-US',
        );
      }
    } catch (e) {
      print('❌ Error starting speech recognition: $e');
      onError?.call('Microphone access failed');
    }
  }
  
  // 5. 음성 인식 중지
  Future<void> stopListening() async {
    if (isListening) {
      await speechToText.stop();
      isListening = false;
      onListeningStateChanged?.call(false);
    }
  }
  
  // 6. AI 응답 생성 및 재생
  Future<void> _generateAIResponse(String userInput) async {
    if (isProcessing) return;
    isProcessing = true;
    
    try {
      // 대화 컨텍스트 구성
      final messages = [
        {
          'role': 'system',
          'content': '''You're having a natural conversation.
          Scenario: ${currentScenario?.title ?? 'Casual chat'}
          Context: ${currentScenario?.context ?? 'Be friendly and natural'}
          
          Guidelines:
          - Respond naturally like a real person would
          - Keep responses concise (1-2 sentences usually)
          - React to what they said, don't correct their grammar
          - Use casual expressions and contractions
          - Show emotion and personality
          - Include filler words occasionally (um, well, you know, I mean)
          - Ask follow-up questions to keep conversation flowing
          - After 6-8 turns, naturally wrap up the conversation'''
        },
        // 대화 히스토리 추가
        ...conversationHistory.map((turn) => {
          'role': turn.speaker == 'AI' ? 'assistant' : 'user',
          'content': turn.text,
        }),
      ];
      
      final response = await _dio.post(
        '/chat/completions',
        data: {
          'model': 'gpt-4-turbo-preview',
          'messages': messages,
          'temperature': 0.8,
          'max_tokens': 150,
        },
      );
      
      final aiResponse = response.data['choices'][0]['message']['content'];
      
      // 대화 기록에 추가
      conversationHistory.add(ConversationTurn(
        speaker: 'AI',
        text: aiResponse,
        timestamp: DateTime.now(),
      ));
      
      // AI 응답 재생
      await _speakWithPremiumVoice(aiResponse);
      
      // 대화 종료 체크 (6턴 이상 또는 종료 신호)
      if (turnCount >= 6 || _isConversationEnding(aiResponse)) {
        onConversationEnd?.call();
      } else {
        // 계속 듣기
        await _startListening();
      }
      
    } catch (e) {
      print('❌ Error generating AI response: $e');
      onError?.call('Failed to generate response');
    } finally {
      isProcessing = false;
    }
  }
  
  // 7. 대화 종료 신호 체크
  bool _isConversationEnding(String message) {
    final endings = [
      'bye', 'goodbye', 'see you', 'talk to you later',
      'have a great', 'take care', 'gotta go', 'nice talking'
    ];
    
    final lowerMessage = message.toLowerCase();
    return endings.any((ending) => lowerMessage.contains(ending));
  }
  
  // 8. 대화 내역 가져오기
  List<ConversationTurn> getConversationHistory() {
    return List.from(conversationHistory);
  }
  
  // 9. 대화 종료
  void endConversation() {
    stopListening();
    onConversationEnd?.call();
  }
}