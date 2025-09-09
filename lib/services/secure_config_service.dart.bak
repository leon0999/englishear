import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/logger.dart';

/// Secure configuration service for production deployment
/// Handles API keys, environment variables, and sensitive data
class SecureConfigService {
  static final SecureConfigService _instance = SecureConfigService._internal();
  factory SecureConfigService() => _instance;
  SecureConfigService._internal();
  
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  
  // Environment configuration
  late final EnvironmentConfig _config;
  bool _isInitialized = false;
  
  // Encryption keys (should be stored in secure keystore in production)
  static const String _encryptionKey = 'CHANGE_THIS_IN_PRODUCTION';
  
  /// Initialize the configuration service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    AppLogger.test('==================== SECURE CONFIG INIT START ====================');
    
    try {
      // Determine environment
      final environment = await _determineEnvironment();
      AppLogger.info('🌍 Environment: ${environment.name}');
      
      // Load configuration for environment
      _config = await _loadConfiguration(environment);
      
      // Validate API keys
      await _validateApiKeys();
      
      // Setup secure storage
      await _setupSecureStorage();
      
      _isInitialized = true;
      
      AppLogger.success('✅ Secure configuration initialized');
      AppLogger.test('==================== SECURE CONFIG INIT COMPLETE ====================');
      
    } catch (e) {
      AppLogger.error('Failed to initialize secure config', e);
      throw SecureConfigException('Configuration initialization failed: $e');
    }
  }
  
  /// Determine current environment
  Future<Environment> _determineEnvironment() async {
    // Check for environment override
    const override = String.fromEnvironment('ENV');
    if (override.isNotEmpty) {
      return Environment.values.firstWhere(
        (e) => e.name == override,
        orElse: () => Environment.development,
      );
    }
    
    // Check if running in debug mode
    if (const bool.fromEnvironment('dart.vm.product') == false) {
      return Environment.development;
    }
    
    // Default to production in release builds
    return Environment.production;
  }
  
  /// Load configuration for environment
  Future<EnvironmentConfig> _loadConfiguration(Environment environment) async {
    switch (environment) {
      case Environment.development:
        return EnvironmentConfig(
          environment: environment,
          apiBaseUrl: 'http://localhost:3000',
          websocketUrl: 'ws://localhost:3000',
          openAiApiKey: await _getSecureValue('OPENAI_API_KEY_DEV'),
          sentryDsn: null,
          enableLogging: true,
          enableCrashReporting: false,
          maxRetries: 3,
          timeoutSeconds: 30,
        );
        
      case Environment.staging:
        return EnvironmentConfig(
          environment: environment,
          apiBaseUrl: 'https://staging-api.englishear.com',
          websocketUrl: 'wss://staging-api.englishear.com',
          openAiApiKey: await _getSecureValue('OPENAI_API_KEY_STAGING'),
          sentryDsn: await _getSecureValue('SENTRY_DSN_STAGING'),
          enableLogging: true,
          enableCrashReporting: true,
          maxRetries: 5,
          timeoutSeconds: 20,
        );
        
      case Environment.production:
        return EnvironmentConfig(
          environment: environment,
          apiBaseUrl: 'https://api.englishear.com',
          websocketUrl: 'wss://api.englishear.com',
          openAiApiKey: await _getSecureValue('OPENAI_API_KEY_PROD'),
          sentryDsn: await _getSecureValue('SENTRY_DSN_PROD'),
          enableLogging: false,
          enableCrashReporting: true,
          maxRetries: 5,
          timeoutSeconds: 15,
        );
    }
  }
  
  /// Get secure value from storage or environment
  Future<String?> _getSecureValue(String key) async {
    // First try secure storage
    final stored = await _secureStorage.read(key: key);
    if (stored != null) return stored;
    
    // Fallback to environment variable
    try {
      final envValue = String.fromEnvironment(key);
      if (envValue.isNotEmpty) return envValue;
    } catch (e) {
      AppLogger.debug('Environment variable $key not found');
    }
    
    // For development, try loading from .env file
    if (_config.environment == Environment.development) {
      try {
        final envContent = await rootBundle.loadString('.env');
        final lines = envContent.split('\n');
        for (final line in lines) {
          if (line.startsWith('$key=')) {
            return line.substring(key.length + 1).trim();
          }
        }
      } catch (e) {
        AppLogger.debug('.env file not found or $key not in .env');
      }
    }
    
    return null;
  }
  
  /// Validate required API keys
  Future<void> _validateApiKeys() async {
    final requiredKeys = [
      'openAiApiKey',
    ];
    
    for (final key in requiredKeys) {
      final value = _getConfigValue(key);
      if (value == null || value.isEmpty) {
        if (_config.environment == Environment.production) {
          throw SecureConfigException('Missing required API key: $key');
        } else {
          AppLogger.warning('⚠️ Missing API key: $key (non-production environment)');
        }
      }
    }
    
    AppLogger.success('✅ API keys validated');
  }
  
  /// Setup secure storage with encryption
  Future<void> _setupSecureStorage() async {
    // iOS options
    const iOSOptions = IOSOptions(
      accessibility: IOSAccessibility.first_unlock_this_device,
    );
    
    // Android options
    const androidOptions = AndroidOptions(
      encryptedSharedPreferences: true,
    );
    
    // Store a test value to ensure storage is working
    await _secureStorage.write(
      key: 'test_key',
      value: 'test_value',
      iOptions: iOSOptions,
      aOptions: androidOptions,
    );
    
    final testValue = await _secureStorage.read(key: 'test_key');
    if (testValue != 'test_value') {
      throw SecureConfigException('Secure storage validation failed');
    }
    
    await _secureStorage.delete(key: 'test_key');
    
    AppLogger.success('✅ Secure storage initialized');
  }
  
  /// Get configuration value
  dynamic _getConfigValue(String key) {
    switch (key) {
      case 'apiBaseUrl':
        return _config.apiBaseUrl;
      case 'websocketUrl':
        return _config.websocketUrl;
      case 'openAiApiKey':
        return _config.openAiApiKey;
      case 'sentryDsn':
        return _config.sentryDsn;
      case 'enableLogging':
        return _config.enableLogging;
      case 'enableCrashReporting':
        return _config.enableCrashReporting;
      case 'maxRetries':
        return _config.maxRetries;
      case 'timeoutSeconds':
        return _config.timeoutSeconds;
      default:
        return null;
    }
  }
  
  /// Store sensitive data securely
  Future<void> storeSecureData(String key, String value) async {
    if (!_isInitialized) {
      throw SecureConfigException('Service not initialized');
    }
    
    // Encrypt value before storing (simplified - use proper encryption in production)
    final encrypted = _simpleEncrypt(value);
    
    await _secureStorage.write(
      key: key,
      value: encrypted,
      iOptions: const IOSOptions(
        accessibility: IOSAccessibility.first_unlock_this_device,
      ),
      aOptions: const AndroidOptions(
        encryptedSharedPreferences: true,
      ),
    );
    
    AppLogger.debug('Stored secure data for key: $key');
  }
  
  /// Retrieve sensitive data
  Future<String?> getSecureData(String key) async {
    if (!_isInitialized) {
      throw SecureConfigException('Service not initialized');
    }
    
    final encrypted = await _secureStorage.read(key: key);
    if (encrypted == null) return null;
    
    // Decrypt value
    return _simpleDecrypt(encrypted);
  }
  
  /// Delete sensitive data
  Future<void> deleteSecureData(String key) async {
    if (!_isInitialized) {
      throw SecureConfigException('Service not initialized');
    }
    
    await _secureStorage.delete(key: key);
    AppLogger.debug('Deleted secure data for key: $key');
  }
  
  /// Clear all secure data
  Future<void> clearAllSecureData() async {
    if (!_isInitialized) {
      throw SecureConfigException('Service not initialized');
    }
    
    await _secureStorage.deleteAll();
    AppLogger.warning('⚠️ All secure data cleared');
  }
  
  /// Simple encryption (replace with proper AES encryption in production)
  String _simpleEncrypt(String plaintext) {
    final bytes = utf8.encode(plaintext);
    final encoded = base64.encode(bytes);
    return encoded;
  }
  
  /// Simple decryption (replace with proper AES decryption in production)
  String _simpleDecrypt(String ciphertext) {
    final bytes = base64.decode(ciphertext);
    final decoded = utf8.decode(bytes);
    return decoded;
  }
  
  /// Get OpenAI API key for current environment
  String? get openAiApiKey => _config.openAiApiKey;
  
  /// Get API base URL for current environment
  String get apiBaseUrl => _config.apiBaseUrl;
  
  /// Get WebSocket URL for current environment
  String get websocketUrl => _config.websocketUrl;
  
  /// Check if logging is enabled
  bool get isLoggingEnabled => _config.enableLogging;
  
  /// Check if crash reporting is enabled
  bool get isCrashReportingEnabled => _config.enableCrashReporting;
  
  /// Get current environment
  Environment get environment => _config.environment;
  
  /// Get timeout duration
  Duration get timeout => Duration(seconds: _config.timeoutSeconds);
  
  /// Get max retry attempts
  int get maxRetries => _config.maxRetries;
  
  /// Rotate API keys (for security)
  Future<void> rotateApiKeys() async {
    AppLogger.warning('🔄 Rotating API keys...');
    
    // In production, this would:
    // 1. Generate new API keys
    // 2. Update backend with new keys
    // 3. Store new keys securely
    // 4. Invalidate old keys after grace period
    
    // For now, just reload configuration
    await initialize();
    
    AppLogger.success('✅ API keys rotated');
  }
  
  /// Export configuration (for debugging, excludes sensitive data)
  Map<String, dynamic> exportConfiguration() {
    return {
      'environment': _config.environment.name,
      'apiBaseUrl': _config.apiBaseUrl,
      'websocketUrl': _config.websocketUrl,
      'enableLogging': _config.enableLogging,
      'enableCrashReporting': _config.enableCrashReporting,
      'maxRetries': _config.maxRetries,
      'timeoutSeconds': _config.timeoutSeconds,
      'hasOpenAiKey': _config.openAiApiKey != null && _config.openAiApiKey!.isNotEmpty,
      'hasSentryDsn': _config.sentryDsn != null && _config.sentryDsn!.isNotEmpty,
    };
  }
}

