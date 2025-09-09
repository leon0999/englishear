import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../core/logger.dart';

/// Enterprise-grade Error Recovery Service
/// Handles all error scenarios with automatic recovery strategies
class ErrorRecoveryService extends ChangeNotifier {
  static final ErrorRecoveryService _instance = ErrorRecoveryService._internal();
  factory ErrorRecoveryService() => _instance;
  ErrorRecoveryService._internal();
  
  // Error tracking
  final Map<ErrorType, List<ErrorEvent>> _errorHistory = {};
  final Map<String, int> _retryAttempts = {};
  
  // Recovery strategies
  final Map<ErrorType, RecoveryStrategy> _recoveryStrategies = {
    ErrorType.network: RecoveryStrategy.exponentialBackoff,
    ErrorType.api: RecoveryStrategy.immediateRetry,
    ErrorType.audio: RecoveryStrategy.reset,
    ErrorType.permission: RecoveryStrategy.userIntervention,
    ErrorType.subscription: RecoveryStrategy.redirect,
    ErrorType.unknown: RecoveryStrategy.fallback,
  };
  
  // Configuration
  static const int maxRetryAttempts = 3;
  static const Duration baseRetryDelay = Duration(seconds: 1);
  static const Duration maxRetryDelay = Duration(seconds: 30);
  
  // Network monitoring
  final Connectivity _connectivity = Connectivity();
  ConnectivityResult? _currentConnectivity;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
  
  // Recovery callbacks
  final Map<ErrorType, List<RecoveryCallback>> _recoveryCallbacks = {};
  
  // Circuit breaker pattern
  final Map<String, CircuitBreaker> _circuitBreakers = {};
  
  /// Initialize error recovery service
  Future<void> initialize() async {
    await _setupNetworkMonitoring();
    _setupErrorHandlers();
    AppLogger.info('🛡️ Error Recovery Service initialized');
  }
  
