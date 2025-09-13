import 'dart:typed_data';
import 'dart:collection';
import 'dart:convert';
import 'package:just_audio/just_audio.dart';
import '../core/logger.dart';

/// Singleton audio player to prevent concurrent playback issues
class SingleAudioPlayer {
  static final SingleAudioPlayer _instance = SingleAudioPlayer._internal();
  factory SingleAudioPlayer() => _instance;
  SingleAudioPlayer._internal() {
    _initialize();
  }
  
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  final Queue<_AudioTask> _queue = Queue();
  
  /// Initialize the player with error handling
  void _initialize() {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _onPlaybackCompleted();
      }
    }, onError: (error) {
      AppLogger.error('Player error: $error');
      _isPlaying = false;
      _processNextInQueue();
    });
  }
  
  /// Play PCM audio data with WAV header
  Future<void> playPCM(Uint8List pcmData, String chunkId) async {
    // Queue if already playing
    if (_isPlaying) {
      AppLogger.debug('🔄 Queuing chunk $chunkId (player busy)');
      _queue.add(_AudioTask(pcmData, chunkId));
      return;
    }
    
    await _playInternal(pcmData, chunkId);
  }
  
  /// Internal playback method
  Future<void> _playInternal(Uint8List pcmData, String chunkId) async {
    _isPlaying = true;
    
    try {
      AppLogger.audio('🎵 Playing chunk $chunkId (${pcmData.length} bytes)');
      
      // Add WAV header - CRITICAL for iOS playback
      final wavData = _addWavHeader(pcmData);
      
      // Convert to base64 data URI
      final base64Audio = base64Encode(wavData);
      final dataUri = 'data:audio/wav;base64,$base64Audio';
      
      // Set source and play
      await _player.setUrl(dataUri);
      await _player.play();
      
      // Wait for completion (handled by stream listener)
      
    } catch (e) {
      AppLogger.error('Failed to play chunk $chunkId: $e');
      _isPlaying = false;
      _processNextInQueue();
    }
  }
  
  /// Called when playback completes
  void _onPlaybackCompleted() {
    AppLogger.success('✅ Playback completed');
    _isPlaying = false;
    _processNextInQueue();
  }
  
  /// Process next audio chunk in queue
  void _processNextInQueue() {
    if (_queue.isEmpty) return;
    
    final task = _queue.removeFirst();
    AppLogger.debug('📤 Processing queued chunk ${task.chunkId}');
    _playInternal(task.data, task.chunkId);
  }
  
  /// Add WAV header to PCM data
  Uint8List _addWavHeader(Uint8List pcmData) {
    const int sampleRate = 24000;
    const int channels = 1;
    const int bitsPerSample = 16;
    
    final int dataSize = pcmData.length;
    final int fileSize = dataSize + 36;
    
    final header = ByteData(44);
    
    // RIFF chunk
    header.setUint32(0, 0x46464952, Endian.big);  // "RIFF"
    header.setUint32(4, fileSize, Endian.little);
    header.setUint32(8, 0x45564157, Endian.big);  // "WAVE"
    
    // fmt chunk
    header.setUint32(12, 0x20746d66, Endian.big); // "fmt "
    header.setUint32(16, 16, Endian.little);      // Subchunk1Size
    header.setUint16(20, 1, Endian.little);       // AudioFormat (1 = PCM)
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * channels * bitsPerSample ~/ 8, Endian.little); // ByteRate
    header.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little); // BlockAlign
    header.setUint16(34, bitsPerSample, Endian.little);
    
    // data chunk
    header.setUint32(36, 0x61746164, Endian.big); // "data"
    header.setUint32(40, dataSize, Endian.little);
    
    // Combine header and PCM data
    final wavData = Uint8List(44 + dataSize);
    wavData.setRange(0, 44, header.buffer.asUint8List());
    wavData.setRange(44, wavData.length, pcmData);
    
    return wavData;
  }
  
  /// Stop playback and clear queue
  Future<void> stop() async {
    try {
      await _player.stop();
      _isPlaying = false;
      _queue.clear();
      AppLogger.info('🛑 Playback stopped and queue cleared');
    } catch (e) {
      AppLogger.error('Error stopping playback: $e');
    }
  }
  
  /// Pause playback
  Future<void> pause() async {
    try {
      await _player.pause();
      AppLogger.info('⏸️ Playback paused');
    } catch (e) {
      AppLogger.error('Error pausing playback: $e');
    }
  }
  
  /// Resume playback
  Future<void> resume() async {
    try {
      await _player.play();
      AppLogger.info('▶️ Playback resumed');
    } catch (e) {
      AppLogger.error('Error resuming playback: $e');
    }
  }
  
  /// Get playback state
  bool get isPlaying => _isPlaying;
  
  /// Get queue size
  int get queueSize => _queue.length;
  
  /// Dispose resources
  void dispose() {
    _player.dispose();
    _queue.clear();
    _isPlaying = false;
    AppLogger.info('SingleAudioPlayer disposed');
  }
}

/// Audio task for queueing
class _AudioTask {
  final Uint8List data;
  final String chunkId;
  
  _AudioTask(this.data, this.chunkId);
}