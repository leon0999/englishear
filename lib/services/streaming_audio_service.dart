import 'dart:async';
import 'dart:typed_data';
import 'dart:collection';
import 'dart:io';
import '../core/logger.dart';
import 'ios_audio_player.dart';
import 'audio_format_helper.dart';

/// Streaming audio service optimized for real-time playback
/// Similar to ChatGPT Voice's approach with minimal buffering
class StreamingAudioService {
  // Audio players
  final IOSAudioPlayer _iosPlayer = IOSAudioPlayer();
  
  // Stream controller for incoming audio data
  final StreamController<Uint8List> _audioStreamController = StreamController<Uint8List>.broadcast();
  
  // Buffer management
  static const int CHUNK_SIZE = 4800;  // 100ms at 24kHz (24000 * 0.1 * 2 bytes)
  static const int MIN_BUFFER_SIZE = 2400;  // 50ms minimum before playing
  static const int MAX_BUFFER_SIZE = 48000;  // 1 second max buffer
  
  final List<int> _buffer = [];
  final Queue<Uint8List> _playQueue = Queue();
  
  // State
  bool _isInitialized = false;
  bool _isProcessing = false;
  int _totalBytesReceived = 0;
  int _totalBytesPlayed = 0;
  
  // Performance metrics
  DateTime? _firstChunkTime;
  DateTime? _lastChunkTime;
  int _chunkCount = 0;
  
  // Timers
  Timer? _processTimer;
  Timer? _flushTimer;
  
  /// Initialize the streaming service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Initialize iOS player
      if (Platform.isIOS) {
        await _iosPlayer.initialize();
        AppLogger.info('iOS audio player initialized for streaming');
      }
      
      // Set up stream listener
      _audioStreamController.stream.listen(
        _handleIncomingAudio,
        onError: (error) {
          AppLogger.error('Audio stream error: $error');
        },
      );
      
      // Start processing timer (10ms interval for smooth playback)
      _processTimer = Timer.periodic(Duration(milliseconds: 10), (_) {
        _processBuffer();
      });
      
