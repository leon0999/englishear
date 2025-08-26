import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiCostOptimizer {
  static final ApiCostOptimizer _instance = ApiCostOptimizer._internal();
  factory ApiCostOptimizer() => _instance;
  ApiCostOptimizer._internal();

  // 캐시 저장소
  final Map<String, CachedImage> _imageCache = {};
  final Map<String, CachedSentence> _sentenceCache = {};
  
  // 사용량 추적
  final Map<String, DailyUsage> _dailyUsage = {};
  
  // 설정
  late final bool _useCacheEnabled;
  late final int _cacheExpiryHours;
  late final int _freeDailyLimit;
  late final int _premiumDailyLimit;

  Future<void> initialize() async {
    _useCacheEnabled = dotenv.env['USE_CACHE'] == 'true';
    _cacheExpiryHours = int.parse(dotenv.env['CACHE_EXPIRY_HOURS'] ?? '24');
    _freeDailyLimit = int.parse(dotenv.env['FREE_DAILY_LIMIT'] ?? '3');
    _premiumDailyLimit = int.parse(dotenv.env['PREMIUM_DAILY_LIMIT'] ?? '100');
    
    await _loadCacheFromStorage();
    await _loadUsageFromStorage();
  }

  // 이미지 캐시 확인
  String? getCachedImage(String prompt, String level) {
    final key = _generateCacheKey(prompt, level);
    final cached = _imageCache[key];
    
    if (cached != null && !_isExpired(cached.timestamp)) {
      print('Using cached image for: $key');
      return cached.imageUrl;
    }
    
    return null;
  }

  // 이미지 캐시 저장
  Future<void> cacheImage(String prompt, String level, String imageUrl) async {
    if (!_useCacheEnabled) return;
    
    final key = _generateCacheKey(prompt, level);
    _imageCache[key] = CachedImage(
      imageUrl: imageUrl,
      timestamp: DateTime.now(),
    );
    
    await _saveCacheToStorage();
  }

  // 문장 캐시 확인
  Map<String, dynamic>? getCachedSentence(String imageDescription, String level) {
    final key = _generateCacheKey(imageDescription, level);
    final cached = _sentenceCache[key];
    
    if (cached != null && !_isExpired(cached.timestamp)) {
      print('Using cached sentence for: $key');
      return cached.data;
    }
    
    return null;
  }

  // 문장 캐시 저장
  Future<void> cacheSentence(
    String imageDescription,
    String level,
    Map<String, dynamic> sentenceData,
  ) async {
    if (!_useCacheEnabled) return;
    
    final key = _generateCacheKey(imageDescription, level);
    _sentenceCache[key] = CachedSentence(
      data: sentenceData,
      timestamp: DateTime.now(),
    );
    
    await _saveCacheToStorage();
  }

  // 일일 사용량 확인
  Future<bool> canUseApi(String userId, bool isPremium) async {
    final today = _getTodayKey();
    final usage = _dailyUsage[userId] ?? DailyUsage(date: today, count: 0);
    
    // 날짜가 바뀌면 리셋
    if (usage.date != today) {
      usage.date = today;
      usage.count = 0;
    }
    
    final limit = isPremium ? _premiumDailyLimit : _freeDailyLimit;
    return usage.count < limit;
  }

  // API 사용 기록
  Future<void> recordApiUsage(String userId) async {
    final today = _getTodayKey();
    final usage = _dailyUsage[userId] ?? DailyUsage(date: today, count: 0);
    
    if (usage.date != today) {
      usage.date = today;
      usage.count = 0;
    }
    
    usage.count++;
    _dailyUsage[userId] = usage;
    
    await _saveUsageToStorage();
  }

  // 남은 사용 횟수 조회
  int getRemainingUsage(String userId, bool isPremium) {
    final today = _getTodayKey();
    final usage = _dailyUsage[userId] ?? DailyUsage(date: today, count: 0);
    
    if (usage.date != today) {
      return isPremium ? _premiumDailyLimit : _freeDailyLimit;
    }
    
    final limit = isPremium ? _premiumDailyLimit : _freeDailyLimit;
    return (limit - usage.count).clamp(0, limit);
  }

  // 비용 계산 (월별)
  Map<String, double> calculateMonthlyCosts(int activeUsers, double premiumRate) {
    final premiumUsers = (activeUsers * premiumRate).round();
    final freeUsers = activeUsers - premiumUsers;
    
    // 일일 API 호출 예상
    final dailyApiCalls = 
        (freeUsers * _freeDailyLimit * 0.5) + // 무료 사용자는 50% 활성도
        (premiumUsers * _premiumDailyLimit * 0.3); // 프리미엄도 30% 활성도
    
    final monthlyApiCalls = dailyApiCalls * 30;
    
    // API 비용 (Stable Diffusion이 DALL-E보다 95% 저렴)
    final imageGenCost = monthlyApiCalls * 0.002; // Stable Diffusion
    final textGenCost = monthlyApiCalls * 0.01; // GPT-4 Turbo
    
    return {
      'total_monthly_cost': imageGenCost + textGenCost,
      'image_generation': imageGenCost,
      'text_generation': textGenCost,
      'cost_per_user': (imageGenCost + textGenCost) / activeUsers,
      'monthly_api_calls': monthlyApiCalls,
    };
  }

  // 캐시 키 생성
  String _generateCacheKey(String input1, String input2) {
    final combined = '$input1:$input2';
    final bytes = utf8.encode(combined);
    final digest = base64.encode(bytes);
    return digest.substring(0, 20); // 짧게 자르기
  }

  // 만료 확인
  bool _isExpired(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    return difference.inHours >= _cacheExpiryHours;
  }

  // 오늘 날짜 키
  String _getTodayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  // 캐시 저장소에서 로드
  Future<void> _loadCacheFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final imageCacheJson = prefs.getString('image_cache');
      final sentenceCacheJson = prefs.getString('sentence_cache');
      
      if (imageCacheJson != null) {
        final Map<String, dynamic> decoded = json.decode(imageCacheJson);
        decoded.forEach((key, value) {
          _imageCache[key] = CachedImage.fromJson(value);
        });
      }
      
      if (sentenceCacheJson != null) {
        final Map<String, dynamic> decoded = json.decode(sentenceCacheJson);
        decoded.forEach((key, value) {
          _sentenceCache[key] = CachedSentence.fromJson(value);
        });
      }
    } catch (e) {
      print('Error loading cache: $e');
    }
  }

  // 캐시 저장소에 저장
  Future<void> _saveCacheToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final imageMap = <String, dynamic>{};
      _imageCache.forEach((key, value) {
        imageMap[key] = value.toJson();
      });
      
      final sentenceMap = <String, dynamic>{};
      _sentenceCache.forEach((key, value) {
        sentenceMap[key] = value.toJson();
      });
      
      await prefs.setString('image_cache', json.encode(imageMap));
      await prefs.setString('sentence_cache', json.encode(sentenceMap));
    } catch (e) {
      print('Error saving cache: $e');
    }
  }

  // 사용량 저장소에서 로드
  Future<void> _loadUsageFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final usageJson = prefs.getString('daily_usage');
      
      if (usageJson != null) {
        final Map<String, dynamic> decoded = json.decode(usageJson);
        decoded.forEach((key, value) {
          _dailyUsage[key] = DailyUsage.fromJson(value);
        });
      }
    } catch (e) {
      print('Error loading usage: $e');
    }
  }

  // 사용량 저장소에 저장
  Future<void> _saveUsageToStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      final usageMap = <String, dynamic>{};
      _dailyUsage.forEach((key, value) {
        usageMap[key] = value.toJson();
      });
      
      await prefs.setString('daily_usage', json.encode(usageMap));
    } catch (e) {
      print('Error saving usage: $e');
    }
  }

  // 캐시 정리 (오래된 항목 제거)
  Future<void> cleanupCache() async {
    final now = DateTime.now();
    
    // 만료된 이미지 캐시 제거
    _imageCache.removeWhere((key, value) => _isExpired(value.timestamp));
    
    // 만료된 문장 캐시 제거
    _sentenceCache.removeWhere((key, value) => _isExpired(value.timestamp));
    
    // 오래된 사용량 데이터 제거 (7일 이상)
    _dailyUsage.removeWhere((key, value) {
      try {
        final date = DateTime.parse(value.date);
        return now.difference(date).inDays > 7;
      } catch (e) {
        return true;
      }
    });
    
    await _saveCacheToStorage();
    await _saveUsageToStorage();
  }
}

// 캐시된 이미지 모델
class CachedImage {
  final String imageUrl;
  final DateTime timestamp;
  
  CachedImage({
    required this.imageUrl,
    required this.timestamp,
  });
  
  factory CachedImage.fromJson(Map<String, dynamic> json) {
    return CachedImage(
      imageUrl: json['imageUrl'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'imageUrl': imageUrl,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

// 캐시된 문장 모델
class CachedSentence {
  final Map<String, dynamic> data;
  final DateTime timestamp;
  
  CachedSentence({
    required this.data,
    required this.timestamp,
  });
  
  factory CachedSentence.fromJson(Map<String, dynamic> json) {
    return CachedSentence(
      data: json['data'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'data': data,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

// 일일 사용량 모델
class DailyUsage {
  String date;
  int count;
  
  DailyUsage({
    required this.date,
    required this.count,
  });
  
  factory DailyUsage.fromJson(Map<String, dynamic> json) {
    return DailyUsage(
      date: json['date'],
      count: json['count'],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'date': date,
      'count': count,
    };
  }
}