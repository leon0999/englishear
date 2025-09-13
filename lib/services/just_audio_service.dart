import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';
import '../core/logger.dart';
import 'audio_format_helper.dart';

/// Service for stable audio playback using just_audio package
class JustAudioService {
  final AudioPlayer _player = AudioPlayer();
  bool _isInitialized = false;
  
  // Audio processing state
  bool _isPlaying = false;
  String? _currentChunkId;
  
  /// Initialize the audio player
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Set up player event listeners
      _player.playerStateStream.listen((state) {
        if (state.playing) {
          AppLogger.audio('🔊 Audio playing', data: {'chunkId': _currentChunkId});
        }
        
        if (state.processingState == ProcessingState.completed) {
          AppLogger.success('✅ Playback completed for chunk $_currentChunkId');
          _isPlaying = false;
          _currentChunkId = null;
        }
      });
      
      // Handle errors
      _player.playbackEventStream.listen(
        (event) {},
        onError: (Object e, StackTrace stackTrace) {
          AppLogger.error('Playback error: $e');
        },
      );
      
      _isInitialized = true;
      AppLogger.info('JustAudioService initialized successfully');
    } catch (e) {
      AppLogger.error('Failed to initialize JustAudioService: $e');
    }
  }
  
  /// Play PCM audio data
  Future<void> playPCMData(Uint8List pcmData, String chunkId) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      // Validate PCM data
      if (!AudioFormatHelper.isValidPCMData(pcmData)) {
        AppLogger.warning('Invalid PCM data for chunk $chunkId');
        return;
      }
      
      _currentChunkId = chunkId;
      _isPlaying = true;
      
      AppLogger.audio('🎵 Processing audio chunk $chunkId', data: {
        'size': pcmData.length,
        'duration': '${(pcmData.length / 48000).toStringAsFixed(2)}s'
      });
      
      // Convert PCM to WAV format
      final wavData = AudioFormatHelper.pcmToWav(pcmData);
      
      // Create data URI from WAV data
      final uri = Uri.dataFromBytes(
        wavData,
        mimeType: 'audio/wav',
      );
      
      // Set audio source with preloading
      await _player.setAudioSource(
        AudioSource.uri(uri),
        preload: true,
      );
      
      // Play the audio
      await _player.play();
      
      // Wait for completion
      await _waitForCompletion();
      
      AppLogger.success('✅ Successfully played chunk $chunkId');
      
    } catch (e) {
      AppLogger.error('Failed to play chunk $chunkId: $e');
      _isPlaying = false;
      _currentChunkId = null;
      
      // Try fallback method
      await _playWithFallback(pcmData, chunkId);
    }
  }
  
  /// Wait for current playback to complete
  Future<void> _waitForCompletion() async {
    if (!_isPlaying) return;
    
    await _player.playerStateStream.firstWhere(
      (state) => state.processingState == ProcessingState.completed,
    );
  }
  
  /// Fallback playback method using custom audio source
  Future<void> _playWithFallback(Uint8List pcmData, String chunkId) async {
    try {
      AppLogger.info('Attempting fallback playback for chunk $chunkId');
      
      // Convert to WAV if not already
      final wavData = AudioFormatHelper.hasWavHeader(pcmData) 
          ? pcmData 
          : AudioFormatHelper.pcmToWav(pcmData);
      
      // Create a custom audio source
      final audioSource = CustomAudioSource(wavData);
      
      // Set and play
      await _player.setAudioSource(audioSource);
      await _player.play();
      
      AppLogger.success('✅ Fallback playback successful for chunk $chunkId');
      
    } catch (e) {
      AppLogger.error('Fallback playback also failed for chunk $chunkId: $e');
    }
  }
  
  /// Stop current playback
  Future<void> stop() async {
    try {
      await _player.stop();
      _isPlaying = false;
      _currentChunkId = null;
      AppLogger.info('Playback stopped');
    } catch (e) {
      AppLogger.error('Error stopping playback: $e');
    }
  }
  
  /// Pause current playback
  Future<void> pause() async {
    try {
      await _player.pause();
      AppLogger.info('Playback paused');
    } catch (e) {
      AppLogger.error('Error pausing playback: $e');
    }
  }
  
  /// Resume playback
  Future<void> resume() async {
    try {
      await _player.play();
      AppLogger.info('Playback resumed');
    } catch (e) {
      AppLogger.error('Error resuming playback: $e');
    }
  }
  
  /// Get current playback state
  bool get isPlaying => _isPlaying;
  
  /// Get current chunk ID being played
  String? get currentChunkId => _currentChunkId;
  
  /// Dispose of resources
  void dispose() {
    try {
      _player.dispose();
      _isInitialized = false;
      _isPlaying = false;
      _currentChunkId = null;
      AppLogger.info('JustAudioService disposed');
    } catch (e) {
      AppLogger.error('Error disposing JustAudioService: $e');
    }
  }
}

/// Custom audio source for direct byte data playback
class CustomAudioSource extends StreamAudioSource {
  final Uint8List _audioData;
  
  CustomAudioSource(this._audioData);
  
  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _audioData.length;
    
    return StreamAudioResponse(
      sourceLength: _audioData.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_audioData.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}