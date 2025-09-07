import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

// Simple AppLogger class for straightforward logging
class AppLogger {
  static bool _debugMode = true;
  static bool _verboseMode = true; // Enable verbose logging for testing
  
  static void info(String message) {
    if (_debugMode) {
      final timestamp = DateTime.now().toIso8601String().substring(11, 23);
      print('[$timestamp] ℹ️ [INFO] $message');
    }
  }
  
  static void warning(String message) {
    if (_debugMode) {
      final timestamp = DateTime.now().toIso8601String().substring(11, 23);
      print('[$timestamp] ⚠️ [WARNING] $message');
    }
  }
  
  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    if (_debugMode) {
      final timestamp = DateTime.now().toIso8601String().substring(11, 23);
      print('[$timestamp] ❌ [ERROR] $message');
      if (error != null) {
        print('[$timestamp]    Error details: $error');
        print('[$timestamp]    Error type: ${error.runtimeType}');
      }
      if (stackTrace != null && _verboseMode) {
        print('[$timestamp]    Stack trace:\n$stackTrace');
      }
    }
  }
  
  static void debug(String message) {
    if (_debugMode) {
      final timestamp = DateTime.now().toIso8601String().substring(11, 23);
      print('[$timestamp] 🔍 [DEBUG] $message');
    }
  }
  
  // Test-specific logging methods
  static void test(String message) {
    if (_debugMode) {
      final timestamp = DateTime.now().toIso8601String().substring(11, 23);
      print('[$timestamp] 🧪 [TEST] $message');
    }
  }
  
  static void success(String message) {
    if (_debugMode) {
      final timestamp = DateTime.now().toIso8601String().substring(11, 23);
      print('[$timestamp] ✅ [SUCCESS] $message');
    }
  }
  
  static void network(String message, {Map<String, dynamic>? data}) {
    if (_debugMode && _verboseMode) {
      final timestamp = DateTime.now().toIso8601String().substring(11, 23);
      print('[$timestamp] 🌐 [NETWORK] $message');
      if (data != null) {
        data.forEach((key, value) {
          print('[$timestamp]    $key: $value');
        });
      }
    }
  }
  
  static void audio(String message, {Map<String, dynamic>? data}) {
    if (_debugMode) {
      final timestamp = DateTime.now().toIso8601String().substring(11, 23);
      print('[$timestamp] 🔊 [AUDIO] $message');
      if (data != null && _verboseMode) {
        data.forEach((key, value) {
          print('[$timestamp]    $key: $value');
        });
      }
    }
  }
}

enum LogLevel {
  debug,
  info,
  warning,
  error,
  critical,
}

class Logger {
  static final Logger _instance = Logger._internal();
  factory Logger() => _instance;
  Logger._internal();

  static const String _name = 'EnglishEar';
  static LogLevel _minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;

  static void setMinLevel(LogLevel level) {
    _minLevel = level;
  }

  static void debug(String message, {dynamic data, StackTrace? stackTrace}) {
    _log(LogLevel.debug, message, data: data, stackTrace: stackTrace);
  }

  static void info(String message, {dynamic data}) {
    _log(LogLevel.info, message, data: data);
  }

  static void warning(String message, {dynamic data, StackTrace? stackTrace}) {
    _log(LogLevel.warning, message, data: data, stackTrace: stackTrace);
  }

  static void error(String message, {dynamic error, StackTrace? stackTrace}) {
    _log(LogLevel.error, message, data: error, stackTrace: stackTrace);
  }

  static void critical(String message, {dynamic error, StackTrace? stackTrace}) {
    _log(LogLevel.critical, message, data: error, stackTrace: stackTrace);
  }

  static void _log(
    LogLevel level,
    String message, {
    dynamic data,
    StackTrace? stackTrace,
  }) {
    if (level.index < _minLevel.index) return;

    final emoji = _getEmoji(level);
    final levelName = level.name.toUpperCase();
    final timestamp = DateTime.now().toIso8601String();
    
    final formattedMessage = '$emoji [$levelName] $message';
    
    if (kDebugMode) {
      // In debug mode, use developer.log for better console output
      developer.log(
        formattedMessage,
        time: DateTime.now(),
        name: _name,
        level: _getLogLevel(level),
        error: data,
        stackTrace: stackTrace,
      );
    } else {
      // In production, you might want to send logs to a service
      _sendToLoggingService(
        level: level,
        message: message,
        data: data,
        stackTrace: stackTrace,
        timestamp: timestamp,
      );
    }
  }

  static String _getEmoji(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return '🐛';
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
      case LogLevel.critical:
        return '🔥';
    }
  }

  static int _getLogLevel(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 500;
      case LogLevel.info:
        return 800;
      case LogLevel.warning:
        return 900;
      case LogLevel.error:
        return 1000;
      case LogLevel.critical:
        return 1200;
    }
  }

  static void _sendToLoggingService({
    required LogLevel level,
    required String message,
    dynamic data,
    StackTrace? stackTrace,
    required String timestamp,
  }) {
    // TODO: Implement sending logs to a remote service (e.g., Sentry, Firebase Crashlytics)
    // For now, just print in production
    if (!kDebugMode) {
      print('[$timestamp] ${level.name.toUpperCase()}: $message');
      if (data != null) print('Data: $data');
      if (stackTrace != null && level.index >= LogLevel.error.index) {
        print('Stack trace: $stackTrace');
      }
    }
  }

  // API-specific logging methods
  static void apiRequest(String endpoint, {Map<String, dynamic>? params}) {
    info('API Request: $endpoint', data: params);
  }

  static void apiResponse(String endpoint, {int? statusCode, dynamic data}) {
    info('API Response: $endpoint (${statusCode ?? 'unknown'})', data: data);
  }

  static void apiError(String endpoint, {dynamic error, StackTrace? stackTrace}) {
    error('API Error: $endpoint', error: error, stackTrace: stackTrace);
  }

  // Performance logging
  static void performance(String operation, Duration duration) {
    final ms = duration.inMilliseconds;
    final level = ms > 3000 ? LogLevel.warning : LogLevel.debug;
    _log(level, 'Performance: $operation took ${ms}ms');
  }

  // Usage tracking
  static void usage(String feature, {Map<String, dynamic>? metadata}) {
    info('Usage: $feature', data: metadata);
  }
}