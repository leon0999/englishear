// lib/services/stable_diffusion_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class StableDiffusionService {
  late final Dio _dio;
  late final String _apiKey;

  // SD-XL 1.0 공식 지원 크기 (Stability AI 문서 기준)
  static const List<Map<String, int>> SDXL_SUPPORTED_DIMENSIONS = [
    {'width': 1024, 'height': 1024},  // 1:1 정사각형
    {'width': 1152, 'height': 896},   // 9:7 가로
    {'width': 1216, 'height': 832},   // 3:2 가로
    {'width': 1344, 'height': 768},   // 7:4 와이드
    {'width': 1536, 'height': 640},   // 12:5 울트라와이드
    {'width': 640, 'height': 1536},   // 5:12 울트라톨
    {'width': 768, 'height': 1344},   // 4:7 톨
    {'width': 832, 'height': 1216},   // 2:3 세로
    {'width': 896, 'height': 1152},   // 7:9 세로
  ];

  // 레벨별 최적화된 크기 매핑
  static const Map<String, Map<String, int>> LEVEL_DIMENSIONS = {
    'beginner': {'width': 1024, 'height': 1024},     // 정사각형 - 가장 범용적
    'intermediate': {'width': 896, 'height': 1152},  // 세로형 - 모바일 최적
    'advanced': {'width': 1216, 'height': 832},      // 가로형 - 파노라마 효과
  };

  StableDiffusionService() {
    _apiKey = dotenv.env['STABILITY_API_KEY'] ?? '';
    _dio = Dio(BaseOptions(
      baseUrl: 'https://api.stability.ai/v1',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
    ));
  }

  Future<String> generateEducationalScene({
    required String level,
    String? theme,
  }) async {
    print('🎨 [StableDiffusion] Starting image generation for level: $level, theme: $theme');

    // 레벨별 최적 설정
    final dimensions = LEVEL_DIMENSIONS[level] ?? LEVEL_DIMENSIONS['beginner']!;
    final prompt = _buildOptimizedPrompt(level, theme);
    
    final Map<String, Map<String, dynamic>> levelConfigs = {
      'beginner': {
        'prompt': prompt,
        'dimensions': dimensions,
        'cfg_scale': 7.0,
        'steps': 30,  // SD-XL은 최소 30 steps 권장
        'style_preset': 'photographic',
      },
      'intermediate': {
        'prompt': prompt,
        'dimensions': dimensions,
        'cfg_scale': 7.5,
        'steps': 35,
        'style_preset': 'photographic',
      },
      'advanced': {
        'prompt': prompt,
        'dimensions': dimensions,
        'cfg_scale': 8.0,
        'steps': 40,
        'style_preset': 'photographic',
      },
    };

    final config = levelConfigs[level] ?? levelConfigs['beginner']!;

    try {
      print(
          '🚀 [StableDiffusion] Sending request with dimensions: ${config['dimensions']['width']}x${config['dimensions']['height']}');

      final response = await _dio.post(
        '/generation/stable-diffusion-xl-1024-v1-0/text-to-image',
        options: Options(
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          validateStatus: (status) => status! < 500,
        ),
        data: {
          'text_prompts': [
            {
              'text': config['prompt'],
              'weight': 1.0,
            },
            {
              'text': 'blurry, bad quality, text, words, letters, numbers, watermark, logo, signature, UI elements, buttons',
              'weight': -1.0,
            },
          ],
          'cfg_scale': config['cfg_scale'],
          'width': config['dimensions']['width'],   // SD-XL 호환 크기
          'height': config['dimensions']['height'],  // SD-XL 호환 크기
          'samples': 1,
          'steps': config['steps'],
          'style_preset': config['style_preset'],
        },
      );

      if (response.statusCode == 200) {
        if (response.data['artifacts'] != null &&
            response.data['artifacts'].isNotEmpty) {
          final base64Image = response.data['artifacts'][0]['base64'];
          print('✅ [StableDiffusion] Image generated successfully!');
          return 'data:image/png;base64,$base64Image';
        }
      } else {
        // 상세한 에러 로깅
        print('❌ [StableDiffusion] API Error:');
        print('   - Status: ${response.statusCode}');
        print('   - Message: ${response.data}');
        
        // 사용자 친화적 에러 메시지
        final errorMsg = _parseErrorMessage(response.statusCode);
        print('   - Action: $errorMsg');
        
        throw Exception(errorMsg);
      }

      throw Exception('No image data received from API');
      
    } catch (e) {
      print('❌ [StableDiffusion] Generation failed: ${e.toString()}');
      
      // 프로덕션 레벨 폴백 전략
      return await _getFallbackImage(theme ?? 'general', level);
    }
  }

  // SD 1.5 모델 사용 (더 빠르고 저렴)
  Future<String> generateImageFast({
    required String prompt,
    int width = 512,
    int height = 512,
  }) async {
    try {
      final response = await _dio.post(
        '/generation/stable-diffusion-v1-6/text-to-image', // SD 1.5는 512x512 지원
        options: Options(
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          },
        ),
        data: {
          'text_prompts': [
            {'text': prompt, 'weight': 1.0},
          ],
          'cfg_scale': 7,
          'width': width, // 512 가능
          'height': height, // 512 가능
          'samples': 1,
          'steps': 15, // 더 빠른 생성
        },
      );

      if (response.data['artifacts'] != null) {
        final base64Image = response.data['artifacts'][0]['base64'];
        return 'data:image/png;base64,$base64Image';
      }
      return '';
    } catch (e) {
      print('Error with SD 1.5: $e');
      return '';
    }
  }

  // 통합 프롬프트 빌더 - 레벨과 테마별 최적화
  String _buildOptimizedPrompt(String level, String? theme) {
    // 품질 향상 키워드
    const String qualityKeywords = 'highly detailed, photorealistic, 8k quality, professional photography, sharp focus, natural lighting';
    
    // 네거티브 프롬프트를 고려한 포지티브 강화
    const String compositionalKeywords = 'clear composition, well-framed, balanced elements, rule of thirds';
    
    // 시나리오별 프롬프트
    final Map<String, Map<String, String>> prompts = {
      'beginner': {
        'street': 'Simple street scene with exactly 3 people walking on sidewalk, minimal traffic, bright daylight, clear storefronts, $qualityKeywords, $compositionalKeywords',
        'restaurant': 'Cozy restaurant interior with 2-3 customers at tables, one waiter serving, warm lighting, simple decor, $qualityKeywords',
        'park': 'Peaceful park scene with 2-3 people walking, green trees, sunny weather, open spaces, $qualityKeywords',
        'office': 'Modern office space with 3 workers at computers, clean desks, bright lighting, $qualityKeywords',
        'home': 'Warm home interior with 3 family members in living room, comfortable furniture, $qualityKeywords',
      },
      'intermediate': {
        'street': 'Urban street photography, 4-5 pedestrians, local shops, moderate traffic, golden hour lighting, $qualityKeywords, cinematic feel',
        'restaurant': 'Restaurant ambiance with 4 diners at tables, waiter in action, atmospheric lighting, $qualityKeywords, lifestyle photography',
        'park': 'Active park scene with 4-5 people doing activities (jogging, reading), natural scenery, $qualityKeywords, documentary style',
        'office': 'Professional workspace with 4-5 colleagues collaborating, modern interior, $qualityKeywords, corporate photography',
        'home': 'Family gathering in modern home, 4-5 people interacting, lived-in feel, $qualityKeywords, lifestyle shot',
      },
      'advanced': {
        'street': 'Bustling city street corner, 5-6 diverse people, architectural details, dynamic composition, $qualityKeywords, street photography style',
        'restaurant': 'Upscale dining atmosphere, 5-6 patrons, elegant interior, sophisticated lighting, $qualityKeywords, commercial photography',
        'park': 'Vibrant public park, 5-6 people in various activities, landscape elements, $qualityKeywords, environmental portrait',
        'office': 'Executive office environment, 5-6 professionals, glass walls, high-end design, $qualityKeywords, architectural photography',
        'home': 'Luxury home interior, 5-6 people at gathering, designer furniture, $qualityKeywords, interior design photography',
      },
    };
    
    // 프롬프트 선택
    final levelPrompts = prompts[level] ?? prompts['beginner']!;
    final basePrompt = levelPrompts[theme] ?? levelPrompts.values.first;
    
    // 교육용 컨텍스트 추가
    return '$basePrompt, educational content, clear focal points, no text overlay, no UI elements';
  }

  // 시나리오별 명확한 프롬프트 생성 (최대 3-5명)
  String _buildBeginnerPrompt(String? theme) {
    final scenarios = {
      'street': 'Clear urban street scene with exactly 3 people walking on sidewalk, minimal cars, storefronts, daytime, bright colors, simple composition, no text or signs',
      'restaurant': 'Interior restaurant scene, 2-3 people sitting at one table eating, one waiter serving, bright lighting, focused view, no text',
      'park': 'Open park with green grass, 2 people walking dog, 1-2 children playing, trees, sunny day, simple scene, no text',
      'office': 'Modern office interior, 3 people working at desks with computers, bright lighting, clean workspace, no text',
      'home': 'Cozy home interior, 3-4 family members in living room, simple furniture, warm lighting, no text',
    };
    
    return scenarios[theme] ?? 'Simple daily life scene with 3-4 people maximum doing activities, bright colors, focused composition, no text';
  }

  String _buildIntermediatePrompt(String? theme) {
    final scenarios = {
      'street': 'Photorealistic street photography, exactly 4-5 people walking, minimal traffic, urban environment, natural lighting, focused composition, no text',
      'restaurant': 'Realistic restaurant interior, 3-4 customers at tables, 1 waiter serving, clean decor, ambient lighting, no text',
      'park': 'Natural park scene, 3 people jogging, 2 people at picnic, trees and paths, golden hour light, no crowds, no text',
      'office': 'Professional office environment, 4 people in meeting room, modern furniture, natural light, clean composition, no text',
      'home': 'Modern home interior, 4 family members doing activities, kitchen or living area, simple furniture, warm atmosphere, no text',
    };
    
    return scenarios[theme] ?? 'Realistic scene with 4-5 people maximum interacting, professional quality, natural lighting, focused view, no text';
  }

  String _buildAdvancedPrompt(String? theme) {
    final scenarios = {
      'street': 'Urban street corner, exactly 5 people visible, 2 shops, minimal vehicles, clean architecture, cinematic lighting, no crowds, no text',
      'restaurant': 'Upscale restaurant, 4-5 people at 2 tables, 1 waiter, elegant decor, atmospheric lighting, focused view, no text',
      'park': 'Public park area, 5 people doing different activities (jogging, reading, walking), trees, water feature, no crowds, no text',
      'office': 'Corporate office interior, 5 people in open space, glass walls, modern design, focused composition, no text',
      'home': 'Home interior, 4-5 family members in living/dining area, clean interior design, lifestyle photography, no text',
    };
    
    return scenarios[theme] ?? 'Photorealistic scene with exactly 5 people maximum, clear focal point, detailed but clean environment, cinematic quality, no text';
  }

  // 이미지 캐싱 (API 호출 줄이기)
  static final Map<String, String> _imageCache = {};

  Future<String> getCachedImage(String level, String theme) async {
    final cacheKey = '$level:$theme';

    if (_imageCache.containsKey(cacheKey)) {
      print('📦 Using cached image for $cacheKey');
      return _imageCache[cacheKey]!;
    }

    final imageUrl = await generateEducationalScene(level: level, theme: theme);
    _imageCache[cacheKey] = imageUrl;
    return imageUrl;
  }

  // API 헬스 체크 및 잔액 확인
  Future<Map<String, dynamic>> checkAPIHealth() async {
    try {
      final response = await _dio.get(
        '/user/account',
        options: Options(
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Accept': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final credits = data['credits'] ?? 0.0;
        print('✅ [StableDiffusion] API Health Check:');
        print('   - Status: Active');
        print('   - Credits: \$${credits.toStringAsFixed(2)}');
        print('   - Email: ${data['email'] ?? 'Unknown'}');
        
        return {
          'healthy': true,
          'credits': credits,
          'email': data['email'],
          'message': credits > 0 ? 'API is ready' : 'Insufficient credits',
        };
      } else {
        return {
          'healthy': false,
          'message': 'API returned status ${response.statusCode}',
        };
      }
    } catch (e) {
      print('❌ [StableDiffusion] Health check failed: $e');
      return {
        'healthy': false,
        'message': 'Health check failed: ${e.toString()}',
      };
    }
  }

  // 에러 메시지 파싱 및 사용자 친화적 메시지 변환
  String _parseErrorMessage(dynamic error) {
    if (error.toString().contains('401')) {
      return 'Invalid API key. Please check your STABILITY_API_KEY in .env file';
    } else if (error.toString().contains('402')) {
      return 'Insufficient credits. Please add credits to your Stability AI account';
    } else if (error.toString().contains('400')) {
      return 'Invalid request parameters. Checking dimension compatibility...';
    } else if (error.toString().contains('429')) {
      return 'Rate limit exceeded. Please wait a moment before trying again';
    } else if (error.toString().contains('500') || error.toString().contains('503')) {
      return 'Stability AI service is temporarily unavailable. Using fallback...';
    }
    return 'Unknown error occurred. Using fallback image...';
  }

  // 시나리오별 최적 스타일 프리셋 선택
  String _getStylePreset(String? theme) {
    final presets = {
      'street': 'photographic',
      'restaurant': 'photographic', 
      'park': 'photographic',
      'office': 'photographic',
      'home': 'photographic',
    };
    
    return presets[theme] ?? 'photographic';
  }

  // 프로덕션 레벨 폴백 이미지 시스템
  Future<String> _getFallbackImage(String theme, String level) async {
    print('🔄 [StableDiffusion] Activating fallback image strategy');
    
    // 1차 폴백: Unsplash API (고품질 실제 사진)
    try {
      final unsplashKeywords = {
        'street': 'city,street,urban,people',
        'restaurant': 'restaurant,dining,interior,food',
        'park': 'park,nature,outdoor,recreation',
        'office': 'office,workplace,business,professional',
        'home': 'home,interior,living,family',
      };
      
      final keywords = unsplashKeywords[theme] ?? 'people,daily,life';
      final size = LEVEL_DIMENSIONS[level] ?? {'width': 1024, 'height': 1024};
      final unsplashUrl = 'https://source.unsplash.com/${size['width']}x${size['height']}/?$keywords';
      
      print('   ✓ Using Unsplash: $unsplashUrl');
      return unsplashUrl;
      
    } catch (e) {
      // 2차 폴백: Picsum (Lorem Picsum - 범용 플레이스홀더)
      try {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final picsumUrl = 'https://picsum.photos/1024/1024?random=$timestamp';
        print('   ✓ Using Picsum: $picsumUrl');
        return picsumUrl;
        
      } catch (e) {
        // 3차 폴백: 로컬 에셋 (최후의 수단)
        print('   ✓ Using local asset fallback');
        return 'assets/images/fallback_${theme ?? 'default'}.jpg';
      }
    }
  }

  // 비용 최적화를 위한 배치 생성
  Future<List<String>> generateBatch({
    required List<String> themes,
    required String level,
    int maxConcurrent = 3,
  }) async {
    print('🎨 [StableDiffusion] Starting batch generation for ${themes.length} themes');
    
    final results = <String>[];
    final chunks = <List<String>>[];
    
    // 청크로 나누기 (동시 요청 제한)
    for (int i = 0; i < themes.length; i += maxConcurrent) {
      final end = (i + maxConcurrent < themes.length) ? i + maxConcurrent : themes.length;
      chunks.add(themes.sublist(i, end));
    }
    
    // 청크별로 병렬 처리
    for (final chunk in chunks) {
      final futures = chunk.map((theme) => 
        generateEducationalScene(level: level, theme: theme)
      ).toList();
      
      final chunkResults = await Future.wait(futures);
      results.addAll(chunkResults);
      
      // Rate limiting을 위한 딜레이
      if (chunks.indexOf(chunk) < chunks.length - 1) {
        await Future.delayed(Duration(seconds: 1));
      }
    }
    
    print('✅ [StableDiffusion] Batch generation complete: ${results.length} images');
    return results;
  }
}
