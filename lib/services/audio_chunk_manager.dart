import 'dart:typed_data';
import 'dart:convert';
import '../core/logger.dart';
import 'single_audio_player.dart';

/// Manager to handle audio chunks and prevent duplicates
class AudioChunkManager {
  final SingleAudioPlayer _player = SingleAudioPlayer();
  final Set<String> _processedChunks = {};
  final Map<String, DateTime> _chunkTimestamps = {};
  
  // Statistics
  int _totalChunksReceived = 0;
  int _duplicatesSkipped = 0;
  int _chunksPlayed = 0;
  
  /// Process an audio chunk
  Future<void> processChunk(String chunkId, Uint8List data, {String? text}) async {
    _totalChunksReceived++;
    
    // Check for duplicate
    if (_processedChunks.contains(chunkId)) {
      _duplicatesSkipped++;
      AppLogger.warning('⚠️ Chunk $chunkId already processed (duplicate #$_duplicatesSkipped), skipping');
      return;
    }
    
    // Validate data
    if (data.isEmpty || data.length < 100) {
      AppLogger.warning('Invalid audio data for chunk $chunkId: ${data.length} bytes');
      return;
    }
    
    // Mark as processed
    _processedChunks.add(chunkId);
    _chunkTimestamps[chunkId] = DateTime.now();
    
    AppLogger.info('🔊 Processing chunk $chunkId (${data.length} bytes)${text != null ? ' - Text: "$text"' : ''}');
    
    // Play using single player
    await _player.playPCM(data, chunkId);
    _chunksPlayed++;
    
    // Clean up old chunks (keep last 100)
    if (_processedChunks.length > 100) {
      _cleanupOldChunks();
    }
  }
  
  /// Process audio delta from WebSocket
  Future<void> processAudioDelta(Map<String, dynamic> data) async {
    try {
      // Extract chunk ID (use item_id or create unique one)
      final chunkId = data['item_id'] ?? 
                      data['response_id'] ?? 
                      'chunk_${DateTime.now().millisecondsSinceEpoch}';
      
      // Extract audio data
      final audioBase64 = data['delta'];
      if (audioBase64 == null || audioBase64.isEmpty) {
        AppLogger.warning('No audio data in delta');
        return;
      }
      
      // Decode base64 to bytes
      final audioData = base64Decode(audioBase64);
      
      // Extract text if available
      final text = data['transcript'] ?? data['text'];
      
      // Process the chunk
      await processChunk(chunkId, audioData, text: text);
      
    } catch (e) {
      AppLogger.error('Failed to process audio delta: $e');
    }
  }
  
  /// Clean up old processed chunks
  void _cleanupOldChunks() {
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(minutes: 5));
    
    // Find chunks older than 5 minutes
    final toRemove = <String>[];
    _chunkTimestamps.forEach((chunkId, timestamp) {
      if (timestamp.isBefore(cutoff)) {
        toRemove.add(chunkId);
      }
    });
    
    // Remove old chunks
    for (final chunkId in toRemove) {
      _processedChunks.remove(chunkId);
      _chunkTimestamps.remove(chunkId);
    }
    
    if (toRemove.isNotEmpty) {
      AppLogger.debug('🧹 Cleaned up ${toRemove.length} old chunks');
    }
  }
  
  /// Clear all processed chunks
  void clear() {
    _processedChunks.clear();
    _chunkTimestamps.clear();
    _player.stop();
    AppLogger.info('🗑️ Cleared all processed chunks and stopped playback');
  }
  
  /// Get statistics
  Map<String, int> getStatistics() {
    return {
      'totalReceived': _totalChunksReceived,
      'duplicatesSkipped': _duplicatesSkipped,
      'chunksPlayed': _chunksPlayed,
      'currentQueueSize': _player.queueSize,
      'processedChunks': _processedChunks.length,
    };
  }
  
  /// Log statistics
  void logStatistics() {
    final stats = getStatistics();
    AppLogger.info('📊 Audio Statistics:');
    AppLogger.info('  Total chunks received: ${stats['totalReceived']}');
    AppLogger.info('  Duplicates skipped: ${stats['duplicatesSkipped']}');
    AppLogger.info('  Chunks played: ${stats['chunksPlayed']}');
    AppLogger.info('  Current queue size: ${stats['currentQueueSize']}');
    AppLogger.info('  Processed chunks in memory: ${stats['processedChunks']}');
  }
  
  /// Stop playback
  Future<void> stop() async {
    await _player.stop();
  }
  
  /// Pause playback
  Future<void> pause() async {
    await _player.pause();
  }
  
  /// Resume playback
  Future<void> resume() async {
    await _player.resume();
  }
  
  /// Check if playing
  bool get isPlaying => _player.isPlaying;
  
  /// Dispose resources
  void dispose() {
    _player.dispose();
    clear();
  }
}