      _isInitialized = true;
      AppLogger.success('✅ StreamingAudioService initialized');
      
    } catch (e) {
      AppLogger.error('Failed to initialize StreamingAudioService: $e');
    }
  }
  
  /// Handle incoming audio data
  void _handleIncomingAudio(Uint8List data) {
    if (data.isEmpty) return;
    
    // Track first chunk time for latency measurement
    _firstChunkTime ??= DateTime.now();
    _lastChunkTime = DateTime.now();
    _chunkCount++;
    
    // Add to buffer
    _buffer.addAll(data);
    _totalBytesReceived += data.length;
    
    AppLogger.debug('📥 Received audio chunk #$_chunkCount: ${data.length} bytes (buffer: ${_buffer.length} bytes)');
    
    // Reset flush timer
    _resetFlushTimer();
    
    // Process immediately if we have enough data
    if (_buffer.length >= MIN_BUFFER_SIZE) {
      _processBuffer();
    }
  }
  
  /// Process buffered audio data
  void _processBuffer() {
    if (_isProcessing || _buffer.isEmpty) return;
    
    _isProcessing = true;
    
    try {
      // Process chunks while buffer has enough data
      while (_buffer.length >= CHUNK_SIZE) {
        // Extract chunk
        final chunkData = Uint8List.fromList(_buffer.take(CHUNK_SIZE).toList());
        _buffer.removeRange(0, CHUNK_SIZE);
        
        // Add to play queue
        _playQueue.add(chunkData);
        
        AppLogger.debug('🎵 Queued chunk for playback: ${chunkData.length} bytes');
      }
      
      // Play queued chunks
      _playQueuedChunks();
      
    } catch (e) {
      AppLogger.error('Error processing buffer: $e');
    } finally {
      _isProcessing = false;
    }
  }
  
  /// Play queued audio chunks
  void _playQueuedChunks() {
    if (_playQueue.isEmpty) return;
    
    // Play all queued chunks
    while (_playQueue.isNotEmpty) {
      final chunk = _playQueue.removeFirst();
      final chunkId = 'stream_${DateTime.now().millisecondsSinceEpoch}';
      
      // Play using iOS player
      if (Platform.isIOS) {
        _iosPlayer.playPCM(chunkId, chunk);
      }
      
      _totalBytesPlayed += chunk.length;
    }
    
    // Log performance metrics
    if (_chunkCount % 10 == 0) {
      _logPerformanceMetrics();
    }
  }
  
  /// Add audio data to stream
  void addAudioData(Uint8List data) {
    if (!_isInitialized) {
      AppLogger.warning('StreamingAudioService not initialized, initializing now...');
      initialize().then((_) {
        _audioStreamController.add(data);
      });
    } else {
      _audioStreamController.add(data);
    }
  }
  
  /// Flush remaining buffer
  Future<void> flush() async {
    AppLogger.info('🚿 Flushing audio buffer (${_buffer.length} bytes remaining)');
    
    // Cancel flush timer
    _flushTimer?.cancel();
    
    // Process any remaining data in buffer
    if (_buffer.isNotEmpty) {
      // Pad with silence if needed to reach minimum chunk size
      if (_buffer.length < MIN_BUFFER_SIZE) {
        final silenceNeeded = MIN_BUFFER_SIZE - _buffer.length;
        _buffer.addAll(List.filled(silenceNeeded, 0));
        AppLogger.debug('Added ${silenceNeeded} bytes of silence for flush');
      }
      
      // Create final chunk
      final finalChunk = Uint8List.fromList(_buffer);
      _buffer.clear();
      
      // Play final chunk
      final chunkId = 'flush_${DateTime.now().millisecondsSinceEpoch}';
      if (Platform.isIOS) {
        await _iosPlayer.playPCM(chunkId, finalChunk);
      }
      
      _totalBytesPlayed += finalChunk.length;
    }
    
    _logPerformanceMetrics();
  }
  
  /// Reset flush timer
  void _resetFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer(Duration(milliseconds: 500), () {
      // Auto-flush if no new data for 500ms
      if (_buffer.isNotEmpty) {
        AppLogger.info('Auto-flushing after 500ms of silence');
        flush();
      }
    });
  }
  
  /// Clear all buffers and reset state
  void clear() {
    _buffer.clear();
    _playQueue.clear();
    _totalBytesReceived = 0;
    _totalBytesPlayed = 0;
    _firstChunkTime = null;
    _lastChunkTime = null;
    _chunkCount = 0;
    _flushTimer?.cancel();
    
    if (Platform.isIOS) {
      _iosPlayer.stop();
    }
    
    AppLogger.info('🗑️ Cleared all audio buffers');
  }
  
  /// Log performance metrics
  void _logPerformanceMetrics() {
    if (_firstChunkTime == null) return;
    
    final now = DateTime.now();
    final totalDuration = now.difference(_firstChunkTime!);
    final bytesPerSecond = _totalBytesReceived / (totalDuration.inMilliseconds / 1000.0);
    final playbackRatio = _totalBytesPlayed / (_totalBytesReceived > 0 ? _totalBytesReceived : 1);
    
    AppLogger.info('📊 Streaming Metrics:');
    AppLogger.info('  Chunks received: $_chunkCount');
    AppLogger.info('  Total received: $_totalBytesReceived bytes');
    AppLogger.info('  Total played: $_totalBytesPlayed bytes');
    AppLogger.info('  Throughput: ${bytesPerSecond.toStringAsFixed(0)} bytes/sec');
    AppLogger.info('  Playback ratio: ${(playbackRatio * 100).toStringAsFixed(1)}%');
    AppLogger.info('  Buffer size: ${_buffer.length} bytes');
    AppLogger.info('  Queue size: ${_playQueue.length} chunks');
  }
  
  /// Get current buffer size
  int get bufferSize => _buffer.length;
  
  /// Get queue size
  int get queueSize => _playQueue.length;
  
  /// Check if playing
  bool get isPlaying => _iosPlayer.isPlaying;
  
  /// Dispose resources
  void dispose() {
    _processTimer?.cancel();
    _flushTimer?.cancel();
    _audioStreamController.close();
    _iosPlayer.dispose();
    clear();
    _isInitialized = false;
    AppLogger.info('StreamingAudioService disposed');
  }
}