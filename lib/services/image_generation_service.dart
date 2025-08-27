import 'openai_service.dart';
import 'stable_diffusion_service.dart';
import 'api_cost_optimizer.dart';

enum AIImageProvider {
  stableDiffusion, // 기본 (95% 저렴)
  openAI,         // 고품질 옵션
  cached,         // 캐시된 이미지
  fallback,       // 폴백 (무료)
}

class ImageGenerationService {
  late final OpenAIService _openAIService;
  late final StableDiffusionService _stableDiffusionService;
  late final ApiCostOptimizer _optimizer;
  
  // 싱글톤 패턴
  static final ImageGenerationService _instance = ImageGenerationService._internal();
  factory ImageGenerationService() => _instance;
  
  ImageGenerationService._internal() {
    _openAIService = OpenAIService();
    _stableDiffusionService = StableDiffusionService();
    _optimizer = ApiCostOptimizer();
  }

  Future<void> initialize() async {
    await _optimizer.initialize();
  }
  
  // 통합 이미지 생성 메서드
  Future<Map<String, dynamic>> generateLearningContent({
    required String level,
    required String userId,
    required bool isPremium,
    String? theme,
    AIImageProvider provider = AIImageProvider.stableDiffusion,
  }) async {
    try {
      // 1. 사용량 체크
      if (!await _optimizer.canUseApi(userId, isPremium)) {
        return {
          'error': true,
          'message': 'Daily limit reached. ${isPremium ? 'Premium' : 'Free'} users have ${_optimizer.getRemainingUsage(userId, isPremium)} uses remaining today.',
          'imageUrl': _getFallbackImage(),
          'sentence': _getFallbackSentence(level),
          'keywords': _getFallbackKeywords(level),
        };
      }

      // 2. 캐시 확인
      final cacheKey = '$theme:$level';
      final cachedImage = _optimizer.getCachedImage(cacheKey, level);
      if (cachedImage != null && provider == AIImageProvider.cached) {
        final cachedSentence = _optimizer.getCachedSentence(cacheKey, level);
        if (cachedSentence != null) {
          return {
            'cached': true,
            'imageUrl': cachedImage,
            ...cachedSentence,
          };
        }
      }

      // 3. 이미지 생성 (DALL-E 3 우선 사용)
      String imageUrl = '';
      Map<String, dynamic> sentenceData = {};

      switch (provider) {
        case AIImageProvider.stableDiffusion:
          // Stable Diffusion은 크레딧이 없으므로 DALL-E 3로 대체
          imageUrl = await _generateWithDALLE(level, theme);
          sentenceData = await _generateSentenceWithGPT(imageUrl, level);
          break;
          
        case AIImageProvider.openAI:
          // DALL-E 3 (기본 옵션)
          imageUrl = await _generateWithDALLE(level, theme);
          sentenceData = await _generateSentenceWithGPT(imageUrl, level);
          break;
          
        case AIImageProvider.cached:
        case AIImageProvider.fallback:
          // 폴백 데이터 사용
          final fallbackData = _getPreGeneratedContent(level);
          imageUrl = fallbackData['imageUrl']!;
          sentenceData = {
            'sentence': fallbackData['sentence'],
            'keywords': fallbackData['keywords'],
            'difficulty': fallbackData['difficulty'],
          };
          break;
      }

      // 4. 캐시 저장
      if (imageUrl.isNotEmpty && provider != AIImageProvider.fallback) {
        await _optimizer.cacheImage(cacheKey, level, imageUrl);
        await _optimizer.cacheSentence(cacheKey, level, sentenceData);
      }

      // 5. 사용량 기록
      await _optimizer.recordApiUsage(userId);

      // 6. 결과 반환
      return {
        'success': true,
        'imageUrl': imageUrl,
        'provider': provider.toString(),
        'remainingUses': _optimizer.getRemainingUsage(userId, isPremium),
        ...sentenceData,
      };

    } catch (e) {
      print('Error generating learning content: $e');
      
      // 에러시 폴백 데이터 반환
      final fallbackData = _getPreGeneratedContent(level);
      return {
        'error': true,
        'message': 'Failed to generate content. Using fallback data.',
        'imageUrl': fallbackData['imageUrl']!,
        'sentence': fallbackData['sentence'],
        'keywords': fallbackData['keywords'],
        'difficulty': fallbackData['difficulty'],
      };
    }
  }

