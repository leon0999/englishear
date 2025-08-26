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

  // DALL-E 3로 학습용 장면 이미지 생성
  Future<String> generateSceneImage({
    required String level,
    String? customPrompt,
  }) async {
    final prompts = {
      'beginner': 'A simple, colorful illustration of daily life scene: person walking in a bright park with clear sky, cartoon style, child-friendly, no text, clear composition',
      'intermediate': 'A modern workplace scene: people collaborating in a bright office, semi-realistic style, professional but friendly atmosphere, good lighting, no text',
      'advanced': 'A complex urban scene: bustling city street with various activities, photorealistic style, detailed environment with shops and pedestrians, no text',
    };
    
    final prompt = customPrompt ?? prompts[level] ?? prompts['beginner']!;
    
    try {
      final response = await _dio.post(
        '/images/generations',
        data: {
          'model': 'dall-e-3',
          'prompt': prompt,
          'n': 1,
          'size': '1024x1024',
          'quality': 'standard', // 'hd'는 2배 비용
          'style': 'vivid', // 'natural' 옵션도 있음
        },
      );
      
      if (response.data['data'] != null && response.data['data'].isNotEmpty) {
        return response.data['data'][0]['url'];
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
}