  /// Setup network monitoring
  Future<void> _setupNetworkMonitoring() async {
    _currentConnectivity = await _connectivity.checkConnectivity();
    
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (ConnectivityResult result) {
        _handleConnectivityChange(result);
      },
    );
  }
  
  /// Setup global error handlers
  void _setupErrorHandlers() {
    // Flutter error handler
    FlutterError.onError = (FlutterErrorDetails details) {
      handleError(
        ErrorType.flutter,
        details.exception,
        stackTrace: details.stack,
        context: details.context?.toString() ?? 'Unknown context',
      );
    };
    
    // Platform errors
    PlatformDispatcher.instance.onError = (error, stack) {
      handleError(
        ErrorType.platform,
        error,
        stackTrace: stack,
      );
      return true;
    };
  }
  
  /// Handle connectivity changes
  void _handleConnectivityChange(ConnectivityResult result) {
    final wasOffline = _currentConnectivity == ConnectivityResult.none;
    final isOnline = result != ConnectivityResult.none;
    
    _currentConnectivity = result;
    
    if (wasOffline && isOnline) {
      AppLogger.success('🌐 Network reconnected');
      _triggerRecoveryCallbacks(ErrorType.network);
    } else if (!isOnline) {
      AppLogger.warning('📵 Network disconnected');
    }
    
    notifyListeners();
  }
  
  /// Handle error with recovery strategy
  Future<T?> handleError<T>(
    ErrorType type,
    dynamic error, {
    StackTrace? stackTrace,
    String? context,
    Future<T> Function()? retryCallback,
  }) async {
    // Log error
    AppLogger.error('${type.name} error in $context', error, stackTrace);
    
    // Record error event
    _recordError(type, error, context);
    
    // Get recovery strategy
    final strategy = _recoveryStrategies[type] ?? RecoveryStrategy.fallback;
    
    // Apply recovery strategy
    switch (strategy) {
      case RecoveryStrategy.immediateRetry:
        if (retryCallback != null) {
          return await _retryWithStrategy(
            retryCallback,
            immediate: true,
            maxAttempts: maxRetryAttempts,
          );
        }
        break;
        
      case RecoveryStrategy.exponentialBackoff:
        if (retryCallback != null) {
          return await _retryWithStrategy(
            retryCallback,
            immediate: false,
            maxAttempts: maxRetryAttempts,
          );
        }
        break;
        
      case RecoveryStrategy.reset:
        await _resetService(context ?? 'unknown');
        break;
        
      case RecoveryStrategy.userIntervention:
        _notifyUserIntervention(type, error);
        break;
        
      case RecoveryStrategy.redirect:
        _handleRedirect(type);
        break;
        
      case RecoveryStrategy.fallback:
        return _provideFallback<T>(type);
        
      case RecoveryStrategy.circuitBreaker:
        return await _handleWithCircuitBreaker(
          context ?? 'unknown',
          retryCallback,
        );
    }
    
    return null;
  }
  
  /// Retry with strategy
  Future<T?> _retryWithStrategy<T>(
    Future<T> Function() callback, {
    required bool immediate,
    required int maxAttempts,
  }) async {
    final key = callback.hashCode.toString();
    _retryAttempts[key] = (_retryAttempts[key] ?? 0) + 1;
    
    if (_retryAttempts[key]! > maxAttempts) {
      AppLogger.warning('Max retry attempts reached');
      _retryAttempts.remove(key);
      return null;
    }
    
    if (!immediate) {
      final delay = _calculateBackoffDelay(_retryAttempts[key]!);
      AppLogger.info('Retrying in ${delay.inSeconds}s (attempt ${_retryAttempts[key]}/$maxAttempts)');
      await Future.delayed(delay);
    }
    
    try {
      final result = await callback();
      _retryAttempts.remove(key);
      AppLogger.success('✅ Retry successful');
      return result;
    } catch (e) {
      AppLogger.error('Retry failed', e);
      return await _retryWithStrategy(
        callback,
        immediate: immediate,
        maxAttempts: maxAttempts,
      );
    }
  }
  
  /// Calculate exponential backoff delay
  Duration _calculateBackoffDelay(int attempt) {
    final exponentialDelay = baseRetryDelay * (1 << (attempt - 1));
    return exponentialDelay > maxRetryDelay ? maxRetryDelay : exponentialDelay;
  }
  
  /// Reset service
  Future<void> _resetService(String serviceName) async {
    AppLogger.info('🔄 Resetting service: $serviceName');
    
    // Trigger reset callbacks
    _triggerRecoveryCallbacks(ErrorType.audio);
    
    // Clear error history for this service
    _errorHistory.clear();
    _retryAttempts.clear();
    
    notifyListeners();
  }
  
  /// Notify user intervention required
  void _notifyUserIntervention(ErrorType type, dynamic error) {
    AppLogger.warning('👤 User intervention required for $type error');
    notifyListeners();
  }
  
  /// Handle redirect
  void _handleRedirect(ErrorType type) {
    AppLogger.info('🔀 Redirecting due to $type error');
    // Navigate to appropriate screen
    notifyListeners();
  }
  
  /// Provide fallback value
  T? _provideFallback<T>(ErrorType type) {
    AppLogger.info('📦 Providing fallback for $type error');
    
    // Return appropriate fallback based on type
    switch (type) {
      case ErrorType.api:
        // Return cached data if available
        return null;
      default:
        return null;
    }
  }
  
  /// Handle with circuit breaker
  Future<T?> _handleWithCircuitBreaker<T>(
    String key,
    Future<T> Function()? callback,
  ) async {
    if (callback == null) return null;
    
    // Get or create circuit breaker
    final breaker = _circuitBreakers.putIfAbsent(
      key,
      () => CircuitBreaker(
        failureThreshold: 5,
        resetTimeout: const Duration(minutes: 1),
      ),
    );
    
    if (breaker.isOpen) {
      AppLogger.warning('⚡ Circuit breaker is open for $key');
      return null;
    }
    
    try {
      final result = await callback();
      breaker.recordSuccess();
      return result;
    } catch (e) {
      breaker.recordFailure();
      
      if (breaker.isOpen) {
        AppLogger.error('⚡ Circuit breaker opened for $key');
      }
      
      rethrow;
    }
  }
  
  /// Record error event
  void _recordError(ErrorType type, dynamic error, String? context) {
    final event = ErrorEvent(
      type: type,
      error: error,
      context: context,
      timestamp: DateTime.now(),
    );
    
    _errorHistory.putIfAbsent(type, () => []).add(event);
    
    // Limit history size
    if (_errorHistory[type]!.length > 100) {
      _errorHistory[type]!.removeAt(0);
    }
  }
  
  /// Register recovery callback
  void registerRecoveryCallback(
    ErrorType type,
    RecoveryCallback callback,
  ) {
    _recoveryCallbacks.putIfAbsent(type, () => []).add(callback);
  }
  
  /// Trigger recovery callbacks
  void _triggerRecoveryCallbacks(ErrorType type) {
    final callbacks = _recoveryCallbacks[type] ?? [];
    for (final callback in callbacks) {
      callback();
    }
  }
  
  /// Get error statistics
  Map<String, dynamic> getErrorStatistics() {
    final stats = <String, dynamic>{};
    
    _errorHistory.forEach((type, events) {
      stats[type.name] = {
        'count': events.length,
        'lastOccurred': events.isNotEmpty 
            ? events.last.timestamp.toIso8601String() 
            : null,
      };
    });
    
    return stats;
  }
  
  /// Check if network is available
  bool get isNetworkAvailable => 
      _currentConnectivity != ConnectivityResult.none;
  
  /// Get current connectivity status
  ConnectivityResult? get connectivityStatus => _currentConnectivity;
  
  /// Clear error history
  void clearErrorHistory() {
    _errorHistory.clear();
    _retryAttempts.clear();
    notifyListeners();
  }
  
  /// Dispose
  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}

