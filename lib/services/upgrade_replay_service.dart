// lib/services/upgrade_replay_service.dart

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'voice_conversation_service.dart';

// 개선된 문장 모델
class UpgradedSentence {
  final String original;
  final String improved;
  final List<String> improvements;
  final int nativeScore;

  UpgradedSentence({
    required this.original,
    required this.improved,
    required this.improvements,
    required this.nativeScore,
  });

  Map<String, dynamic> toJson() => {
    'original': original,
    'improved': improved,
    'improvements': improvements,
    'nativeScore': nativeScore,
  };
}

// 전체 대화 리플레이 데이터
class ConversationReplay {
  final List<ConversationTurn> originalConversation;
  final List<ConversationTurn> upgradedConversation;
  final List<UpgradedSentence> improvements;
  final int overallScore;
  final String feedback;

  ConversationReplay({
    required this.originalConversation,
    required this.upgradedConversation,
    required this.improvements,
    required this.overallScore,
    required this.feedback,
  });
}

class UpgradeReplayService {
  late final Dio _dio;
  late final String _apiKey;
  
  // 음성 변환용
  static const List<String> replayVoices = ['alloy', 'echo', 'nova', 'shimmer'];
  
  UpgradeReplayService() {
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
  
  // 1. 대화 분석 및 개선점 생성
  Future<ConversationReplay> analyzeAndUpgrade(List<ConversationTurn> conversation) async {
    try {
      // 사용자 발화만 추출
      final userTurns = conversation.where((turn) => turn.speaker == 'User').toList();
      
      if (userTurns.isEmpty) {
        throw Exception('No user utterances found in conversation');
      }
      
      // 각 사용자 발화 개선
      List<UpgradedSentence> improvements = [];
      for (var turn in userTurns) {
        final upgraded = await _upgradeUserSentence(turn.text, conversation);
        improvements.add(upgraded);
      }
      
      // 개선된 대화 재구성
      final upgradedConversation = _reconstructConversation(conversation, improvements);
      
      // 전체 평가 생성
      final evaluation = await _generateOverallEvaluation(conversation, improvements);
      
      return ConversationReplay(
        originalConversation: conversation,
        upgradedConversation: upgradedConversation,
        improvements: improvements,
        overallScore: evaluation['score'],
        feedback: evaluation['feedback'],
      );
      
    } catch (e) {
      print('❌ Error analyzing conversation: $e');
      throw e;
    }
  }
  
  // 2. 개별 문장 개선
  Future<UpgradedSentence> _upgradeUserSentence(String userText, List<ConversationTurn> context) async {
    try {
      // 대화 컨텍스트 구성
      final contextStr = context.map((t) => '${t.speaker}: ${t.text}').join('\n');
      
      final response = await _dio.post(
        '/chat/completions',
        data: {
          'model': 'gpt-4-turbo-preview',
          'messages': [
            {
              'role': 'system',
              'content': '''You are an expert English teacher helping non-native speakers sound more natural.
              
              Analyze the user's sentence in context and provide:
              1. A more native-sounding version
              2. Specific improvements made
              3. Native speaker score (1-100)
              
              Focus on:
              - Natural expressions and idioms
              - Better word choices
              - Improved grammar and flow
              - Conversational tone
              
              Return JSON format:
              {
                "improved": "the improved sentence",
                "improvements": ["improvement 1", "improvement 2"],
                "nativeScore": 85
              }'''
            },
            {
              'role': 'user',
              'content': '''Context:
              $contextStr
              
              User said: "$userText"
              
              Provide a more native-sounding version.'''
            }
          ],
          'temperature': 0.7,
          'response_format': {'type': 'json_object'},
        },
      );
      
      final content = response.data['choices'][0]['message']['content'];
      final json = jsonDecode(content);
      
      return UpgradedSentence(
        original: userText,
        improved: json['improved'] ?? userText,
        improvements: List<String>.from(json['improvements'] ?? []),
        nativeScore: json['nativeScore'] ?? 70,
      );
      
    } catch (e) {
      print('Error upgrading sentence: $e');
      // 실패시 원본 반환
      return UpgradedSentence(
        original: userText,
        improved: userText,
        improvements: ['Unable to generate improvements'],
        nativeScore: 50,
      );
    }
  }
  
  // 3. 개선된 대화 재구성
  List<ConversationTurn> _reconstructConversation(
    List<ConversationTurn> original,
    List<UpgradedSentence> improvements,
  ) {
    List<ConversationTurn> upgraded = [];
    int improvementIndex = 0;
    
    for (var turn in original) {
      if (turn.speaker == 'User' && improvementIndex < improvements.length) {
        // 사용자 발화를 개선된 버전으로 교체
        upgraded.add(ConversationTurn(
          speaker: turn.speaker,
          text: improvements[improvementIndex].improved,
          timestamp: turn.timestamp,
          improvedVersion: improvements[improvementIndex].improved,
        ));
        improvementIndex++;
      } else {
        // AI 발화는 그대로 유지
        upgraded.add(turn);
      }
    }
    
    return upgraded;
  }
  
  // 4. 전체 평가 생성
  Future<Map<String, dynamic>> _generateOverallEvaluation(
    List<ConversationTurn> conversation,
    List<UpgradedSentence> improvements,
  ) async {
    try {
      final avgScore = improvements.isEmpty ? 50 : 
        improvements.map((i) => i.nativeScore).reduce((a, b) => a + b) ~/ improvements.length;
      
      final response = await _dio.post(
        '/chat/completions',
        data: {
          'model': 'gpt-4-turbo-preview',
          'messages': [
            {
              'role': 'system',
              'content': '''You are an encouraging English teacher.
              Based on the conversation and improvements, provide:
              1. Overall performance feedback
              2. Key areas for improvement
              3. Positive reinforcement
              
              Keep it concise and motivating.'''
            },
            {
              'role': 'user',
              'content': '''The student completed a conversation practice.
              Average native score: $avgScore/100
              Number of turns: ${improvements.length}
              
              Provide encouraging feedback in 2-3 sentences.'''
            }
          ],
          'temperature': 0.8,
          'max_tokens': 150,
        },
      );
      
      return {
        'score': avgScore,
        'feedback': response.data['choices'][0]['message']['content'],
      };
      
    } catch (e) {
      print('Error generating evaluation: $e');
      return {
        'score': 70,
        'feedback': 'Good job practicing! Keep working on natural expressions and you\'ll sound even more fluent.',
      };
    }
  }
  
  // 5. 리플레이 음성 생성 (개선된 대화)
  Future<List<String>> generateReplayAudio(List<ConversationTurn> upgradedConversation) async {
    List<String> audioUrls = [];
    
    try {
      for (var turn in upgradedConversation) {
        // 각 턴마다 다른 음성 사용 (다양성)
        final voice = turn.speaker == 'AI' ? 
          'nova' : replayVoices[audioUrls.length % replayVoices.length];
        
        final response = await _dio.post(
          '/audio/speech',
          options: Options(responseType: ResponseType.bytes),
          data: {
            'model': 'tts-1-hd',
            'voice': voice,
            'input': turn.text,
            'speed': turn.speaker == 'User' ? 0.9 : 0.95,
          },
        );
        
        // Base64로 인코딩
        final bytes = response.data;
        final base64Audio = base64Encode(bytes);
        audioUrls.add('data:audio/mp3;base64,$base64Audio');
      }
      
    } catch (e) {
      print('Error generating replay audio: $e');
    }
    
    return audioUrls;
  }
  
  // 6. 학습 보고서 생성
  Future<Map<String, dynamic>> generateLearningReport(ConversationReplay replay) async {
    try {
      // 주요 개선 포인트 추출
      final allImprovements = replay.improvements
        .expand((i) => i.improvements)
        .toList();
      
      // 가장 많이 나온 개선 영역 분석
      final improvementCategories = _categorizeImprovements(allImprovements);
      
      return {
        'totalTurns': replay.originalConversation.length,
        'userTurns': replay.improvements.length,
        'averageScore': replay.overallScore,
        'topImprovements': improvementCategories.take(3).toList(),
        'feedback': replay.feedback,
        'nextSteps': _generateNextSteps(replay.overallScore),
      };
      
    } catch (e) {
      print('Error generating report: $e');
      return {
        'error': 'Failed to generate learning report',
      };
    }
  }
  
  // 7. 개선점 카테고리 분석
  List<Map<String, dynamic>> _categorizeImprovements(List<String> improvements) {
    Map<String, int> categories = {
      'Grammar': 0,
      'Vocabulary': 0,
      'Expressions': 0,
      'Fluency': 0,
      'Pronunciation': 0,
    };
    
    for (var improvement in improvements) {
      final lower = improvement.toLowerCase();
      if (lower.contains('grammar') || lower.contains('tense')) {
        categories['Grammar'] = (categories['Grammar'] ?? 0) + 1;
      }
      if (lower.contains('word') || lower.contains('vocabulary')) {
        categories['Vocabulary'] = (categories['Vocabulary'] ?? 0) + 1;
      }
      if (lower.contains('expression') || lower.contains('idiom')) {
        categories['Expressions'] = (categories['Expressions'] ?? 0) + 1;
      }
      if (lower.contains('natural') || lower.contains('fluent')) {
        categories['Fluency'] = (categories['Fluency'] ?? 0) + 1;
      }
    }
    
    return categories.entries
      .where((e) => e.value > 0)
      .map((e) => {'category': e.key, 'count': e.value})
      .toList()
      ..sort((a, b) => (b['count'] as int).compareTo(a['count'] as int));
  }
  
  // 8. 다음 학습 단계 제안
  List<String> _generateNextSteps(int score) {
    if (score >= 85) {
      return [
        'Practice advanced idioms and expressions',
        'Focus on cultural nuances in conversation',
        'Try more complex topics',
      ];
    } else if (score >= 70) {
      return [
        'Work on natural conversation flow',
        'Practice common phrasal verbs',
        'Improve sentence variety',
      ];
    } else {
      return [
        'Focus on basic grammar patterns',
        'Build vocabulary with common words',
        'Practice simple sentence structures',
      ];
    }
  }
}