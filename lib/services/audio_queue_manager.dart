import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import '../core/logger.dart';

/// Audio queue manager to ensure sequential playback without overlapping
class AudioQueueManager {
  final Queue<AudioChunk> _playQueue = Queue();
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Timer? _playbackTimer;
  
  // Playback settings
  static const double PLAYBACK_RATE = 0.85; // 15% slower for clarity
  static const int DEFAULT_CHUNK_GAP_MS = 50;
  static const int SENTENCE_END_GAP_MS = 300;
  static const int PHRASE_GAP_MS = 150;
  
  // Performance tracking
  int _totalChunksPlayed = 0;
  DateTime? _lastPlaybackTime;
  
  AudioQueueManager() {
    _initializePlayer();
  }
  
  void _initializePlayer() {
    _audioPlayer.setReleaseMode(ReleaseMode.stop);
    _audioPlayer.setVolume(1.0);
    _audioPlayer.setPlaybackRate(PLAYBACK_RATE);
    
    // Listen for playback completion
    _audioPlayer.onPlayerComplete.listen((_) {
      AppLogger.debug('Player completed current chunk');
    });
    
    AppLogger.info('🎵 Audio queue manager initialized');
  }
  
  /// Add audio chunk to the queue
  void addChunk(String id, Uint8List data, {String? text}) {
    // Detect sentence boundaries
    bool isEndOfSentence = false;
    bool isPhraseEnd = false;
    
    if (text != null && text.isNotEmpty) {
      isEndOfSentence = RegExp(r'[.!?]\s*$').hasMatch(text);
      isPhraseEnd = RegExp(r'[,:;]\s*$').hasMatch(text);
    }
    
    final chunk = AudioChunk(
      id: id,
      data: data,
      text: text,
      isEndOfSentence: isEndOfSentence,
      isPhraseEnd: isPhraseEnd,
      timestamp: DateTime.now(),
    );
    
    _playQueue.add(chunk);
    AppLogger.info('📦 Added chunk $id to queue (${data.length} bytes, sentence end: $isEndOfSentence)');
    
    // Start playback if not already playing
    if (!_isPlaying) {
      _startPlayback();
    }
  }
  
  /// Start sequential playback of queued chunks
  Future<void> _startPlayback() async {
    if (_isPlaying) {
      AppLogger.warning('Playback already in progress');
      return;
    }
    
    _isPlaying = true;
    AppLogger.info('▶️ Starting sequential playback');
    
    try {
      while (_playQueue.isNotEmpty) {
        final chunk = _playQueue.removeFirst();
        
        // Play the chunk and wait for completion
        await _playChunk(chunk);
        
        // Add appropriate gap based on text punctuation
        int gapMs = DEFAULT_CHUNK_GAP_MS;
        if (chunk.isEndOfSentence) {
          gapMs = SENTENCE_END_GAP_MS;
          AppLogger.debug('Adding sentence-end pause: ${gapMs}ms');
        } else if (chunk.isPhraseEnd) {
          gapMs = PHRASE_GAP_MS;
          AppLogger.debug('Adding phrase-end pause: ${gapMs}ms');
        }
        
        // Wait before playing next chunk
        await Future.delayed(Duration(milliseconds: gapMs));
      }
    } catch (e) {
      AppLogger.error('Playback error', e);
    } finally {
      _isPlaying = false;
      AppLogger.info('⏹️ Playback queue completed');
    }
  }
  
  /// Play a single audio chunk
  Future<void> _playChunk(AudioChunk chunk) async {
    try {
      final startTime = DateTime.now();
      
      // Convert PCM to WAV
      final wavData = _createWavFromPcm(chunk.data);
      
      // Play and wait for completion
      await _audioPlayer.play(BytesSource(wavData));
      
      // Wait for the audio to actually finish playing
      final duration = _calculateDuration(chunk.data);
      await Future.delayed(Duration(milliseconds: duration));
      
      _totalChunksPlayed++;
      _lastPlaybackTime = DateTime.now();
      
      final playbackTime = DateTime.now().difference(startTime).inMilliseconds;
      AppLogger.success('✅ Played chunk ${chunk.id} (${playbackTime}ms, text: "${chunk.text ?? "no text"}")');
      
    } catch (e) {
      AppLogger.error('Failed to play chunk ${chunk.id}', e);
      throw e;
    }
  }
  
  /// Calculate audio duration in milliseconds
  int _calculateDuration(Uint8List pcmData) {
    const int sampleRate = 24000;
    const int bytesPerSample = 2;
    final samples = pcmData.length / bytesPerSample;
    final seconds = samples / sampleRate;
    final adjustedSeconds = seconds / PLAYBACK_RATE; // Adjust for playback rate
    return (adjustedSeconds * 1000).round();
  }
  
  /// Create WAV header for PCM data
  Uint8List _createWavFromPcm(Uint8List pcmData) {
    const int sampleRate = 24000;
    const int numChannels = 1;
    const int bitsPerSample = 16;
    
    final int dataSize = pcmData.length;
    final int fileSize = dataSize + 36;
    
    final wavFile = Uint8List(fileSize + 8);
    final wavData = wavFile.buffer.asByteData();
    
    // RIFF header
    wavFile.setRange(0, 4, 'RIFF'.codeUnits);
    wavData.setUint32(4, fileSize, Endian.little);
    wavFile.setRange(8, 12, 'WAVE'.codeUnits);
    
    // fmt chunk
    wavFile.setRange(12, 16, 'fmt '.codeUnits);
    wavData.setUint32(16, 16, Endian.little); // fmt chunk size
    wavData.setUint16(20, 1, Endian.little); // PCM format
    wavData.setUint16(22, numChannels, Endian.little);
    wavData.setUint32(24, sampleRate, Endian.little);
    wavData.setUint32(28, sampleRate * numChannels * bitsPerSample ~/ 8, Endian.little);
    wavData.setUint16(32, numChannels * bitsPerSample ~/ 8, Endian.little);
    wavData.setUint16(34, bitsPerSample, Endian.little);
    
    // data chunk
    wavFile.setRange(36, 40, 'data'.codeUnits);
    wavData.setUint32(40, dataSize, Endian.little);
    wavFile.setRange(44, 44 + dataSize, pcmData);
    
    return wavFile;
  }
  
  /// Clear the queue
  void clear() {
    _playQueue.clear();
    _audioPlayer.stop();
    _isPlaying = false;
    AppLogger.info('🗑️ Audio queue cleared');
  }
  
  /// Get queue status
  Map<String, dynamic> getStatus() {
    return {
      'queueSize': _playQueue.length,
      'isPlaying': _isPlaying,
      'totalChunksPlayed': _totalChunksPlayed,
      'lastPlaybackTime': _lastPlaybackTime?.toIso8601String(),
    };
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    clear();
    await _audioPlayer.dispose();
    _playbackTimer?.cancel();
    AppLogger.info('Audio queue manager disposed');
  }
}

/// Audio chunk with metadata
class AudioChunk {
  final String id;
  final Uint8List data;
  final String? text;
  final bool isEndOfSentence;
  final bool isPhraseEnd;
  final DateTime timestamp;
  
  AudioChunk({
    required this.id,
    required this.data,
    this.text,
    this.isEndOfSentence = false,
    this.isPhraseEnd = false,
    required this.timestamp,
  });
}