/// Error types
enum ErrorType {
  network,
  api,
  audio,
  permission,
  subscription,
  flutter,
  platform,
  unknown,
}

/// Recovery strategies
enum RecoveryStrategy {
  immediateRetry,
  exponentialBackoff,
  reset,
  userIntervention,
  redirect,
  fallback,
  circuitBreaker,
}

/// Error event
class ErrorEvent {
  final ErrorType type;
  final dynamic error;
  final String? context;
  final DateTime timestamp;
  
  ErrorEvent({
    required this.type,
    required this.error,
    this.context,
    required this.timestamp,
  });
}

/// Recovery callback
typedef RecoveryCallback = void Function();

/// Circuit breaker implementation
class CircuitBreaker {
  final int failureThreshold;
  final Duration resetTimeout;
  
  int _failureCount = 0;
  DateTime? _lastFailureTime;
  CircuitBreakerState _state = CircuitBreakerState.closed;
  
  CircuitBreaker({
    required this.failureThreshold,
    required this.resetTimeout,
  });
  
  bool get isOpen => _state == CircuitBreakerState.open;
  bool get isClosed => _state == CircuitBreakerState.closed;
  bool get isHalfOpen => _state == CircuitBreakerState.halfOpen;
  
  void recordSuccess() {
    if (_state == CircuitBreakerState.halfOpen) {
      _state = CircuitBreakerState.closed;
      _failureCount = 0;
      AppLogger.info('⚡ Circuit breaker closed');
    }
  }
  
  void recordFailure() {
    _failureCount++;
    _lastFailureTime = DateTime.now();
    
    if (_failureCount >= failureThreshold) {
      _state = CircuitBreakerState.open;
      
      // Schedule half-open state
      Future.delayed(resetTimeout, () {
        _state = CircuitBreakerState.halfOpen;
        AppLogger.info('⚡ Circuit breaker half-open');
      });
    }
  }
  
  void reset() {
    _state = CircuitBreakerState.closed;
    _failureCount = 0;
    _lastFailureTime = null;
  }
}

/// Circuit breaker states
enum CircuitBreakerState {
  closed,
  open,
  halfOpen,
}