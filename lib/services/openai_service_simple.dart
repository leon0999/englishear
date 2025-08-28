import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../core/logger.dart';

// 간소화된 OpenAI 서비스 (MVP용)
class OpenAIServiceSimple {
  late final Dio _dio;
  late final String _apiKey;
  
  // Singleton pattern
  static OpenAIServiceSimple? _instance;
  
  factory OpenAIServiceSimple() {
    _instance ??= OpenAIServiceSimple._internal();
    return _instance!;
  }
  
  OpenAIServiceSimple._internal() {
    _initialize();
  }
  
  void _initialize() {
    _apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
    
    if (_apiKey.isEmpty) {
      Logger.warning('OpenAI API key not configured');
    }
    
    _dio = Dio(BaseOptions(
      baseUrl: dotenv.env['OPENAI_BASE_URL'] ?? 'https://api.openai.com/v1',
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));
    
    Logger.info('OpenAI Service initialized');
  }
  
  // 캐시 초기화 (더미 메서드)
  Future<void> initializeCache() async {
    Logger.info('Cache initialized (dummy)');
  }
  
  // AI 튜터 응답 생성
  Future<String> getAITutorResponse({
    required String userMessage,
    required String context,
  }) async {
    try {
      final response = await _retryRequest(() => _dio.post(
        '/chat/completions',
        data: {
          'model': 'gpt-4-turbo-preview',
          'messages': [
            {
              'role': 'system',
              'content': context,
            },
            if (userMessage.isNotEmpty)
              {
                'role': 'user',
                'content': userMessage,
              },
          ],
          'temperature': 0.7,
          'max_tokens': 200,
        },
      ));
      
      if (response.statusCode == 200) {
        final data = response.data;
        return data['choices'][0]['message']['content'] ?? '';
      }
      
      throw Exception('Failed to get AI response');
    } catch (e) {
      Logger.error('Failed to get AI tutor response', error: e);
      return 'I apologize, but I\'m having trouble responding right now. Please try again.';
    }
  }
  
  // 재시도 로직
  Future<Response> _retryRequest(Future<Response> Function() request, {int maxAttempts = 3}) async {
    int attempts = 0;
    
    while (attempts < maxAttempts) {
      try {
        final response = await request();
        return response;
      } catch (e) {
        attempts++;
        
        if (attempts >= maxAttempts) {
          throw e;
        }
        
        // Rate limit 에러 체크
        if (e is DioException && e.response?.statusCode == 429) {
          await Future.delayed(Duration(seconds: attempts * 2));
          continue;
        }
        
        // 네트워크 에러 체크
        if (e is DioException && 
            (e.type == DioExceptionType.connectionTimeout ||
             e.type == DioExceptionType.receiveTimeout ||
             e.type == DioExceptionType.connectionError)) {
          await Future.delayed(Duration(seconds: attempts));
          continue;
        }
        
        // 다른 에러는 즉시 throw
        throw e;
      }
    }
    
    throw Exception('Max retry attempts reached');
  }
}