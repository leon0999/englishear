import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import '../services/performance_monitor.dart';

/// Real-time performance dashboard widget
class PerformanceDashboardWidget extends StatefulWidget {
  final PerformanceMonitor performanceMonitor;
  
  const PerformanceDashboardWidget({
    Key? key,
    required this.performanceMonitor,
  }) : super(key: key);
  
  @override
  _PerformanceDashboardWidgetState createState() => _PerformanceDashboardWidgetState();
}

class _PerformanceDashboardWidgetState extends State<PerformanceDashboardWidget>
    with SingleTickerProviderStateMixin {
  
  StreamSubscription? _metricsSubscription;
  StreamSubscription? _alertSubscription;
  
  PerformanceMetrics? _currentMetrics;
  List<PerformanceAlert> _recentAlerts = [];
  List<double> _latencyHistory = [];
  
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  
  @override
  void initState() {
    super.initState();
    
    // Setup animations
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    ));
    _animationController.forward();
    
    // Subscribe to performance streams
    _metricsSubscription = widget.performanceMonitor.metricsStream.listen((metrics) {
      setState(() {
        _currentMetrics = metrics;
        _latencyHistory.add(metrics.currentLatencyMs.toDouble());
        if (_latencyHistory.length > 20) {
          _latencyHistory.removeAt(0);
        }
      });
    });
    
    _alertSubscription = widget.performanceMonitor.alertStream.listen((alert) {
      setState(() {
        _recentAlerts.insert(0, alert);
        if (_recentAlerts.length > 5) {
          _recentAlerts.removeLast();
        }
      });
    });
  }
  
  @override
  void dispose() {
    _metricsSubscription?.cancel();
    _alertSubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF1A1F3A),
              const Color(0xFF0A0E27),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.speed, color: Colors.amber, size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    'Performance Analytics',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  // Network condition indicator
                  if (_currentMetrics != null)
                    _NetworkConditionBadge(
                      condition: _currentMetrics!.networkCondition,
                    ),
                ],
              ),
            ),
            
            // Main metrics grid
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Primary metrics row
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          title: 'Current Latency',
                          value: '${_currentMetrics?.currentLatencyMs ?? 0}',
                          unit: 'ms',
                          icon: Icons.timer,
                          color: _getLatencyColor(_currentMetrics?.currentLatencyMs ?? 0),
                          trend: _calculateTrend(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          title: 'Average',
                          value: _currentMetrics?.averageLatencyMs.toStringAsFixed(0) ?? '0',
                          unit: 'ms',
                          icon: Icons.analytics,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Secondary metrics row
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          title: 'P95 Latency',
                          value: _currentMetrics?.p95LatencyMs.toStringAsFixed(0) ?? '0',
                          unit: 'ms',
                          icon: Icons.trending_up,
                          color: Colors.purple,
                          isCompact: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          title: 'Success Rate',
                          value: _currentMetrics?.successRate.toStringAsFixed(1) ?? '0',
                          unit: '%',
                          icon: Icons.check_circle,
                          color: Colors.green,
                          isCompact: true,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _MetricCard(
                          title: 'Requests',
                          value: '${_currentMetrics?.totalRequests ?? 0}',
                          unit: '',
                          icon: Icons.sync,
                          color: Colors.orange,
                          isCompact: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Latency chart
                  if (_latencyHistory.isNotEmpty)
                    Container(
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: _LatencyChart(
                        data: _latencyHistory,
                        targetLine: 200, // Moshi AI target
                      ),
                    ),
                  
                  const SizedBox(height: 16),
                  
                  // Moshi AI comparison
                  _MoshiComparisonCard(
                    currentLatency: _currentMetrics?.averageLatencyMs ?? 0,
                  ),
                  
                  // Recent alerts
                  if (_recentAlerts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _AlertsSection(alerts: _recentAlerts),
                  ],
                ],
              ),
            ),
            
            // Footer with test button
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final result = await widget.performanceMonitor.runPerformanceTest();
                        _showTestResults(result);
                      },
                      icon: const Icon(Icons.speed),
                      label: const Text('Run Performance Test'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.withOpacity(0.2),
                        foregroundColor: Colors.amber,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.amber.withOpacity(0.5)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () {
                      widget.performanceMonitor.reset();
                      setState(() {
                        _currentMetrics = null;
                        _recentAlerts.clear();
                        _latencyHistory.clear();
                      });
                    },
                    icon: const Icon(Icons.refresh),
                    color: Colors.white54,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Color _getLatencyColor(int latencyMs) {
    if (latencyMs <= 160) return Colors.green;
    if (latencyMs <= 200) return Colors.blue;
    if (latencyMs <= 500) return Colors.amber;
    return Colors.red;
  }
  
  double _calculateTrend() {
    if (_latencyHistory.length < 2) return 0;
    final recent = _latencyHistory.last;
    final previous = _latencyHistory[_latencyHistory.length - 2];
    return (recent - previous) / previous;
  }
  
  void _showTestResults(PerformanceTestResult result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F3A),
        title: const Text(
          'Performance Test Results',
          style: TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Text(
            result.summary,
            style: const TextStyle(color: Colors.white70, fontFamily: 'monospace'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

/// Metric card widget
class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color color;
  final double? trend;
  final bool isCompact;
  
  const _MetricCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    this.trend,
    this.isCompact = false,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(isCompact ? 12 : 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: isCompact ? 16 : 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: isCompact ? 11 : 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trend != null)
                Icon(
                  trend! > 0 ? Icons.arrow_upward : Icons.arrow_downward,
                  color: trend! > 0 ? Colors.red : Colors.green,
                  size: 14,
                ),
            ],
          ),
          SizedBox(height: isCompact ? 4 : 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: isCompact ? 18 : 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: isCompact ? 12 : 14,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Latency chart widget
class _LatencyChart extends StatelessWidget {
  final List<double> data;
  final double targetLine;
  
  const _LatencyChart({
    required this.data,
    required this.targetLine,
  });
  
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LatencyChartPainter(
        data: data,
        targetLine: targetLine,
      ),
      child: Container(),
    );
  }
}

class _LatencyChartPainter extends CustomPainter {
  final List<double> data;
  final double targetLine;
  
  _LatencyChartPainter({
    required this.data,
    required this.targetLine,
  });
  
  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    
    final paint = Paint()
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    
    // Find max value for scaling
    final maxValue = math.max(data.reduce(math.max), targetLine) * 1.2;
    
    // Draw target line
    paint.color = Colors.amber.withOpacity(0.5);
    paint.strokeWidth = 1;
    paint.pathEffect = null;
    final targetY = size.height - (targetLine / maxValue * size.height);
    canvas.drawLine(
      Offset(0, targetY),
      Offset(size.width, targetY),
      paint,
    );
    
    // Draw data line
    paint.color = Colors.blue;
    paint.strokeWidth = 2;
    
    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = (i / (data.length - 1)) * size.width;
      final y = size.height - (data[i] / maxValue * size.height);
      
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    
    canvas.drawPath(path, paint);
    
    // Draw gradient fill
    final fillPath = Path.from(path);
    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();
    
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.blue.withOpacity(0.3),
        Colors.blue.withOpacity(0.0),
      ],
    );
    
    final fillPaint = Paint()
      ..shader = gradient.createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    
    canvas.drawPath(fillPath, fillPaint);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Moshi AI comparison card
