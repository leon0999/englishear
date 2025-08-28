import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/logger.dart';
import '../core/exceptions.dart';

class CacheService {
  static const String _cachePrefix = 'openai_cache_';
  static const String _timestampSuffix = '_timestamp';
  
  final SharedPreferences _prefs;
  final int cacheExpiryHours;

  CacheService({
    required SharedPreferences prefs,
    this.cacheExpiryHours = 24,
  }) : _prefs = prefs;

  static Future<CacheService> create({int cacheExpiryHours = 24}) async {
    final prefs = await SharedPreferences.getInstance();
    return CacheService(prefs: prefs, cacheExpiryHours: cacheExpiryHours);
  }

  // Generate cache key from request parameters
  String generateKey(String type, Map<String, dynamic> params) {
    final sortedParams = Map.fromEntries(
      params.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    final paramString = json.encode(sortedParams);
    final hash = paramString.hashCode.toString();
    return '$_cachePrefix${type}_$hash';
  }

  // Store data in cache
  Future<void> set(String key, dynamic data, {Duration? customExpiry}) async {
    try {
      final jsonData = json.encode(data);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      await _prefs.setString(key, jsonData);
      await _prefs.setInt('$key$_timestampSuffix', timestamp);
      
      Logger.debug('Cache set: $key');
    } catch (e) {
      Logger.warning('Failed to cache data', data: e);
      throw CacheException(message: 'Failed to cache data: $e');
    }
  }

  // Retrieve data from cache
  Future<T?> get<T>(String key) async {
    try {
      final jsonData = _prefs.getString(key);
      if (jsonData == null) {
        Logger.debug('Cache miss: $key');
        return null;
      }

      final timestamp = _prefs.getInt('$key$_timestampSuffix') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      final expiryMs = cacheExpiryHours * 60 * 60 * 1000;

      if (now - timestamp > expiryMs) {
        Logger.debug('Cache expired: $key');
        await remove(key);
        return null;
      }

      Logger.debug('Cache hit: $key');
      return json.decode(jsonData) as T;
    } catch (e) {
      Logger.warning('Failed to retrieve cached data', data: e);
      return null;
    }
  }

  // Remove specific cache entry
  Future<void> remove(String key) async {
    await _prefs.remove(key);
    await _prefs.remove('$key$_timestampSuffix');
    Logger.debug('Cache removed: $key');
  }

  // Clear all cache
  Future<void> clearAll() async {
    final keys = _prefs.getKeys().where((key) => key.startsWith(_cachePrefix));
    for (final key in keys) {
      await _prefs.remove(key);
    }
    Logger.info('All cache cleared');
  }

  // Get cache size
  int getCacheSize() {
    final keys = _prefs.getKeys().where((key) => key.startsWith(_cachePrefix));
    int totalSize = 0;
    
    for (final key in keys) {
      final value = _prefs.getString(key);
      if (value != null) {
        totalSize += value.length;
      }
    }
    
    return totalSize;
  }

  // Clean expired cache entries
  Future<void> cleanExpired() async {
    final keys = _prefs.getKeys().where((key) => key.startsWith(_cachePrefix) && !key.contains(_timestampSuffix));
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiryMs = cacheExpiryHours * 60 * 60 * 1000;
    int cleanedCount = 0;

    for (final key in keys) {
      final timestamp = _prefs.getInt('$key$_timestampSuffix') ?? 0;
      if (now - timestamp > expiryMs) {
        await remove(key);
        cleanedCount++;
      }
    }

    if (cleanedCount > 0) {
      Logger.info('Cleaned $cleanedCount expired cache entries');
    }
  }

  // Check if cache exists and is valid
  Future<bool> hasValid(String key) async {
    final data = await get(key);
    return data != null;
  }

  // Get cache statistics
  Map<String, dynamic> getStats() {
    final keys = _prefs.getKeys().where((key) => key.startsWith(_cachePrefix) && !key.contains(_timestampSuffix));
    final now = DateTime.now().millisecondsSinceEpoch;
    final expiryMs = cacheExpiryHours * 60 * 60 * 1000;
    
    int totalEntries = 0;
    int expiredEntries = 0;
    int totalSize = 0;

    for (final key in keys) {
      totalEntries++;
      final value = _prefs.getString(key);
      if (value != null) {
        totalSize += value.length;
      }
      
      final timestamp = _prefs.getInt('$key$_timestampSuffix') ?? 0;
      if (now - timestamp > expiryMs) {
        expiredEntries++;
      }
    }

    return {
      'totalEntries': totalEntries,
      'expiredEntries': expiredEntries,
      'validEntries': totalEntries - expiredEntries,
      'totalSizeBytes': totalSize,
      'totalSizeKB': (totalSize / 1024).toStringAsFixed(2),
    };
  }
}

// Cache manager for specific OpenAI operations
class OpenAICacheManager {
  final CacheService _cacheService;

  OpenAICacheManager(this._cacheService);

  // Cache image generation results
  Future<String?> getCachedImage(String prompt, String quality, String size) async {
    final key = _cacheService.generateKey('image', {
      'prompt': prompt,
      'quality': quality,
      'size': size,
    });
    
    final cached = await _cacheService.get<Map<String, dynamic>>(key);
    return cached?['imageData'] as String?;
  }

  Future<void> cacheImage(String prompt, String quality, String size, String imageData) async {
    final key = _cacheService.generateKey('image', {
      'prompt': prompt,
      'quality': quality,
      'size': size,
    });
    
    await _cacheService.set(key, {'imageData': imageData});
  }

  // Cache learning content
  Future<Map<String, dynamic>?> getCachedLearningContent(String imageDescription, String level) async {
    final key = _cacheService.generateKey('learning', {
      'description': imageDescription,
      'level': level,
    });
    
    return await _cacheService.get<Map<String, dynamic>>(key);
  }

  Future<void> cacheLearningContent(String imageDescription, String level, Map<String, dynamic> content) async {
    final key = _cacheService.generateKey('learning', {
      'description': imageDescription,
      'level': level,
    });
    
    await _cacheService.set(key, content);
  }

  // Cache pronunciation evaluation
  Future<Map<String, dynamic>?> getCachedEvaluation(String userSpeech, String correctSentence) async {
    final key = _cacheService.generateKey('evaluation', {
      'user': userSpeech,
      'correct': correctSentence,
    });
    
    return await _cacheService.get<Map<String, dynamic>>(key);
  }

  Future<void> cacheEvaluation(String userSpeech, String correctSentence, Map<String, dynamic> evaluation) async {
    final key = _cacheService.generateKey('evaluation', {
      'user': userSpeech,
      'correct': correctSentence,
    });
    
    await _cacheService.set(key, evaluation, customExpiry: const Duration(hours: 1)); // Shorter expiry for evaluations
  }
}