  // Stable Diffusion으로 이미지 생성
  Future<String> _generateWithStableDiffusion(String level, String? theme) async {
    try {
      final imageUrl = await _stableDiffusionService.generateEducationalScene(
        level: level,
        theme: theme,
      );
      
      // StableDiffusion에서 이미 fallback 이미지를 반환하므로 그대로 사용
      print('📸 [ImageGenService] Received from StableDiffusion: ${imageUrl.substring(0, 50)}...');
      return imageUrl;
    } catch (e) {
      print('Stable Diffusion error in ImageGenService: $e');
      return _getFallbackImage();
    }
  }

  // DALL-E로 이미지 생성
  Future<String> _generateWithDALLE(String level, String? theme) async {
    try {
      final imageUrl = await _openAIService.generateSceneImage(
        level: level,
        scenario: theme,
      );
      
      if (imageUrl.isNotEmpty) {
        print('✅ [ImageGenService] DALL-E 3 image received');
        return imageUrl;
      }
      
      // 이미지 생성 실패시 폴백
      return _getFallbackImage();
    } catch (e) {
      print('❌ [ImageGenService] DALL-E error: $e');
      return _getFallbackImage();
    }
  }

  // GPT로 문장 생성
  Future<Map<String, dynamic>> _generateSentenceWithGPT(String imageUrl, String level) async {
    try {
      // 이미지 설명을 기반으로 문장 생성
      final description = _describeImageForGPT(level);
      return await _openAIService.generateSentenceForImage(
        imageDescription: description,
        level: level,
      );
    } catch (e) {
      print('GPT sentence generation error: $e');
      return _getFallbackSentenceData(level);
    }
  }

  // 발음 평가
  Future<Map<String, dynamic>> evaluatePronunciation({
    required String userSpeech,
    required String correctSentence,
    required List<String> keywords,
  }) async {
    try {
      return await _openAIService.evaluatePronunciation(
        userSpeech: userSpeech,
        correctSentence: correctSentence,
        keywords: keywords,
      );
    } catch (e) {
      print('Evaluation error: $e');
      // 폴백 평가
      return _generateFallbackEvaluation(userSpeech, correctSentence, keywords);
    }
  }

  // AI 튜터 응답
  Future<String> getAITutorHelp({
    required String userMessage,
    required String context,
  }) async {
    try {
      return await _openAIService.getAITutorResponse(
        userMessage: userMessage,
        context: context,
      );
    } catch (e) {
      print('AI Tutor error: $e');
      return 'Let me help you with that. Try breaking down the sentence into smaller parts and practice each word slowly.';
    }
  }

  // 캐시 정리 (주기적으로 실행)
  Future<void> cleanupCache() async {
    await _optimizer.cleanupCache();
  }

  // 비용 분석
  Map<String, double> getCostAnalysis(int activeUsers, double premiumRate) {
    return _optimizer.calculateMonthlyCosts(activeUsers, premiumRate);
  }

  // === 헬퍼 메서드들 ===

  String _describeImageForGPT(String level) {
    final descriptions = {
      'beginner': 'A simple daily life scene with people doing common activities',
      'intermediate': 'A workplace or social setting with professional interactions',
      'advanced': 'A complex urban environment with multiple activities and interactions',
    };
    return descriptions[level] ?? descriptions['beginner']!;
  }

