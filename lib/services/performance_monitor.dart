import 'dart:async';
import 'dart:math' as math;
import '../core/logger.dart';

/// Performance monitoring service for measuring real-world latency
/// Tracks all critical metrics for achieving Moshi AI level performance
class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();
  
  // Performance metrics storage
  final Map<String, List<int>> _latencyMeasurements = {};
  final Map<String, DateTime> _operationStartTimes = {};
  final List<NetworkMetric> _networkMetrics = [];
  final List<AudioMetric> _audioMetrics = [];
  
  // Real-time performance stats
  int _currentLatencyMs = 0;
  double _averageLatencyMs = 0;
  double _p95LatencyMs = 0;
  double _p99LatencyMs = 0;
  int _totalRequests = 0;
  int _failedRequests = 0;
  
  // Network conditions simulation
  NetworkCondition _currentCondition = NetworkCondition.wifi5G;
  
  // Stream controllers for real-time monitoring
  final _metricsController = StreamController<PerformanceMetrics>.broadcast();
  final _alertController = StreamController<PerformanceAlert>.broadcast();
  
  Stream<PerformanceMetrics> get metricsStream => _metricsController.stream;
  Stream<PerformanceAlert> get alertStream => _alertController.stream;
  
  // Performance thresholds (Moshi AI targets)
  static const int TARGET_FIRST_BYTE_MS = 160;
  static const int TARGET_E2E_LATENCY_MS = 200;
  static const int ALERT_THRESHOLD_MS = 500;
  
  /// Start tracking an operation
  void startOperation(String operationId) {
    _operationStartTimes[operationId] = DateTime.now();
    AppLogger.debug('⏱️ Started operation: $operationId');
  }
  
  /// End tracking and record latency
  int endOperation(String operationId, {String? category}) {
    final startTime = _operationStartTimes.remove(operationId);
    if (startTime == null) {
      AppLogger.warning('No start time found for operation: $operationId');
      return 0;
    }
    
    final latencyMs = DateTime.now().difference(startTime).inMilliseconds;
    final cat = category ?? 'general';
    
    // Store measurement
    _latencyMeasurements.putIfAbsent(cat, () => []).add(latencyMs);
    _currentLatencyMs = latencyMs;
    _totalRequests++;
    
    // Update statistics
    _updateStatistics(cat);
    
    // Check for performance alerts
    _checkPerformanceAlerts(operationId, latencyMs);
    
    // Log based on performance
    if (latencyMs <= TARGET_FIRST_BYTE_MS) {
      AppLogger.success('🚀 $operationId: ${latencyMs}ms (Moshi AI level!)');
    } else if (latencyMs <= TARGET_E2E_LATENCY_MS) {
      AppLogger.info('✅ $operationId: ${latencyMs}ms (Good)');
    } else if (latencyMs <= ALERT_THRESHOLD_MS) {
      AppLogger.warning('⚠️ $operationId: ${latencyMs}ms (Slow)');
    } else {
      AppLogger.error('🔴 $operationId: ${latencyMs}ms (Critical)');
      _failedRequests++;
    }
    
    // Emit metrics update
    _emitMetrics();
    
    return latencyMs;
  }
  
  /// Record network metric
  void recordNetworkMetric({
    required String endpoint,
    required int requestSizeBytes,
    required int responseSizeBytes,
    required int latencyMs,
    required bool success,
  }) {
    final metric = NetworkMetric(
      timestamp: DateTime.now(),
      endpoint: endpoint,
      requestSize: requestSizeBytes,
      responseSize: responseSizeBytes,
      latency: latencyMs,
      success: success,
      networkCondition: _currentCondition,
    );
    
    _networkMetrics.add(metric);
    
    // Keep only last 1000 metrics
    if (_networkMetrics.length > 1000) {
      _networkMetrics.removeAt(0);
    }
  }
  
  /// Record audio processing metric
  void recordAudioMetric({
    required String operation,
    required int audioSizeBytes,
    required int processingTimeMs,
    required double audioQuality,
  }) {
    final metric = AudioMetric(
      timestamp: DateTime.now(),
      operation: operation,
      audioSize: audioSizeBytes,
      processingTime: processingTimeMs,
      quality: audioQuality,
    );
    
    _audioMetrics.add(metric);
    
    // Keep only last 500 metrics
    if (_audioMetrics.length > 500) {
      _audioMetrics.removeAt(0);
    }
  }
  
  /// Simulate different network conditions for testing
  void simulateNetworkCondition(NetworkCondition condition) {
    _currentCondition = condition;
    AppLogger.info('📡 Simulating network: ${condition.name}');
    
    // Add artificial delay based on condition
    switch (condition) {
      case NetworkCondition.wifi5G:
        // No additional delay
        break;
      case NetworkCondition.wifi24G:
        // Add 20-50ms delay
        Future.delayed(Duration(milliseconds: 20 + math.Random().nextInt(30)));
        break;
      case NetworkCondition.lte4G:
        // Add 50-100ms delay
        Future.delayed(Duration(milliseconds: 50 + math.Random().nextInt(50)));
        break;
      case NetworkCondition.lte3G:
        // Add 100-300ms delay
        Future.delayed(Duration(milliseconds: 100 + math.Random().nextInt(200)));
        break;
      case NetworkCondition.edge2G:
        // Add 300-1000ms delay
        Future.delayed(Duration(milliseconds: 300 + math.Random().nextInt(700)));
        break;
    }
  }
  
  /// Update statistics for a category
  void _updateStatistics(String category) {
    final measurements = _latencyMeasurements[category];
    if (measurements == null || measurements.isEmpty) return;
    
    // Sort for percentile calculation
    final sorted = List<int>.from(measurements)..sort();
    
    // Calculate statistics
    _averageLatencyMs = sorted.reduce((a, b) => a + b) / sorted.length;
    
    // P95
    final p95Index = (sorted.length * 0.95).floor();
    _p95LatencyMs = sorted[math.min(p95Index, sorted.length - 1)].toDouble();
    
    // P99
    final p99Index = (sorted.length * 0.99).floor();
    _p99LatencyMs = sorted[math.min(p99Index, sorted.length - 1)].toDouble();
  }
  
  /// Check for performance alerts
  void _checkPerformanceAlerts(String operation, int latencyMs) {
    if (latencyMs > ALERT_THRESHOLD_MS) {
      final alert = PerformanceAlert(
        timestamp: DateTime.now(),
        operation: operation,
        latencyMs: latencyMs,
        severity: latencyMs > 1000 ? AlertSeverity.critical : AlertSeverity.warning,
        message: 'Operation exceeded ${ALERT_THRESHOLD_MS}ms threshold',
      );
      
      _alertController.add(alert);
    }
  }
  
  /// Emit current metrics
  void _emitMetrics() {
    final metrics = PerformanceMetrics(
      currentLatencyMs: _currentLatencyMs,
      averageLatencyMs: _averageLatencyMs,
      p95LatencyMs: _p95LatencyMs,
      p99LatencyMs: _p99LatencyMs,
      totalRequests: _totalRequests,
      failedRequests: _failedRequests,
      successRate: _totalRequests > 0 
        ? ((_totalRequests - _failedRequests) / _totalRequests * 100) 
        : 100,
      networkCondition: _currentCondition,
      timestamp: DateTime.now(),
    );
    
    _metricsController.add(metrics);
  }
  
  /// Run comprehensive performance test
  Future<PerformanceTestResult> runPerformanceTest() async {
    AppLogger.test('==================== PERFORMANCE TEST START ====================');
    
    final results = <String, List<int>>{};
    final conditions = NetworkCondition.values;
    
    for (final condition in conditions) {
      simulateNetworkCondition(condition);
      AppLogger.info('Testing under ${condition.name} conditions...');
      
      final conditionResults = <int>[];
      
      // Test 10 operations under each condition
      for (int i = 0; i < 10; i++) {
        final operationId = 'test_${condition.name}_$i';
        startOperation(operationId);
        
        // Simulate processing delay
        await Future.delayed(Duration(
          milliseconds: condition.baseLatency + math.Random().nextInt(50)
        ));
        
        final latency = endOperation(operationId, category: 'test');
        conditionResults.add(latency);
        
        // Small delay between tests
        await Future.delayed(Duration(milliseconds: 100));
      }
      
      results[condition.name] = conditionResults;
    }
    
    // Generate test report
    final report = PerformanceTestResult(
      timestamp: DateTime.now(),
      results: results,
      summary: _generateTestSummary(results),
    );
    
    AppLogger.test('==================== PERFORMANCE TEST COMPLETE ====================');
    _logTestReport(report);
    
    return report;
  }
  
  /// Generate test summary
  String _generateTestSummary(Map<String, List<int>> results) {
    final buffer = StringBuffer();
    buffer.writeln('Performance Test Summary');
    buffer.writeln('========================');
    
    for (final entry in results.entries) {
      final condition = entry.key;
      final latencies = entry.value;
      
      if (latencies.isEmpty) continue;
      
      final avg = latencies.reduce((a, b) => a + b) / latencies.length;
      final min = latencies.reduce(math.min);
      final max = latencies.reduce(math.max);
      
      buffer.writeln('\n$condition:');
      buffer.writeln('  Average: ${avg.toStringAsFixed(1)}ms');
      buffer.writeln('  Min: ${min}ms');
      buffer.writeln('  Max: ${max}ms');
      
      // Check against Moshi AI target
      if (avg <= TARGET_E2E_LATENCY_MS) {
        buffer.writeln('  ✅ Meets Moshi AI target!');
      } else {
        buffer.writeln('  ❌ Above target (${TARGET_E2E_LATENCY_MS}ms)');
      }
    }
    
    return buffer.toString();
  }
  
  /// Log test report
  void _logTestReport(PerformanceTestResult report) {
    AppLogger.success('📊 PERFORMANCE TEST REPORT');
    AppLogger.success('==========================');
    
    for (final line in report.summary.split('\n')) {
      if (line.isNotEmpty) {
        AppLogger.success(line);
      }
    }
  }
  
  /// Get current performance summary
  Map<String, dynamic> getCurrentSummary() {
    return {
      'current_latency_ms': _currentLatencyMs,
      'average_latency_ms': _averageLatencyMs.toStringAsFixed(1),
      'p95_latency_ms': _p95LatencyMs.toStringAsFixed(1),
      'p99_latency_ms': _p99LatencyMs.toStringAsFixed(1),
      'total_requests': _totalRequests,
      'failed_requests': _failedRequests,
      'success_rate': '${((_totalRequests - _failedRequests) / math.max(1, _totalRequests) * 100).toStringAsFixed(1)}%',
      'network_condition': _currentCondition.name,
      'meets_moshi_target': _averageLatencyMs <= TARGET_E2E_LATENCY_MS,
    };
  }
  
  /// Reset all metrics
  void reset() {
    _latencyMeasurements.clear();
    _operationStartTimes.clear();
    _networkMetrics.clear();
    _audioMetrics.clear();
    _currentLatencyMs = 0;
    _averageLatencyMs = 0;
    _p95LatencyMs = 0;
    _p99LatencyMs = 0;
    _totalRequests = 0;
    _failedRequests = 0;
    
    AppLogger.info('🔄 Performance metrics reset');
  }
  
  /// Dispose resources
  void dispose() {
    _metricsController.close();
    _alertController.close();
  }
}

