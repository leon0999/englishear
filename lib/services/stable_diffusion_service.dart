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
        'dimensions': ALLOWED_DIMENSIONS['square']!,
        'cfg_scale': 7.0,
        'steps': 20, // 빠른 생성
      },
      'intermediate': {
        'prompt': _buildIntermediatePrompt(theme),
        'dimensions': ALLOWED_DIMENSIONS['landscape']!,
        'cfg_scale': 7.5,
        'steps': 25,
      },
      'advanced': {
        'prompt': _buildAdvancedPrompt(theme),
        'dimensions': ALLOWED_DIMENSIONS['landscape']!,
        'cfg_scale': 8.0,
        'steps': 30,
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

  String _buildBeginnerPrompt(String? theme) {
    final actualTheme = theme ?? 'daily life activity';
    return 'Simple cartoon illustration of $actualTheme, bright colors, friendly, educational, no text';
  }

  String _buildIntermediatePrompt(String? theme) {
    final actualTheme = theme ?? 'people in modern office';
    return 'Realistic scene of $actualTheme, professional, natural lighting, clear details, no text';
  }

  String _buildAdvancedPrompt(String? theme) {
    final actualTheme = theme ?? 'busy city street';
    return 'Complex photorealistic $actualTheme, multiple activities, detailed environment, no text';
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
