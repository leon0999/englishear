import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:retry/retry.dart';
import '../core/logger.dart';
import '../core/exceptions.dart';
import '../models/openai_models.dart';
import 'cache_service.dart';

class OpenAIServiceRefactored {
  late final Dio _dio;
  late final OpenAIConfig _config;
  late final OpenAICacheManager _cacheManager;
  late final RetryOptions _retryOptions;

  // Singleton pattern
  static OpenAIServiceRefactored? _instance;
  
  factory OpenAIServiceRefactored() {
    _instance ??= OpenAIServiceRefactored._internal();
    return _instance!;
  }

  OpenAIServiceRefactored._internal() {
    _initialize();
  }

  void _initialize() {
    // Load configuration from environment
    _config = OpenAIConfig(
      apiKey: dotenv.env['OPENAI_API_KEY'] ?? '',
      baseUrl: dotenv.env['OPENAI_BASE_URL'] ?? 'https://api.openai.com/v1',
      connectTimeoutSeconds: 30,
      receiveTimeoutSeconds: 30,
      maxRetries: 3,
      useCache: dotenv.env['USE_CACHE'] == 'true',
      cacheExpiryHours: int.tryParse(dotenv.env['CACHE_EXPIRY_HOURS'] ?? '24') ?? 24,
    );

    // Validate configuration
    if (_config.apiKey.isEmpty) {
      throw ConfigurationException(
        message: 'OpenAI API key is not configured. Please check your .env file.',
      );
    }

    // Initialize Dio with interceptors
    _dio = Dio(BaseOptions(
      baseUrl: _config.baseUrl,
      connectTimeout: Duration(seconds: _config.connectTimeoutSeconds),
      receiveTimeout: Duration(seconds: _config.receiveTimeoutSeconds),
    ));

    // Add interceptors
    _dio.interceptors.add(_AuthInterceptor(_config.apiKey));
    _dio.interceptors.add(_LoggingInterceptor());
    _dio.interceptors.add(_ErrorInterceptor());

    // Initialize retry options
    _retryOptions = RetryOptions(
      maxAttempts: _config.maxRetries,
      delayFactor: const Duration(seconds: 2),
      maxDelay: const Duration(seconds: 30),
      randomizationFactor: 0.25,
    );

    Logger.info('OpenAI Service initialized successfully');
  }

  // Initialize cache manager (needs to be called asynchronously)
  Future<void> initializeCache() async {
    try {
      final cacheService = await CacheService.create(
        cacheExpiryHours: _config.cacheExpiryHours,
      );
      _cacheManager = OpenAICacheManager(cacheService);
      Logger.info('Cache manager initialized');
    } catch (e) {
      Logger.warning('Failed to initialize cache manager', data: e);
      // Continue without cache
    }
  }

  // Generate scene image with DALL-E 3
  Future<String> generateSceneImage({
    required DifficultyLevel level,
    required ScenarioType scenario,
    String? customPrompt,
    bool useCache = true,
  }) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      final prompt = customPrompt ?? _buildEnhancedPrompt(level, scenario);
      
      // Check cache first if enabled
      if (_config.useCache && useCache) {
        final cachedImage = await _cacheManager.getCachedImage(
          prompt,
          'standard',
          '1024x1024',
        );
        if (cachedImage != null) {
          Logger.info('Image retrieved from cache');
          return cachedImage;
        }
      }

      Logger.info('Generating image for ${scenario.displayName} (${level.name})');

      final request = ImageGenerationRequest(
        prompt: prompt,
        model: 'dall-e-3',
        n: 1,
        size: '1024x1024',
        quality: 'standard',
        style: 'natural',
        responseFormat: 'b64_json',
      );

      final response = await _retryOptions.retry(
        () => _dio.post(
          '/images/generations',
          data: request.toJson(),
        ),
        retryIf: (e) => _isRetryableError(e),
      );

      final imageResponse = ImageGenerationResponse.fromJson(response.data);
      
      if (imageResponse.data.isEmpty) {
        throw ImageGenerationException(
          message: 'No image data returned from API',
        );
      }

      String imageData = '';
      final image = imageResponse.data.first;
      
      if (image.b64Json != null) {
        imageData = 'data:image/png;base64,${image.b64Json}';
        Logger.info('Image generated successfully (Base64)');
      } else if (image.url != null) {
        imageData = image.url!;
        Logger.info('Image generated successfully (URL)');
      } else {
        throw ImageGenerationException(
          message: 'Invalid image data format',
        );
      }

      // Cache the result if enabled
      if (_config.useCache && useCache && imageData.isNotEmpty) {
        await _cacheManager.cacheImage(prompt, 'standard', '1024x1024', imageData);
      }