/// Network conditions for testing
enum NetworkCondition {
  wifi5G(name: '5G WiFi', baseLatency: 10),
  wifi24G(name: '2.4G WiFi', baseLatency: 30),
  lte4G(name: '4G LTE', baseLatency: 70),
  lte3G(name: '3G', baseLatency: 150),
  edge2G(name: '2G/Edge', baseLatency: 500);
  
  final String name;
  final int baseLatency;
  
  const NetworkCondition({required this.name, required this.baseLatency});
}

/// Performance metrics snapshot
class PerformanceMetrics {
  final int currentLatencyMs;
  final double averageLatencyMs;
  final double p95LatencyMs;
  final double p99LatencyMs;
  final int totalRequests;
  final int failedRequests;
  final double successRate;
  final NetworkCondition networkCondition;
  final DateTime timestamp;
  
  PerformanceMetrics({
    required this.currentLatencyMs,
    required this.averageLatencyMs,
    required this.p95LatencyMs,
    required this.p99LatencyMs,
    required this.totalRequests,
    required this.failedRequests,
    required this.successRate,
    required this.networkCondition,
    required this.timestamp,
  });
}

/// Performance alert
class PerformanceAlert {
  final DateTime timestamp;
  final String operation;
  final int latencyMs;
  final AlertSeverity severity;
  final String message;
  
  PerformanceAlert({
    required this.timestamp,
    required this.operation,
    required this.latencyMs,
    required this.severity,
    required this.message,
  });
}

/// Alert severity levels
enum AlertSeverity {
  info,
  warning,
  critical,
}

/// Network metric
class NetworkMetric {
  final DateTime timestamp;
  final String endpoint;
  final int requestSize;
  final int responseSize;
  final int latency;
  final bool success;
  final NetworkCondition networkCondition;
  
  NetworkMetric({
    required this.timestamp,
    required this.endpoint,
    required this.requestSize,
    required this.responseSize,
    required this.latency,
    required this.success,
    required this.networkCondition,
  });
}

/// Audio processing metric
class AudioMetric {
  final DateTime timestamp;
  final String operation;
  final int audioSize;
  final int processingTime;
  final double quality;
  
  AudioMetric({
    required this.timestamp,
    required this.operation,
    required this.audioSize,
    required this.processingTime,
    required this.quality,
  });
}

/// Performance test result
class PerformanceTestResult {
  final DateTime timestamp;
  final Map<String, List<int>> results;
  final String summary;
  
  PerformanceTestResult({
    required this.timestamp,
    required this.results,
    required this.summary,
  });
}