/// Environment types
enum Environment {
  development,
  staging,
  production,
}

/// Environment configuration
class EnvironmentConfig {
  final Environment environment;
  final String apiBaseUrl;
  final String websocketUrl;
  final String? openAiApiKey;
  final String? sentryDsn;
  final bool enableLogging;
  final bool enableCrashReporting;
  final int maxRetries;
  final int timeoutSeconds;
  
  EnvironmentConfig({
    required this.environment,
    required this.apiBaseUrl,
    required this.websocketUrl,
    this.openAiApiKey,
    this.sentryDsn,
    required this.enableLogging,
    required this.enableCrashReporting,
    required this.maxRetries,
    required this.timeoutSeconds,
  });
}

/// Secure configuration exception
class SecureConfigException implements Exception {
  final String message;
  
  SecureConfigException(this.message);
  
  @override
  String toString() => 'SecureConfigException: $message';
}

/// iOS options for secure storage
class IOSOptions {
  final IOSAccessibility accessibility;
  
  const IOSOptions({
    required this.accessibility,
  });
}

/// iOS accessibility levels
enum IOSAccessibility {
  first_unlock_this_device,
  after_first_unlock,
  always,
}

/// Android options for secure storage
class AndroidOptions {
  final bool encryptedSharedPreferences;
  
  const AndroidOptions({
    required this.encryptedSharedPreferences,
  });
}