class _MoshiComparisonCard extends StatelessWidget {
  final double currentLatency;
  
  const _MoshiComparisonCard({
    required this.currentLatency,
  });
  
  @override
  Widget build(BuildContext context) {
    final achievedMoshiLevel = currentLatency <= 200;
    final percentageOfMoshi = (200 / math.max(currentLatency, 1) * 100).clamp(0, 100);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: achievedMoshiLevel
            ? [Colors.green.withOpacity(0.2), Colors.green.withOpacity(0.1)]
            : [Colors.orange.withOpacity(0.2), Colors.orange.withOpacity(0.1)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: achievedMoshiLevel 
            ? Colors.green.withOpacity(0.5)
            : Colors.orange.withOpacity(0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            achievedMoshiLevel ? Icons.emoji_events : Icons.speed,
            color: achievedMoshiLevel ? Colors.green : Colors.orange,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  achievedMoshiLevel 
                    ? '🎉 Moshi AI Level Achieved!'
                    : 'Working towards Moshi AI level',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Current: ${currentLatency.toStringAsFixed(0)}ms | Target: 200ms',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: percentageOfMoshi / 100,
                  backgroundColor: Colors.white.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    achievedMoshiLevel ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Network condition badge
class _NetworkConditionBadge extends StatelessWidget {
  final NetworkCondition condition;
  
  const _NetworkConditionBadge({
    required this.condition,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _getConditionColor().withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _getConditionColor().withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.signal_cellular_alt,
            size: 14,
            color: _getConditionColor(),
          ),
          const SizedBox(width: 4),
          Text(
            condition.name,
            style: TextStyle(
              color: _getConditionColor(),
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  Color _getConditionColor() {
    switch (condition) {
      case NetworkCondition.wifi5G:
        return Colors.green;
      case NetworkCondition.wifi24G:
        return Colors.blue;
      case NetworkCondition.lte4G:
        return Colors.amber;
      case NetworkCondition.lte3G:
        return Colors.orange;
      case NetworkCondition.edge2G:
        return Colors.red;
    }
  }
}

/// Alerts section
class _AlertsSection extends StatelessWidget {
  final List<PerformanceAlert> alerts;
  
  const _AlertsSection({
    required this.alerts,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, color: Colors.red, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Recent Alerts',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...alerts.map((alert) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${alert.operation}: ${alert.latencyMs}ms',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 11,
              ),
            ),
          )),
        ],
      ),
    );
  }
}