      Logger.performance('Image generation', stopwatch.elapsed);
      return imageData;

    } catch (e) {
      Logger.error('Failed to generate image', error: e);
      if (e is DioException) {
        throw OpenAIException.fromDioError(e);
      }
      rethrow;
    } finally {
      stopwatch.stop();
    }
  }

  // Generate learning content for an image
  Future<LearningContent> generateSentenceForImage({
    required String imageDescription,
    required DifficultyLevel level,
    bool useCache = true,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Check cache first if enabled
      if (_config.useCache && useCache) {
        final cached = await _cacheManager.getCachedLearningContent(
          imageDescription,
          level.name,
        );
        if (cached != null) {
          Logger.info('Learning content retrieved from cache');
          return LearningContent.fromJson(cached);
        }
      }

      Logger.info('Generating learning content for ${level.name} level');

      final systemPrompt = _buildLearningSystemPrompt(level);
      final userPrompt = 'Generate learning content for this scene: $imageDescription';

      final request = ChatCompletionRequest(
        model: 'gpt-4-turbo-preview',
        messages: [
          ChatMessage(role: 'system', content: systemPrompt),
          ChatMessage(role: 'user', content: userPrompt),
        ],
        temperature: 0.7,
        maxTokens: 300,
        responseFormat: {'type': 'json_object'},
      );

      final response = await _retryOptions.retry(
        () => _dio.post(
          '/chat/completions',
          data: request.toJson(),
        ),
        retryIf: (e) => _isRetryableError(e),
      );

      final chatResponse = ChatCompletionResponse.fromJson(response.data);
      
      if (chatResponse.choices.isEmpty) {
        throw OpenAIException(
          message: 'No response generated',
          code: 'EMPTY_RESPONSE',
        );
      }

      final content = json.decode(chatResponse.choices.first.message.content);
      final learningContent = LearningContent.fromJson(content);

      // Cache the result if enabled
      if (_config.useCache && useCache) {
        await _cacheManager.cacheLearningContent(
          imageDescription,
          level.name,
          content,
        );
      }

      Logger.performance('Content generation', stopwatch.elapsed);
      Logger.usage('content_generated', metadata: {
        'level': level.name,
        'tokens': chatResponse.usage.totalTokens,
      });

      return learningContent;

    } catch (e) {
      Logger.error('Failed to generate learning content', error: e);
      if (e is DioException) {
        throw OpenAIException.fromDioError(e);
      }
      rethrow;
    } finally {
      stopwatch.stop();
    }
  }

  // Evaluate user pronunciation
  Future<PronunciationEvaluation> evaluatePronunciation({
    required String userSpeech,
    required String correctSentence,
    required List<String> keywords,
    bool useCache = true,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      // Check cache first if enabled
      if (_config.useCache && useCache) {
        final cached = await _cacheManager.getCachedEvaluation(
          userSpeech,
          correctSentence,
        );
        if (cached != null) {
          Logger.info('Evaluation retrieved from cache');
          return PronunciationEvaluation.fromJson(cached);
        }
      }

      Logger.info('Evaluating pronunciation');

      final systemPrompt = _buildEvaluationSystemPrompt();
      final userPrompt = '''Evaluate this speech:
Correct sentence: "$correctSentence"
Keywords to check: ${keywords.join(', ')}
User said: "$userSpeech"''';

      final request = ChatCompletionRequest(
        model: 'gpt-4-turbo-preview',
        messages: [
          ChatMessage(role: 'system', content: systemPrompt),
          ChatMessage(role: 'user', content: userPrompt),
        ],
        temperature: 0.3,
        maxTokens: 500,
        responseFormat: {'type': 'json_object'},
      );

      final response = await _retryOptions.retry(
        () => _dio.post(
          '/chat/completions',
          data: request.toJson(),
        ),
        retryIf: (e) => _isRetryableError(e),
      );

      final chatResponse = ChatCompletionResponse.fromJson(response.data);
      
      if (chatResponse.choices.isEmpty) {
        throw OpenAIException(
          message: 'No evaluation generated',
          code: 'EMPTY_RESPONSE',
        );
      }

      final content = json.decode(chatResponse.choices.first.message.content);
      final evaluation = PronunciationEvaluation.fromJson(content);

      // Cache the result if enabled (with shorter expiry)
      if (_config.useCache && useCache) {
        await _cacheManager.cacheEvaluation(
          userSpeech,
          correctSentence,
          content,
        );
      }

      Logger.performance('Pronunciation evaluation', stopwatch.elapsed);
      Logger.usage('pronunciation_evaluated', metadata: {
        'score': evaluation.overallScore,
        'tokens': chatResponse.usage.totalTokens,
      });

      return evaluation;

    } catch (e) {
      Logger.error('Failed to evaluate pronunciation', error: e);
      if (e is DioException) {
        throw OpenAIException.fromDioError(e);
      }
      rethrow;
    } finally {
      stopwatch.stop();
    }
  }

  // Get AI tutor response
  Future<String> getAITutorResponse({
    required String userMessage,
    required String context,
    List<ChatMessage>? conversationHistory,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      Logger.info('Getting AI tutor response');

      final messages = <ChatMessage>[
        ChatMessage(
          role: 'system',
          content: _buildTutorSystemPrompt(),
        ),
      ];

      // Add conversation history if provided
      if (conversationHistory != null && conversationHistory.isNotEmpty) {
        messages.addAll(conversationHistory.take(10)); // Limit history to last 10 messages
      }

      messages.add(ChatMessage(
        role: 'user',
        content: 'Context: $context\n\nStudent question: $userMessage',
      ));

      final request = ChatCompletionRequest(
        model: 'gpt-4-turbo-preview',
        messages: messages,
        temperature: 0.7,
        maxTokens: 200,
      );

      final response = await _retryOptions.retry(
        () => _dio.post(
          '/chat/completions',
          data: request.toJson(),
        ),
        retryIf: (e) => _isRetryableError(e),
      );

      final chatResponse = ChatCompletionResponse.fromJson(response.data);
      
      if (chatResponse.choices.isEmpty) {
        throw OpenAIException(
          message: 'No response generated',
          code: 'EMPTY_RESPONSE',
        );
      }

      final tutorResponse = chatResponse.choices.first.message.content;

      Logger.performance('Tutor response', stopwatch.elapsed);
      Logger.usage('tutor_interaction', metadata: {
        'tokens': chatResponse.usage.totalTokens,
      });

      return tutorResponse;

    } catch (e) {
      Logger.error('Failed to get tutor response', error: e);
      if (e is DioException) {
        // Provide fallback response on error
        return 'I apologize, but I\'m having trouble responding right now. Please try again.';
      }
      return 'Sorry, I couldn\'t process your request. Please try again later.';
    } finally {
      stopwatch.stop();
    }
  }

  // Helper method to check if error is retryable
  bool _isRetryableError(dynamic e) {
    if (e is DioException) {
      final exception = OpenAIException.fromDioError(e);
      return exception.isRetryable;
    }
    return false;
  }

  // Build enhanced prompt for image generation
  String _buildEnhancedPrompt(DifficultyLevel level, ScenarioType scenario) {
    final prompts = _getScenarioPrompts();
    final levelPrompts = prompts[level] ?? prompts[DifficultyLevel.beginner]!;
    final basePrompt = levelPrompts[scenario] ?? levelPrompts[ScenarioType.street]!;
    
    return '$basePrompt, high quality, clear composition, educational content, suitable for language learning, no text or signs';
  }

  // Get scenario-specific prompts
  Map<DifficultyLevel, Map<ScenarioType, String>> _getScenarioPrompts() {
    return {
      DifficultyLevel.beginner: {
        ScenarioType.street: 'A bright, friendly street scene with 3-4 people walking, clear storefronts, daytime, simple composition, educational illustration style',
        ScenarioType.restaurant: 'A cozy restaurant interior with 2-3 people eating at tables, warm lighting, simple decor, clear view, educational style',
        ScenarioType.park: 'A sunny park with 2-3 people, green trees, playground, simple activities, bright colors, educational illustration',
        ScenarioType.office: 'A modern office with 3 people working at computers, bright space, clean desks, educational style',
        ScenarioType.home: 'A warm home interior with family of 3-4, living room setting, cozy atmosphere, educational style',
        ScenarioType.airport: 'A simple airport terminal with travelers and signs, bright lighting, clear layout',
        ScenarioType.shopping: 'A shopping mall with stores and shoppers, bright atmosphere, simple scene',
        ScenarioType.school: 'A classroom with students and teacher, educational setting, bright and clear',
        ScenarioType.hospital: 'A clean hospital reception area with staff and visitors, professional setting',
        ScenarioType.beach: 'A sunny beach with families playing, clear blue sky, simple beach activities',
      },
      DifficultyLevel.intermediate: {
        ScenarioType.street: 'A realistic urban street with 4-5 pedestrians, shops, moderate traffic, natural lighting, photographic style',
        ScenarioType.restaurant: 'A restaurant scene with diners and waiter, atmospheric lighting, semi-realistic style, clear details',
        ScenarioType.park: 'An active park with people jogging and relaxing, natural scenery, golden hour light, photographic style',
        ScenarioType.office: 'A professional office with team meeting, modern furniture, natural light, business setting',
        ScenarioType.home: 'A modern home with family activities, open plan living, natural lighting, lifestyle photography',
        ScenarioType.airport: 'A busy airport with travelers, departure boards, realistic atmosphere',
        ScenarioType.shopping: 'A vibrant shopping center with various stores and crowds, realistic style',
        ScenarioType.school: 'A school corridor with students between classes, natural interactions',
        ScenarioType.hospital: 'A hospital ward with medical staff and patients, professional environment',
        ScenarioType.beach: 'A beach scene with various activities, sunset lighting, realistic style',
      },
      DifficultyLevel.advanced: {
        ScenarioType.street: 'A detailed city street corner with diverse people, architectural details, dynamic urban life, photorealistic style',
        ScenarioType.restaurant: 'An upscale restaurant with multiple diners, elegant decor, sophisticated atmosphere, photorealistic',
        ScenarioType.park: 'A vibrant public park with various activities, landscape details, environmental portrait style',
        ScenarioType.office: 'A corporate office environment, glass walls, multiple professionals, high-end design, photorealistic',
        ScenarioType.home: 'A luxury home interior with family gathering, designer furniture, lifestyle photography style',
        ScenarioType.airport: 'An international airport hub with diverse travelers, complex scene, photorealistic',
        ScenarioType.shopping: 'A luxury shopping district with high-end stores and shoppers, detailed architecture',
        ScenarioType.school: 'A university campus with students in various activities, architectural details',
        ScenarioType.hospital: 'A modern hospital complex with various departments, professional atmosphere',
        ScenarioType.beach: 'A scenic coastline with multiple activities, dramatic lighting, photorealistic',
      },
    };
  }

  // Build system prompts
  String _buildLearningSystemPrompt(DifficultyLevel level) {
    return '''You are an English teaching assistant. Generate learning content based on the scene.

Requirements:
- Create one English sentence describing the scene
- Difficulty: ${level.description}
- Extract 3-4 key vocabulary words from the sentence
- Return valid JSON format

Response format:
{
  "sentence": "The complete sentence",
  "keywords": ["word1", "word2", "word3"],
  "difficulty": 1-5 (numeric),
  "grammarPoint": "Brief grammar explanation",
  "pronunciationTips": ["tip1", "tip2"]
}''';
  }

  String _buildEvaluationSystemPrompt() {
    return '''You are an expert English pronunciation coach. Evaluate the user's speech.

Evaluation criteria:
1. Pronunciation accuracy (0-100)
2. Fluency and rhythm (0-100)
3. Grammar correctness
4. Keyword detection

Return JSON format:
{
  "overallScore": 0-100,
  "pronunciationScore": 0-100,
  "fluencyScore": 0-100,
  "grammarScore": 0-100,
  "matchedKeywords": ["words correctly pronounced"],
  "missedKeywords": ["words missed or mispronounced"],
  "errors": [{"type": "pronunciation/grammar", "word": "word", "suggestion": "tip"}],
  "feedback": "Encouraging personalized feedback",
  "improvementTips": ["specific tip 1", "specific tip 2"]
}''';
  }

  String _buildTutorSystemPrompt() {
    return '''You are a friendly English tutor. Help users improve their English speaking skills.
- Be encouraging and patient
- Provide simple, clear explanations
- Suggest practice exercises
- Keep responses concise (2-3 sentences)
- Focus on practical usage and common mistakes''';
  }

  // Get service statistics
  Map<String, dynamic> getStats() {
    return {
      'apiKey': _config.apiKey.isNotEmpty ? 'Configured' : 'Not configured',
      'baseUrl': _config.baseUrl,
      'cacheEnabled': _config.useCache,
      'maxRetries': _config.maxRetries,
    };
  }
}

// Dio Interceptors
class _AuthInterceptor extends Interceptor {
  final String apiKey;

  _AuthInterceptor(this.apiKey);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['Authorization'] = 'Bearer $apiKey';
    options.headers['Content-Type'] = 'application/json';
    handler.next(options);
  }
}

class _LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    Logger.apiRequest(options.path, params: options.data);
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    Logger.apiResponse(response.requestOptions.path, statusCode: response.statusCode);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    Logger.apiError(err.requestOptions.path, error: err);
    handler.next(err);
  }
}

class _ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // Handle specific OpenAI errors
    if (err.response?.data != null) {
      final data = err.response!.data;
      if (data is Map && data['error'] != null) {
        final errorMessage = data['error']['message'] ?? 'Unknown error';
        final errorType = data['error']['type'];
        
        // Check for content policy violation
        if (errorType == 'invalid_request_error' && errorMessage.contains('content policy')) {
          handler.reject(ContentModerationException(
            message: 'Content violates OpenAI usage policies',
            statusCode: err.response?.statusCode,
            errorType: errorType,
            details: errorMessage,
          ));
          return;
        }
      }
    }
    handler.next(err);
  }
}