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

  // 시나리오별 명확한 프롬프트 생성
  String _buildBeginnerPrompt(String? theme) {
    final scenarios = {
      'street': 'Clear urban street scene with visible pedestrians walking on sidewalk, cars on road, storefronts, daytime, bright colors, no text or signs',
      'restaurant': 'Interior restaurant scene, people sitting at tables eating, waiter serving food, bright lighting, clear view, no text',
      'park': 'Open park with green grass, people walking dogs, children playing on playground, trees, sunny day, no text',
      'office': 'Modern office interior, people working at desks with computers, bright lighting, clear workspace, no text',
      'home': 'Cozy home interior, family in living room, furniture visible, warm lighting, no text',
    };
    
    return scenarios[theme] ?? 'Simple daily life scene with people doing activities, bright colors, clear composition, no text';
  }

  String _buildIntermediatePrompt(String? theme) {
    final scenarios = {
      'street': 'Photorealistic busy street, multiple pedestrians, shops, traffic, urban environment, natural lighting, high detail, no text',
      'restaurant': 'Realistic restaurant interior, customers dining, waiters serving, detailed decor, ambient lighting, no text',
      'park': 'Natural park scene, people jogging, picnic areas, lake or pond, trees and paths, golden hour light, no text',
      'office': 'Professional office environment, meeting rooms, people collaborating, modern furniture, natural light, no text',
      'home': 'Modern home interior, family activities, kitchen or living area, detailed furniture, warm atmosphere, no text',
    };
    
    return scenarios[theme] ?? 'Realistic scene with people interacting, professional quality, natural lighting, no text';
  }

  String _buildAdvancedPrompt(String? theme) {
    final scenarios = {
      'street': 'Complex urban intersection, crowds of people, multiple shops, vehicles, street vendors, detailed architecture, cinematic lighting, no text',
      'restaurant': 'Upscale restaurant full scene, multiple tables, kitchen visible, staff and customers, elegant decor, atmospheric lighting, no text',
      'park': 'Large public park, multiple activities, sports fields, walking paths, water features, diverse crowd, dynamic composition, no text',
      'office': 'Corporate headquarters interior, open floor plan, multiple departments, glass walls, people in meetings, modern design, no text',
      'home': 'Multi-room home view, family members in different activities, detailed interior design, lifestyle photography, no text',
    };
    
    return scenarios[theme] ?? 'Complex photorealistic scene, multiple focal points, detailed environment, cinematic quality, no text';
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
