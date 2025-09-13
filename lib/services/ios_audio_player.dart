import 'dart:io';
import 'dart:typed_data';
import 'dart:collection';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../core/logger.dart';

/// iOS-optimized audio player using file-based playback
/// Avoids data URI issues on iOS platform
class IOSAudioPlayer {
  static final IOSAudioPlayer _instance = IOSAudioPlayer._internal();
  factory IOSAudioPlayer() => _instance;
  IOSAudioPlayer._internal();
  
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  final Queue<AudioChunk> _queue = Queue();
  String? _tempDir;
  
  /// Initialize iOS audio player with proper settings
  Future<void> initialize() async {
    try {
      // Get temporary directory for audio files
      final dir = await getTemporaryDirectory();
      _tempDir = dir.path;
      
      // Configure for iOS low-latency playback
      await _player.setPlayerMode(PlayerMode.lowLatency);
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(1.0);
      
      // Set up completion listener
      _player.onPlayerComplete.listen((_) {
        _onPlaybackCompleted();
      });
      
      AppLogger.success('✅ IOSAudioPlayer initialized with temp dir: $_tempDir');
    } catch (e) {
      AppLogger.error('Failed to initialize IOSAudioPlayer: $e');
    }
  }
  
  /// Play PCM audio data by converting to WAV file
  Future<void> playPCM(String chunkId, Uint8List pcmData) async {
    // Queue if already playing
    if (_isPlaying) {
      _queue.add(AudioChunk(chunkId, pcmData));
      AppLogger.debug('🔄 Queuing chunk $chunkId (${_queue.length} in queue)');
      return;
    }
    
    await _playChunk(chunkId, pcmData);
  }
  
  /// Internal method to play a single chunk
  Future<void> _playChunk(String chunkId, Uint8List pcmData) async {
    _isPlaying = true;
    
    try {
      // Validate PCM data
      if (pcmData.isEmpty || pcmData.length < 100) {
        throw Exception('Invalid PCM data: ${pcmData.length} bytes');
      }
      
      // Create WAV file with proper headers
      final wavData = _createWavFile(pcmData);
      
      // Generate unique filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '$_tempDir/audio_${chunkId}_$timestamp.wav';
      final file = File(filePath);
      
      // Write WAV data to file
      await file.writeAsBytes(wavData);
      
      // Verify file exists
      if (!await file.exists()) {
        throw Exception('WAV file not created at $filePath');
      }
      
      AppLogger.audio('🎵 Playing chunk $chunkId from file (${wavData.length} bytes)');
      
      // Play using DeviceFileSource (iOS compatible)
      await _player.play(DeviceFileSource(filePath));
      
      // Note: Completion is handled by listener
      
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
    
    // Clean up temporary file
    _cleanupTempFiles();
    
    // Process next in queue
    _processNextInQueue();
  }
  
  /// Process next audio chunk in queue
  void _processNextInQueue() {
    if (_queue.isEmpty) return;
    
    final next = _queue.removeFirst();
    AppLogger.debug('📤 Processing queued chunk ${next.id} (${_queue.length} remaining)');
    _playChunk(next.id, next.data);
  }
  
  /// Create WAV file from PCM data
  Uint8List _createWavFile(Uint8List pcmData) {
    const int sampleRate = 24000;  // OpenAI Realtime API sample rate
    const int channels = 1;         // Mono
    const int bitsPerSample = 16;   // PCM16
    
    final dataSize = pcmData.length;
    final fileSize = dataSize + 36;  // 44 byte header - 8 bytes for RIFF
    
    final wav = BytesBuilder();
    
    // RIFF header
    wav.add(utf8.encode('RIFF'));
    wav.add(_int32ToBytes(fileSize));
    wav.add(utf8.encode('WAVE'));
    
    // fmt chunk
    wav.add(utf8.encode('fmt '));
    wav.add(_int32ToBytes(16));  // Subchunk1Size (16 for PCM)
    wav.add(_int16ToBytes(1));   // AudioFormat (1 = PCM)
    wav.add(_int16ToBytes(channels));
    wav.add(_int32ToBytes(sampleRate));
    wav.add(_int32ToBytes(sampleRate * channels * bitsPerSample ~/ 8));  // ByteRate
    wav.add(_int16ToBytes(channels * bitsPerSample ~/ 8));  // BlockAlign
    wav.add(_int16ToBytes(bitsPerSample));
    
    // data chunk
    wav.add(utf8.encode('data'));
    wav.add(_int32ToBytes(dataSize));
    wav.add(pcmData);
    
    return wav.toBytes();
  }
  
  /// Convert int32 to little-endian bytes
  Uint8List _int32ToBytes(int value) {
    final bytes = Uint8List(4);
    bytes.buffer.asByteData().setInt32(0, value, Endian.little);
    return bytes;
  }
  
  /// Convert int16 to little-endian bytes
  Uint8List _int16ToBytes(int value) {
    final bytes = Uint8List(2);
    bytes.buffer.asByteData().setInt16(0, value, Endian.little);
    return bytes;
  }
  
  /// Clean up old temporary files
  void _cleanupTempFiles() {
    try {
      if (_tempDir == null) return;
      
      final dir = Directory(_tempDir!);
      if (!dir.existsSync()) return;
      
      // Delete WAV files older than 1 minute
      final cutoff = DateTime.now().subtract(Duration(minutes: 1));
      
      dir.listSync().where((file) {
        return file.path.contains('audio_') && 
               file.path.endsWith('.wav') &&
               file.statSync().modified.isBefore(cutoff);
      }).forEach((file) {
        try {
          file.deleteSync();
          AppLogger.debug('🧹 Deleted old temp file: ${file.path}');
        } catch (e) {
          // Ignore deletion errors
        }
      });
    } catch (e) {
      AppLogger.debug('Temp file cleanup error: $e');
    }
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
      await _player.resume();
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
    _cleanupTempFiles();
    AppLogger.info('IOSAudioPlayer disposed');
  }
}

/// Audio chunk data
class AudioChunk {
  final String id;
  final Uint8List data;
  
  AudioChunk(this.id, this.data);
}