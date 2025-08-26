// lib/services/stable_diffusion_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class StableDiffusionService {
  late final Dio _dio;
  late final String _apiKey;

  // SDXL 지원 크기
  static const Map<String, List<int>> ALLOWED_DIMENSIONS = {
    'square': [1024, 1024],
    'landscape': [1152, 896],
    'portrait': [896, 1152],
    'wide': [1344, 768],
    'tall': [768, 1344],
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
    print('🎨 [StableDiffusion] Starting image generation for level: $level');

    final Map<String, Map<String, dynamic>> levelConfigs = {
      'beginner': {
        'prompt': _buildBeginnerPrompt(theme),
        'dimensions': [768, 768],  // 더 작은 크기로 빠른 생성
        'cfg_scale': 7.0,
        'steps': 15,  // 더 빠른 생성
      },
      'intermediate': {
        'prompt': _buildIntermediatePrompt(theme),
        'dimensions': ALLOWED_DIMENSIONS['portrait']!,  // 896x1152
        'cfg_scale': 7.5,
        'steps': 20,
      },
      'advanced': {
        'prompt': _buildAdvancedPrompt(theme),
        'dimensions': ALLOWED_DIMENSIONS['square']!,  // 1024x1024
        'cfg_scale': 8.0,
        'steps': 25,
      },
    };

    final config = levelConfigs[level] ?? levelConfigs['beginner']!;

    try {
      print(
          '🚀 [StableDiffusion] Sending request with dimensions: ${config['dimensions'][0]}x${config['dimensions'][1]}');

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
              'text':
                  'text, words, letters, numbers, watermark, logo, signature',
              'weight': -1.0,
            },
          ],
          'cfg_scale': config['cfg_scale'],
          'width': config['dimensions'][0], // ✅ 올바른 크기 사용
          'height': config['dimensions'][1], // ✅ 올바른 크기 사용
          'samples': 1,
          'steps': config['steps'],
        },
      );

      if (response.statusCode == 200) {
        if (response.data['artifacts'] != null &&
            response.data['artifacts'].isNotEmpty) {
          final base64Image = response.data['artifacts'][0]['base64'];
          print('✅ [StableDiffusion] Image generated successfully!');
          return 'data:image/png;base64,$base64Image';
        }
      } else if (response.statusCode == 401) {
        print('❌ [StableDiffusion] Invalid API key');
        print('Please check your STABILITY_API_KEY in .env file');
      } else if (response.statusCode == 400) {
        print('❌ [StableDiffusion] Bad request: ${response.data}');
      }

      throw Exception('Failed to generate image');
    } catch (e) {
      print('❌ [StableDiffusion] Error: $e');

      // Picsum 폴백 (테스트용)
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fallbackUrl = 'https://picsum.photos/1024/1024?random=$timestamp';
      print('🔄 Using fallback image: $fallbackUrl');
      return fallbackUrl;
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
}
