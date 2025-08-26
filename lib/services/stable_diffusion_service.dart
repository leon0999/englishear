import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class StableDiffusionService {
  late final Dio _dio;
  late final String _apiKey;
  
  StableDiffusionService() {
    _apiKey = dotenv.env['STABILITY_API_KEY'] ?? '';
    _dio = Dio(BaseOptions(
      baseUrl: dotenv.env['STABILITY_BASE_URL'] ?? 'https://api.stability.ai/v1',
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
    ));
  }

  // Stable Diffusion XL로 이미지 생성 (DALL-E보다 95% 저렴)
  Future<String> generateImage({
    required String prompt,
    String? negativePrompt,
    int width = 1024,
    int height = 1024,
    int steps = 30,
    double cfgScale = 7.0,
  }) async {
    try {
      // 프롬프트 최적화
      final optimizedPrompt = _optimizePrompt(prompt);
      final defaultNegativePrompt = 'text, letters, numbers, watermark, signature, blurry, low quality';
      
      final response = await _dio.post(
        '/generation/stable-diffusion-xl-1024-v1-0/text-to-image',
        options: Options(
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
        data: {
          'text_prompts': [
            {
              'text': optimizedPrompt,
              'weight': 1.0,
            },
            if (negativePrompt != null || defaultNegativePrompt.isNotEmpty)
              {
                'text': negativePrompt ?? defaultNegativePrompt,
                'weight': -1.0,
              },
          ],
          'cfg_scale': cfgScale,
          'height': height,
          'width': width,
          'samples': 1,
          'steps': steps,
          'style_preset': 'photographic', // 다른 옵션: 3d-model, anime, cinematic, comic-book
        },
      );
      
      // Base64 이미지 처리
      if (response.data['artifacts'] != null && response.data['artifacts'].isNotEmpty) {
        final base64Image = response.data['artifacts'][0]['base64'];
        return 'data:image/png;base64,$base64Image';
      }
      
      return '';
    } catch (e) {
      print('Error generating image with Stable Diffusion: $e');
      throw Exception('Failed to generate image: $e');
    }
  }

  // 교육용 장면 이미지 생성 (레벨별)
  Future<String> generateEducationalScene({
    required String level,
    String? theme,
  }) async {
    print('🎨 [StableDiffusion] Starting image generation for level: $level');
    final Map<String, Map<String, dynamic>> levelConfigs = {
      'beginner': {
        'prompt': _buildBeginnerPrompt(theme),
        'style': 'digital-art',
        'cfg_scale': 7.0,
        'steps': 25,
      },
      'intermediate': {
        'prompt': _buildIntermediatePrompt(theme),
        'style': 'photographic',
        'cfg_scale': 7.5,
        'steps': 30,
      },
      'advanced': {
        'prompt': _buildAdvancedPrompt(theme),
        'style': 'photographic',
        'cfg_scale': 8.0,
        'steps': 35,
      },
    };
    
    final config = levelConfigs[level] ?? levelConfigs['beginner']!;
    
    try {
      print('🚀 [StableDiffusion] Sending API request to Stability AI...');
      print('📝 [StableDiffusion] Prompt: ${config['prompt']}');
      final response = await _dio.post(
        '/generation/stable-diffusion-xl-1024-v1-0/text-to-image',
        options: Options(
          headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
        ),
        data: {
          'text_prompts': [
            {
              'text': config['prompt'],
              'weight': 1.0,
            },
            {
              'text': 'text, words, letters, numbers, watermark, logo, signature, ugly, blurry',
              'weight': -1.0,
            },
          ],
          'cfg_scale': config['cfg_scale'],
          'height': 512,  // 🔥 512로 줄여서 속도 향상
          'width': 512,   // 🔥 512로 줄여서 속도 향상
          'samples': 1,
          'steps': 20,    // 🔥 20으로 줄여서 속도 향상
          'style_preset': config['style'],
        },
      );
      
      print('✅ [StableDiffusion] API Response received!');
      if (response.data['artifacts'] != null && response.data['artifacts'].isNotEmpty) {
        final base64Image = response.data['artifacts'][0]['base64'];
        print('🖼️ [StableDiffusion] Image generated successfully! Size: ${base64Image.length} bytes');
        return 'data:image/png;base64,$base64Image';
      }
      
      print('❌ [StableDiffusion] No image in response');
      return '';
    } catch (e) {
      print('❌ [StableDiffusion] Error generating educational scene: $e');
      if (e is DioException) {
        print('❌ [StableDiffusion] Status: ${e.response?.statusCode}');
        print('❌ [StableDiffusion] Response: ${e.response?.data}');
        
        // API 키 확인
        if (e.response?.statusCode == 401) {
          print('🔑 [StableDiffusion] API Key might be invalid');
        } else if (e.response?.statusCode == 404) {
          print('🔍 [StableDiffusion] Engine not found - check engine ID');
        }
      }
      
      // 테스트용 폴백 이미지 반환
      print('🔄 [StableDiffusion] Using fallback image for testing');
      final fallbackUrl = 'https://picsum.photos/1024/1024?random=${DateTime.now().millisecondsSinceEpoch}';
      print('🖼️ [StableDiffusion] Fallback URL: $fallbackUrl');
      return fallbackUrl;
    }
  }

  // Base64를 Uint8List로 변환 (캐싱용)
  Uint8List base64ToImage(String base64String) {
    // data:image/png;base64, 제거
    final base64 = base64String.replaceFirst(RegExp(r'data:image/[^;]+;base64,'), '');
    return base64Decode(base64);
  }

  // 프롬프트 최적화
  String _optimizePrompt(String prompt) {
    // Stable Diffusion에 최적화된 프롬프트 생성
    final optimizations = [
      'high quality',
      'detailed',
      '8k resolution',
      'professional photography',
    ];
    
    return '$prompt, ${optimizations.join(', ')}';
  }

  // 초급자용 프롬프트 생성
  String _buildBeginnerPrompt(String? theme) {
    final defaultTheme = 'daily life';
    final actualTheme = theme ?? defaultTheme;
    
    return '''Simple, colorful illustration of $actualTheme scene,
    cartoon style, bright colors, friendly atmosphere,
    clear composition, child-friendly, educational,
    no text or letters, clean background''';
  }

  // 중급자용 프롬프트 생성
  String _buildIntermediatePrompt(String? theme) {
    final defaultTheme = 'modern workplace';
    final actualTheme = theme ?? defaultTheme;
    
    return '''Realistic scene of $actualTheme,
    professional environment, natural lighting,
    diverse people interacting, modern setting,
    clear details, no text or signage,
    semi-photorealistic style''';
  }

  // 고급자용 프롬프트 생성
  String _buildAdvancedPrompt(String? theme) {
    final defaultTheme = 'urban environment';
    final actualTheme = theme ?? defaultTheme;
    
    return '''Complex $actualTheme scene,
    photorealistic, multiple activities happening,
    detailed architecture and environment,
    diverse crowd, dynamic composition,
    professional photography, golden hour lighting,
    no visible text or signs''';
  }

  // 이미지 업스케일 (선택적 기능)
  Future<String> upscaleImage({
    required String imageBase64,
    int scaleFactor = 2,
  }) async {
    try {
      final response = await _dio.post(
        '/generation/esrgan-v1-x2plus/image-to-image/upscale',
        data: {
          'image': imageBase64.replaceFirst(RegExp(r'data:image/[^;]+;base64,'), ''),
          'width': 2048, // 최대 2048
        },
      );
      
      if (response.data['artifacts'] != null && response.data['artifacts'].isNotEmpty) {
        final base64Image = response.data['artifacts'][0]['base64'];
        return 'data:image/png;base64,$base64Image';
      }
      
      return imageBase64; // 실패시 원본 반환
    } catch (e) {
      print('Error upscaling image: $e');
      return imageBase64; // 실패시 원본 반환
    }
  }
}