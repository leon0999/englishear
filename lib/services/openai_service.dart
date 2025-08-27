import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class OpenAIService {
  late final Dio _dio;
  late final String _apiKey;
  
  OpenAIService() {
    _apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
    _dio = Dio(BaseOptions(
      baseUrl: dotenv.env['OPENAI_BASE_URL'] ?? 'https://api.openai.com/v1',
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  // DALL-E 3로 학습용 장면 이미지 생성 (개선된 버전)
  Future<String> generateSceneImage({
    required String level,
    String? scenario,
    String? customPrompt,
  }) async {
    final prompt = customPrompt ?? _buildEnhancedPrompt(level, scenario);
    
    try {
      print('🎨 [DALL-E 3] Generating image for $scenario ($level)');
      
      final response = await _dio.post(
        '/images/generations',
        data: {
          'model': 'dall-e-3',
          'prompt': prompt,
          'n': 1,
          'size': '1024x1024',
          'quality': 'standard', // 'standard' for cost optimization
          'style': 'natural', // 'natural' for realistic learning scenes
          'response_format': 'b64_json', // Base64로 받기 (CORS 회피)
        },
      );
      
      if (response.statusCode == 200 && 
          response.data['data'] != null && 
          response.data['data'].isNotEmpty) {
        // Base64 형식으로 받은 경우
        if (response.data['data'][0]['b64_json'] != null) {
          final base64Image = response.data['data'][0]['b64_json'];
          print('✅ [DALL-E 3] Image generated successfully (Base64)');
          // Data URL 형식으로 반환
          return 'data:image/png;base64,$base64Image';
        }
        // URL 형식으로 받은 경우 (fallback)
        else if (response.data['data'][0]['url'] != null) {
          final imageUrl = response.data['data'][0]['url'];
          print('✅ [DALL-E 3] Image generated successfully (URL)');
          return imageUrl;
        }
      }
      return '';
    } catch (e) {
      print('Error generating image with DALL-E: $e');
      throw Exception('Failed to generate image: $e');
    }
  }

  // GPT-4로 문장 생성 (이미지 설명 기반)
  Future<Map<String, dynamic>> generateSentenceForImage({
    required String imageDescription,
    required String level,
  }) async {
    final difficultyGuide = {
      'beginner': 'Use simple present tense, common vocabulary (top 1000 words), 5-8 words per sentence',
      'intermediate': 'Use various tenses, everyday vocabulary (top 3000 words), 8-12 words per sentence',
      'advanced': 'Use complex grammar, sophisticated vocabulary, idiomatic expressions, 12-20 words',
    };
    
    try {
      final response = await _dio.post(
        '/chat/completions',
        data: {
          'model': 'gpt-4-turbo-preview',
          'messages': [
            {
              'role': 'system',
              'content': '''You are an English teaching assistant. Generate learning content based on the scene.
              
              Requirements:
              - Create one English sentence describing the scene
              - Difficulty: ${difficultyGuide[level]}
              - Extract 3-4 key vocabulary words from the sentence
              - Return valid JSON format
              
              Response format:
              {
                "sentence": "The complete sentence",
                "keywords": ["word1", "word2", "word3"],
                "difficulty": 1-5 (numeric),
                "grammar_point": "Brief grammar explanation",
                "pronunciation_tips": ["tip1", "tip2"]
              }'''
            },
            {
              'role': 'user',
              'content': 'Generate learning content for this scene: $imageDescription'
            }
          ],
          'response_format': {'type': 'json_object'},
          'temperature': 0.7,
          'max_tokens': 300,
        },
      );
      
      final content = response.data['choices'][0]['message']['content'];
      return json.decode(content);
    } catch (e) {
      print('Error generating sentence: $e');
      throw Exception('Failed to generate sentence: $e');
    }
  }

  // 사용자 발음 평가 및 피드백
  Future<Map<String, dynamic>> evaluatePronunciation({
    required String userSpeech,
    required String correctSentence,
    required List<String> keywords,
  }) async {
    try {
      final response = await _dio.post(
        '/chat/completions',
        data: {
          'model': 'gpt-4-turbo-preview',
          'messages': [
            {
              'role': 'system',
              'content': '''You are an expert English pronunciation coach. Evaluate the user's speech.
              
              Evaluation criteria:
              1. Pronunciation accuracy (0-100)
              2. Fluency and rhythm (0-100)
              3. Grammar correctness
              4. Keyword detection
              
              Return JSON format:
              {
                "overall_score": 0-100,
                "pronunciation_score": 0-100,
                "fluency_score": 0-100,
                "grammar_score": 0-100,
                "matched_keywords": ["words correctly pronounced"],
                "missed_keywords": ["words missed or mispronounced"],
                "errors": [{"type": "pronunciation/grammar", "word": "word", "suggestion": "tip"}],
                "feedback": "Encouraging personalized feedback",
                "improvement_tips": ["specific tip 1", "specific tip 2"]
              }'''
            },
            {
              'role': 'user',
              'content': '''Evaluate this speech:
              Correct sentence: "$correctSentence"
              Keywords to check: ${keywords.join(', ')}
              User said: "$userSpeech"'''
            }
          ],
          'response_format': {'type': 'json_object'},
          'temperature': 0.3,
          'max_tokens': 500,
        },
      );
      
      final content = response.data['choices'][0]['message']['content'];
      return json.decode(content);
    } catch (e) {
      print('Error evaluating pronunciation: $e');
      throw Exception('Failed to evaluate pronunciation: $e');
    }
  }

  // AI 튜터 대화 (추가 기능)
  Future<String> getAITutorResponse({
    required String userMessage,
    required String context,
  }) async {
    try {
      final response = await _dio.post(
        '/chat/completions',
        data: {
          'model': 'gpt-4-turbo-preview',
          'messages': [
            {
              'role': 'system',
              'content': '''You are a friendly English tutor. Help users improve their English speaking skills.
              - Be encouraging and patient
              - Provide simple, clear explanations
              - Suggest practice exercises
              - Keep responses concise (2-3 sentences)'''
            },
            {
              'role': 'user',
              'content': 'Context: $context\n\nStudent question: $userMessage'
            }
          ],
          'temperature': 0.7,
          'max_tokens': 200,
        },
      );
      
      return response.data['choices'][0]['message']['content'];
    } catch (e) {
      print('Error getting tutor response: $e');
      return 'I apologize, but I\'m having trouble responding right now. Please try again.';
    }
  }
  
  // DALL-E 3용 향상된 프롬프트 생성
  String _buildEnhancedPrompt(String level, String? scenario) {
    final Map<String, Map<String, String>> prompts = {
      'beginner': {
        'street': 'A bright, friendly street scene with 3-4 people walking, clear storefronts, daytime, simple composition, educational illustration style, no text or signs',
        'restaurant': 'A cozy restaurant interior with 2-3 people eating at tables, warm lighting, simple decor, clear view, educational style, no text',
        'park': 'A sunny park with 2-3 people, green trees, playground, simple activities, bright colors, educational illustration, no text',
        'office': 'A modern office with 3 people working at computers, bright space, clean desks, educational style, no text',
        'home': 'A warm home interior with family of 3-4, living room setting, cozy atmosphere, educational style, no text',
      },
      'intermediate': {
        'street': 'A realistic urban street with 4-5 pedestrians, shops, moderate traffic, natural lighting, photographic style, no text',
        'restaurant': 'A restaurant scene with diners and waiter, atmospheric lighting, semi-realistic style, clear details, no text',
        'park': 'An active park with people jogging and relaxing, natural scenery, golden hour light, photographic style, no text',
        'office': 'A professional office with team meeting, modern furniture, natural light, business setting, no text',
        'home': 'A modern home with family activities, open plan living, natural lighting, lifestyle photography, no text',
      },
      'advanced': {
        'street': 'A detailed city street corner with diverse people, architectural details, dynamic urban life, photorealistic style, no text',
        'restaurant': 'An upscale restaurant with multiple diners, elegant decor, sophisticated atmosphere, photorealistic, no text',
        'park': 'A vibrant public park with various activities, landscape details, environmental portrait style, no text',
        'office': 'A corporate office environment, glass walls, multiple professionals, high-end design, photorealistic, no text',
        'home': 'A luxury home interior with family gathering, designer furniture, lifestyle photography style, no text',
      },
    };
    
    final levelPrompts = prompts[level] ?? prompts['beginner']!;
    final basePrompt = levelPrompts[scenario] ?? levelPrompts['street']!;
    
    return '$basePrompt, high quality, clear composition, educational content, suitable for language learning';
  }
}