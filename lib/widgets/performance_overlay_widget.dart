import 'package:flutter/material.dart';

/// Performance Overlay Widget for real-time metrics display
class PerformanceOverlayWidget extends StatelessWidget {
  final Map<String, dynamic> metrics;
  final VoidCallback onClose;
  
  const PerformanceOverlayWidget({
    super.key,
    required this.metrics,
    required this.onClose,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Performance Metrics',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              GestureDetector(
                onTap: onClose,
                child: const Icon(
                  Icons.close,
                  color: Colors.white54,
                  size: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ..._buildMetricRows(),
        ],
      ),
    );
  }
  
  List<Widget> _buildMetricRows() {
    final rows = <Widget>[];
    
    // API Metrics
    if (metrics['api'] != null) {
      final apiMetrics = metrics['api'] as Map<String, dynamic>;
      rows.add(_buildSection('API Performance'));
      
      if (apiMetrics['avg_first_byte_latency'] != null) {
        rows.add(_buildMetricRow(
          'First Byte',
          '${apiMetrics['avg_first_byte_latency']}ms',
          _getLatencyColor(apiMetrics['avg_first_byte_latency']),
        ));
      }
      
      if (apiMetrics['total_responses'] != null) {
        rows.add(_buildMetricRow(
          'Responses',
          '${apiMetrics['total_responses']}',
          Colors.white70,
        ));
      }
    }
    
    // Conversation Metrics
    if (metrics['conversation'] != null) {
      final convMetrics = metrics['conversation'] as Map<String, dynamic>;
      rows.add(const SizedBox(height: 8));
      rows.add(_buildSection('Conversation'));
      
      convMetrics.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          rows.add(_buildMetricRow(
            _formatMetricName(key),
            '${value['avg']}ms',
            _getLatencyColor(double.tryParse(value['avg'].toString()) ?? 0),
          ));
        }
      });
    }
    
    // Audio Metrics
    if (metrics['audio'] != null) {
      final audioMetrics = metrics['audio'] as Map<String, dynamic>;
      rows.add(const SizedBox(height: 8));
      rows.add(_buildSection('Audio'));
      
      if (audioMetrics['buffer_size'] != null) {
        rows.add(_buildMetricRow(
          'Buffer',
          '${audioMetrics['buffer_size']} chunks',
          Colors.white70,
        ));
      }
      
      if (audioMetrics['playback_speed'] != null) {
        rows.add(_buildMetricRow(
          'Speed',
          '${audioMetrics['playback_speed']}x',
          Colors.white70,
        ));
      }
    }
    
    return rows;
  }
  
  Widget _buildSection(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
  
  Widget _buildMetricRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatMetricName(String name) {
    return name
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) => word.isNotEmpty 
            ? '${word[0].toUpperCase()}${word.substring(1)}' 
            : word)
        .join(' ');
  }
  
  Color _getLatencyColor(double latency) {
    if (latency < 100) return Colors.green;
    if (latency < 300) return Colors.yellow;
    if (latency < 500) return Colors.orange;
    return Colors.red;
  }
}