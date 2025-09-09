import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Conversation history widget with search and filtering
class ConversationHistoryWidget extends StatefulWidget {
  final List<ConversationEntry> conversations;
  final Function(ConversationEntry)? onTap;
  final Function(ConversationEntry)? onDelete;
  
  const ConversationHistoryWidget({
    Key? key,
    required this.conversations,
    this.onTap,
    this.onDelete,
  }) : super(key: key);
  
  @override
  _ConversationHistoryWidgetState createState() => _ConversationHistoryWidgetState();
}

class _ConversationHistoryWidgetState extends State<ConversationHistoryWidget> {
  String _searchQuery = '';
  ConversationFilter _filter = ConversationFilter.all;
  
  List<ConversationEntry> get filteredConversations {
    var filtered = widget.conversations;
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((conv) =>
        conv.userText.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        conv.aiResponse.toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }
    
    // Apply time filter
    final now = DateTime.now();
    switch (_filter) {
      case ConversationFilter.today:
        filtered = filtered.where((conv) =>
          conv.timestamp.isAfter(DateTime(now.year, now.month, now.day))
        ).toList();
        break;
      case ConversationFilter.week:
        filtered = filtered.where((conv) =>
          conv.timestamp.isAfter(now.subtract(Duration(days: 7)))
        ).toList();
        break;
      case ConversationFilter.month:
        filtered = filtered.where((conv) =>
          conv.timestamp.isAfter(now.subtract(Duration(days: 30)))
        ).toList();
        break;
      case ConversationFilter.all:
        // No filter
        break;
    }
    
    // Sort by timestamp (newest first)
    filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    
    return filtered;
  }
  
  @override
  Widget build(BuildContext context) {
    final conversations = filteredConversations;
    
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Header with search and filter
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E27),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Column(
              children: [
                // Search bar
                TextField(
                  onChanged: (value) => setState(() => _searchQuery = value),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search conversations...',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.5)),
                    suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white54),
                          onPressed: () => setState(() => _searchQuery = ''),
                        )
                      : null,
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.05),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
                const SizedBox(height: 12),
                // Filter chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ConversationFilter.values.map((filter) {
                      final isSelected = _filter == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(
                            filter.label,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (_) => setState(() => _filter = filter),
                          selectedColor: Colors.blue.withOpacity(0.3),
                          backgroundColor: Colors.white.withOpacity(0.1),
                          side: BorderSide(
                            color: isSelected ? Colors.blue : Colors.white24,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          
          // Conversation list
          Expanded(
            child: conversations.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 48,
                        color: Colors.white.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _searchQuery.isNotEmpty 
                          ? 'No conversations found'
                          : 'No conversations yet',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: conversations.length,
                  itemBuilder: (context, index) {
                    final conversation = conversations[index];
                    return _ConversationCard(
                      conversation: conversation,
                      onTap: () => widget.onTap?.call(conversation),
                      onDelete: () => widget.onDelete?.call(conversation),
                    );
                  },
                ),
          ),
          
          // Footer with stats
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0A0E27),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(
                  icon: Icons.chat,
                  value: conversations.length.toString(),
                  label: 'Conversations',
                ),
                _StatItem(
                  icon: Icons.schedule,
                  value: _calculateAverageResponseTime(conversations),
                  label: 'Avg Response',
                ),
                _StatItem(
                  icon: Icons.trending_up,
                  value: _calculateSuccessRate(conversations),
                  label: 'Success Rate',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  String _calculateAverageResponseTime(List<ConversationEntry> conversations) {
    if (conversations.isEmpty) return '0ms';
    final avgMs = conversations
      .map((c) => c.responseLatencyMs)
      .reduce((a, b) => a + b) / conversations.length;
    return '${avgMs.toStringAsFixed(0)}ms';
  }
  
  String _calculateSuccessRate(List<ConversationEntry> conversations) {
    if (conversations.isEmpty) return '0%';
    final successful = conversations.where((c) => c.responseLatencyMs < 200).length;
    final rate = (successful / conversations.length * 100);
    return '${rate.toStringAsFixed(0)}%';
  }
}

/// Individual conversation card
class _ConversationCard extends StatelessWidget {
  final ConversationEntry conversation;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  
  const _ConversationCard({
    required this.conversation,
    this.onTap,
    this.onDelete,
  });
  
  @override
  Widget build(BuildContext context) {
    final timeFormatter = DateFormat('HH:mm');
    final dateFormatter = DateFormat('MMM dd');
    final isToday = DateTime.now().day == conversation.timestamp.day;
    
    return Card(
      color: Colors.white.withOpacity(0.05),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.white.withOpacity(0.1)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with timestamp and latency
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isToday 
                      ? timeFormatter.format(conversation.timestamp)
                      : dateFormatter.format(conversation.timestamp),
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                  Row(
                    children: [
                      // Latency badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getLatencyColor(conversation.responseLatencyMs).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _getLatencyColor(conversation.responseLatencyMs).withOpacity(0.5),
                          ),
                        ),
                        child: Text(
                          '${conversation.responseLatencyMs}ms',
                          style: TextStyle(
                            color: _getLatencyColor(conversation.responseLatencyMs),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (onDelete != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.withOpacity(0.7)),
                          onPressed: onDelete,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // User message
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.person, size: 16, color: Colors.blue.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      conversation.userText,
                      style: const TextStyle(color: Colors.white70, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              
              // AI response
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.psychology, size: 16, color: Colors.green.withOpacity(0.7)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      conversation.aiResponse,
                      style: const TextStyle(color: Colors.white60, fontSize: 14),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Color _getLatencyColor(int latencyMs) {
    if (latencyMs <= 160) return Colors.green;  // Moshi AI level
    if (latencyMs <= 200) return Colors.blue;   // Target met
    if (latencyMs <= 500) return Colors.amber;  // Acceptable
    return Colors.red;  // Needs improvement
  }
}

/// Stat item widget
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  
  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
  });
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white54, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

/// Conversation entry model
class ConversationEntry {
  final String id;
  final String userText;
  final String aiResponse;
  final DateTime timestamp;
  final int responseLatencyMs;
  final Map<String, dynamic>? metadata;
  
  ConversationEntry({
    required this.id,
    required this.userText,
    required this.aiResponse,
    required this.timestamp,
    required this.responseLatencyMs,
    this.metadata,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'userText': userText,
    'aiResponse': aiResponse,
    'timestamp': timestamp.toIso8601String(),
    'responseLatencyMs': responseLatencyMs,
    'metadata': metadata,
  };
  
  factory ConversationEntry.fromJson(Map<String, dynamic> json) => ConversationEntry(
    id: json['id'],
    userText: json['userText'],
    aiResponse: json['aiResponse'],
    timestamp: DateTime.parse(json['timestamp']),
    responseLatencyMs: json['responseLatencyMs'],
    metadata: json['metadata'],
  );
}

/// Filter options
enum ConversationFilter {
  all('All'),
  today('Today'),
  week('This Week'),
  month('This Month');
  
  final String label;
  const ConversationFilter(this.label);
}