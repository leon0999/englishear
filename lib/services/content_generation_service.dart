// lib/services/content_generation_service.dart

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'audio_service.dart';

class ContentGenerationService {
  late final Dio _dio;
  late final String _apiKey;
  final AudioService audioService = AudioService();
  
  ContentGenerationService() {
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
  
  Future<Map<String, dynamic>> generateImmersiveContent({
    required String imageUrl,
    required String scenario,
    required String level,
  }) async {
    try {
      // GPT-4로 몰입형 컨텐츠 생성
      final prompt = _buildPrompt(scenario, level);
      
      final response = await _dio.post(
        '/chat/completions',
        data: {
          'model': 'gpt-4-turbo-preview',
          'messages': [
            {
              'role': 'system',
              'content': 'You are an expert English language teacher creating immersive learning experiences. Generate content that feels natural and engaging, as if the learner is really there in the scene.'
            },
            {
              'role': 'user',
              'content': prompt,
            }
          ],
          'temperature': 0.7,
          'max_tokens': 1000,
        },
      );
      
      if (response.statusCode == 200) {
        final content = response.data['choices'][0]['message']['content'];
        final jsonContent = _parseGPTResponse(content);
        
        // 배경음 URL 가져오기
        final ambientSoundUrl = await _getAmbientSound(scenario);
        
        // 스몰톡 TTS 생성
        final smallTalkAudio = await _generateSmallTalkAudio(jsonContent['smallTalk'] ?? []);
        
        return {
          'imageUrl': imageUrl,
          'ambientSound': ambientSoundUrl,
          'smallTalk': jsonContent['smallTalk'] ?? _getDefaultSmallTalk(scenario),
          'smallTalkAudio': smallTalkAudio,
          'lastSentence': jsonContent['lastSentence'] ?? _getDefaultLastSentence(scenario),
          'expectedResponse': jsonContent['expectedResponse'] ?? _getDefaultResponse(scenario),
          'alternatives': jsonContent['alternatives'] ?? _getDefaultAlternatives(scenario),
        };
      }
      
      // 폴백: 기본 컨텐츠 반환
      return _getDefaultContent(scenario, level, imageUrl);
      
    } catch (e) {
      print('Error generating immersive content: $e');
      return _getDefaultContent(scenario, level, imageUrl);
    }
  }
  
  String _buildPrompt(String scenario, String level) {
    return '''
Create an immersive English learning experience for a $scenario scenario.
Level: $level (${_getLevelDescription(level)})

Generate the following content in JSON format:
{
  "smallTalk": [3-4 sentences that would be overheard in this scenario, natural conversation],
  "lastSentence": "A question or statement that naturally invites a response from the learner",
  "expectedResponse": "The most natural response a native speaker would give",
  "alternatives": ["2-3 other acceptable responses"]
}

Requirements:
1. Small talk should be 10-20 seconds when spoken naturally
2. Language should match the $level level
3. The last sentence must naturally lead to learner participation
4. Make it feel authentic, like being in a real $scenario

Example for a restaurant (intermediate level):
{
  "smallTalk": [
    "The salmon special looks amazing tonight.",
    "I heard the chef trained at Le Cordon Bleu.",
    "Should we start with some appetizers?"
  ],
  "lastSentence": "What would you like to order?",
  "expectedResponse": "I'll have the salmon special, please",
  "alternatives": [
    "The salmon sounds great",
    "I'd like to try the special",
    "Can I get the salmon?"
  ]
}

Now generate content for: $scenario ($level level)
''';
  }
  
  String _getLevelDescription(String level) {
    switch (level) {
      case 'beginner':
        return 'simple sentences, common vocabulary, present tense';
      case 'intermediate':
        return 'varied sentences, everyday vocabulary, mixed tenses';
      case 'advanced':
        return 'complex sentences, sophisticated vocabulary, all tenses';
      default:
        return 'simple to moderate difficulty';
    }
  }
  
  Map<String, dynamic> _parseGPTResponse(String content) {
    try {
      // GPT 응답에서 JSON 추출
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
      if (jsonMatch != null) {
        return jsonDecode(jsonMatch.group(0)!);
      }
      
      // JSON 파싱 실패시 텍스트 파싱 시도
      return _parseTextResponse(content);
      
    } catch (e) {
      print('Error parsing GPT response: $e');
      return {};
    }
  }
  
  Map<String, dynamic> _parseTextResponse(String content) {
    // 텍스트 응답을 파싱하여 구조화된 데이터로 변환
    final Map<String, dynamic> result = {};
    
    // 간단한 텍스트 파싱 로직
    final lines = content.split('\n');
    List<String> smallTalk = [];
    
    for (final line in lines) {
      if (line.contains('Small talk:') || line.contains('Conversation:')) {
        // 스몰톡 파싱
      } else if (line.contains('Last sentence:') || line.contains('Question:')) {
        result['lastSentence'] = line.split(':').last.trim();
      } else if (line.contains('Expected:') || line.contains('Response:')) {
        result['expectedResponse'] = line.split(':').last.trim();
      }
    }
    
    if (smallTalk.isNotEmpty) result['smallTalk'] = smallTalk;
    
    return result;
  }
  
  Future<String> _getAmbientSound(String scenario) async {
    // 시나리오별 배경음 URL (실제 서비스에서는 CDN URL 사용)
    final sounds = {
      'street': 'https://www.soundjay.com/misc/sounds/street-ambience-1.mp3',
      'restaurant': 'https://www.soundjay.com/misc/sounds/restaurant-ambience-1.mp3',
      'park': 'https://www.soundjay.com/nature/sounds/park-ambience-1.mp3',
      'office': 'https://www.soundjay.com/misc/sounds/office-ambience-1.mp3',
      'home': 'https://www.soundjay.com/misc/sounds/home-ambience-1.mp3',
    };
    
    return sounds[scenario] ?? '';
  }
  
  Future<List<String>> _generateSmallTalkAudio(List<String> sentences) async {
    List<String> audioUrls = [];
    
    for (String sentence in sentences) {
      try {
        final audioUrl = await audioService.generateTTS(sentence);
        audioUrls.add(audioUrl);
      } catch (e) {
        print('Error generating TTS for: $sentence');
      }
    }
    
    return audioUrls;
  }
  
  // 기본 컨텐츠 (폴백용)
  Map<String, dynamic> _getDefaultContent(String scenario, String level, String imageUrl) {
    final defaultContents = {
      'street': {
        'beginner': {
          'smallTalk': [
            'Look at all the people!',
            'The shops are busy today.',
            'It\'s a nice day for walking.'
          ],
          'lastSentence': 'Where are you going?',
          'expectedResponse': 'I\'m going to the store',
          'alternatives': ['To the store', 'I\'m going shopping', 'Just walking around'],
        },
        'intermediate': {
          'smallTalk': [
            'The traffic is heavier than usual.',
            'That new coffee shop looks interesting.',
            'I love the energy of the city.'
          ],
          'lastSentence': 'Have you tried that new café?',
          'expectedResponse': 'Not yet, but I\'d love to',
          'alternatives': ['No, is it good?', 'Yes, the coffee is amazing', 'I\'ve been meaning to'],
        },
        'advanced': {
          'smallTalk': [
            'The urban development here has been remarkable.',
            'I\'ve noticed more pedestrian-friendly spaces lately.',
            'The architectural diversity really defines this neighborhood.'
          ],
          'lastSentence': 'What\'s your impression of the changes?',
          'expectedResponse': 'I think they\'ve really improved the area\'s livability',
          'alternatives': [
            'The changes have made it more vibrant',
            'It\'s definitely more pedestrian-friendly now',
            'I appreciate the blend of old and new architecture'
          ],
        },
      },
      'restaurant': {
        'beginner': {
          'smallTalk': [
            'This place smells good!',
            'The menu looks great.',
            'I\'m very hungry.'
          ],
          'lastSentence': 'What do you want to eat?',
          'expectedResponse': 'I want the pasta',
          'alternatives': ['The pizza looks good', 'I\'ll have a burger', 'Something light, please'],
        },
        'intermediate': {
          'smallTalk': [
            'The atmosphere here is really nice.',
            'I heard their pasta is homemade.',
            'Should we get some wine?'
          ],
          'lastSentence': 'What are you in the mood for?',
          'expectedResponse': 'I\'m thinking about the seafood special',
          'alternatives': [
            'Something light would be nice',
            'I can\'t decide between the steak and salmon',
            'What do you recommend?'
          ],
        },
        'advanced': {
          'smallTalk': [
            'The ambiance perfectly complements their cuisine.',
            'I appreciate how they source local ingredients.',
            'Their wine pairing suggestions are always spot on.'
          ],
          'lastSentence': 'How would you like your steak prepared?',
          'expectedResponse': 'Medium-rare, with the red wine reduction on the side',
          'alternatives': [
            'I\'ll defer to the chef\'s recommendation',
            'Medium, and could we share the wine pairing?',
            'Actually, I\'m leaning towards the fish instead'
          ],
        },
      },
    };
    
    // 시나리오와 레벨에 맞는 기본 컨텐츠 반환
    const defaultLevel = 'beginner';
    const defaultScenario = 'street';
    
    final content = defaultContents[scenario]?[level] ?? 
                    defaultContents[scenario]?[defaultLevel] ?? 
                    defaultContents[defaultScenario]?[defaultLevel] ?? {};
    
    return {
      'imageUrl': imageUrl,
      'ambientSound': '',
      ...content,
      'smallTalkAudio': [],
    };
  }
  
  List<String> _getDefaultSmallTalk(String scenario) {
    return _getDefaultContent(scenario, 'beginner', '')['smallTalk'] ?? [];
  }
  
  String _getDefaultLastSentence(String scenario) {
    return _getDefaultContent(scenario, 'beginner', '')['lastSentence'] ?? 'What do you think?';
  }
  
  String _getDefaultResponse(String scenario) {
    return _getDefaultContent(scenario, 'beginner', '')['expectedResponse'] ?? 'That sounds great';
  }
  
  List<String> _getDefaultAlternatives(String scenario) {
    return _getDefaultContent(scenario, 'beginner', '')['alternatives'] ?? ['Yes', 'No', 'Maybe'];
  }
}