  String _getFallbackImage() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'https://picsum.photos/1024/1024?random=$timestamp';
  }

  String _getFallbackSentence(String level) {
    final sentences = {
      'beginner': 'The cat is sleeping on the sofa.',
      'intermediate': 'She has been working on this project since morning.',
      'advanced': 'Despite the challenging circumstances, the team managed to deliver exceptional results.',
    };
    return sentences[level] ?? sentences['beginner']!;
  }

  List<String> _getFallbackKeywords(String level) {
    final keywords = {
      'beginner': ['cat', 'sleeping', 'sofa'],
      'intermediate': ['working', 'project', 'morning'],
      'advanced': ['challenging', 'circumstances', 'exceptional'],
    };
    return keywords[level] ?? keywords['beginner']!;
  }

  Map<String, dynamic> _getFallbackSentenceData(String level) {
    return {
      'sentence': _getFallbackSentence(level),
      'keywords': _getFallbackKeywords(level),
      'difficulty': level == 'beginner' ? 1 : level == 'intermediate' ? 3 : 5,
      'grammar_point': 'Practice basic sentence structure',
      'pronunciation_tips': ['Speak slowly', 'Focus on clear articulation'],
    };
  }

  Map<String, dynamic> _generateFallbackEvaluation(
    String userSpeech,
    String correctSentence,
    List<String> keywords,
  ) {
    // 간단한 폴백 평가 로직
    final userWords = userSpeech.toLowerCase().split(' ');
    final correctWords = correctSentence.toLowerCase().split(' ');
    final matchedKeywords = keywords.where((k) => userWords.contains(k.toLowerCase())).toList();
    
    final accuracy = (userWords.length / correctWords.length * 100).clamp(0, 100).round();
    
    return {
      'overall_score': accuracy,
      'pronunciation_score': accuracy - 5,
      'fluency_score': accuracy - 10,
      'grammar_score': accuracy,
      'matched_keywords': matchedKeywords,
      'missed_keywords': keywords.where((k) => !matchedKeywords.contains(k)).toList(),
      'feedback': accuracy > 70 ? 'Good job! Keep practicing!' : 'Keep trying! You\'re improving!',
      'improvement_tips': [
        'Practice speaking more slowly',
        'Focus on pronouncing each word clearly',
      ],
    };
  }

  // 미리 생성된 콘텐츠 (폴백용)
  Map<String, dynamic> _getPreGeneratedContent(String level) {
    final contents = {
      'beginner': [
        {
          'imageUrl': 'https://picsum.photos/1024/1024?random=101',
          'keywords': ['walking', 'dog', 'park'],
          'sentence': 'A woman is walking her dog in the park',
          'difficulty': 1,
        },
        {
          'imageUrl': 'https://picsum.photos/1024/1024?random=102',
          'keywords': ['reading', 'book', 'library'],
          'sentence': 'The boy is reading a book in the library',
          'difficulty': 1,
        },
      ],
      'intermediate': [
        {
          'imageUrl': 'https://picsum.photos/1024/1024?random=201',
          'keywords': ['presenting', 'meeting', 'colleagues'],
          'sentence': 'She has been presenting her ideas to colleagues all morning',
          'difficulty': 3,
        },
        {
          'imageUrl': 'https://picsum.photos/1024/1024?random=202',
          'keywords': ['developing', 'software', 'team'],
          'sentence': 'The team is developing new software for the client',
          'difficulty': 3,
        },
      ],
      'advanced': [
        {
          'imageUrl': 'https://picsum.photos/1024/1024?random=301',
          'keywords': ['implementing', 'strategic', 'initiatives'],
          'sentence': 'The company has been implementing strategic initiatives to enhance market competitiveness',
          'difficulty': 5,
        },
        {
          'imageUrl': 'https://picsum.photos/1024/1024?random=302',
          'keywords': ['navigating', 'complex', 'negotiations'],
          'sentence': 'Successfully navigating complex negotiations requires both patience and expertise',
          'difficulty': 5,
        },
      ],
    };
    
    final levelContents = contents[level] ?? contents['beginner']!;
    final randomIndex = DateTime.now().millisecond % levelContents.length;
    return levelContents[randomIndex];
  }
}