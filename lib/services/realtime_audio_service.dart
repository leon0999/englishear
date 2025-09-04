// lib/services/realtime_audio_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../core/logger.dart';

/// Enhanced audio service for OpenAI Realtime API
/// Handles PCM16 audio at 24kHz sample rate
class RealtimeAudioService {
  // Audio players for output
  final _MockAudioPlayer _audioPlayer = _MockAudioPlayer();
  final List<_MockAudioPlayer> _playerPool = [];
  int _currentPlayerIndex = 0;
  
  // Audio recorder for input
  final AudioRecorder _recorder = AudioRecorder();
  
  // Audio queue for smooth playback
  final List<Uint8List> _audioQueue = [];
  bool _isPlaying = false;
  Timer? _playbackTimer;
  
  // Stream controllers
  final _audioLevelController = StreamController<double>.broadcast();
  final _audioDataController = StreamController<Uint8List>.broadcast();
  
  Stream<double> get audioLevelStream => _audioLevelController.stream;
  Stream<Uint8List> get audioDataStream => _audioDataController.stream;
  
  // Recording state
  bool _isRecording = false;
  StreamSubscription? _recordingSubscription;
  
  RealtimeAudioService() {
    _initializePlayerPool();
  }
  
  /// Initialize a pool of audio players for smooth playback
  void _initializePlayerPool() {
    // Create 3 players for rotating playback
    for (int i = 0; i < 3; i++) {
      _playerPool.add(_MockAudioPlayer());
    }
  }
  
  /// Start recording audio for input
  Future<void> startRecording(Function(Uint8List) onData) async {
    try {
      if (_isRecording) {
        AppLogger.warning('Already recording');
        return;
      }
      
      // Check permission
      if (!await _recorder.hasPermission()) {
        throw Exception('Microphone permission denied');
      }
      
      // Start recording with PCM16 at 24kHz
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 24000,  // Realtime API requirement
          numChannels: 1,
          bitRate: 128000,
        ),
      );
      
      _isRecording = true;
      AppLogger.info('Started recording at 24kHz PCM16');
      
      // Listen to audio stream
      _recordingSubscription = stream.listen(
        (chunk) {
          if (chunk.isNotEmpty) {
            onData(chunk);
            _calculateAudioLevel(chunk);
          }
        },
        onError: (error) {
          AppLogger.error('Recording error', error);
        },
      );
    } catch (e) {
      AppLogger.error('Failed to start recording', e);
      _isRecording = false;
      rethrow;
    }
  }
  
  /// Stop recording
  Future<void> stopRecording() async {
    try {
      await _recordingSubscription?.cancel();
      await _recorder.stop();
      _isRecording = false;
      _audioLevelController.add(0.0);
      AppLogger.info('Stopped recording');
    } catch (e) {
      AppLogger.error('Failed to stop recording', e);
    }
  }
  
  /// Play audio chunk from base64 encoded PCM data
  Future<void> playAudioChunk(String base64Audio) async {
    try {
      final audioBytes = base64Decode(base64Audio);
      
      // Add to queue for smooth playback
      _audioQueue.add(audioBytes);
      
      // Start playback if not already playing
      if (!_isPlaying) {
        _startPlaybackQueue();
      }
    } catch (e) {
      AppLogger.error('Failed to queue audio chunk', e);
    }
  }
  
  /// Start processing the playback queue
  void _startPlaybackQueue() {
    if (_isPlaying) return;
    
    _isPlaying = true;
    
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 50), (_) async {
      if (_audioQueue.isEmpty) {
        _stopPlaybackQueue();
        return;
      }
      
      // Combine multiple chunks for smoother playback
      final List<int> combinedData = [];
      int chunksToPlay = _audioQueue.length.clamp(1, 3);
      
      for (int i = 0; i < chunksToPlay; i++) {
        if (_audioQueue.isNotEmpty) {
          combinedData.addAll(_audioQueue.removeAt(0));
        }
      }
      
      if (combinedData.isNotEmpty) {
        await _playPCMAudio(Uint8List.fromList(combinedData));
      }
    });
  }
  
  /// Stop playback queue
  void _stopPlaybackQueue() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _isPlaying = false;
  }
  
  /// Play PCM audio data
  Future<void> _playPCMAudio(Uint8List pcmData) async {
    File? tempFile;
    
    try {
      // Convert PCM to WAV
      final wavData = _pcmToWav(pcmData);
      
      // Create temp file
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      tempFile = File('${tempDir.path}/realtime_audio_$timestamp.wav');
      
      // Write WAV data
      await tempFile.writeAsBytes(wavData);
      
      // Get next player from pool
      final player = _playerPool[_currentPlayerIndex];
      _currentPlayerIndex = (_currentPlayerIndex + 1) % _playerPool.length;
      
      // Set file and play
      await player.setFilePath(tempFile.path);
      await player.play();
      
      // Schedule file deletion after playback
      Timer(const Duration(seconds: 2), () {
        if (tempFile != null && tempFile.existsSync()) {
          try {
            tempFile.deleteSync();
          } catch (e) {
            // Ignore deletion errors
          }
        }
      });
      
    } catch (e) {
      AppLogger.error('Failed to play PCM audio', e);
      // Clean up on error
      if (tempFile != null && tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (e) {
          // Ignore
        }
      }
    }
  }
  
  /// Convert PCM16 data to WAV format
  /// OpenAI Realtime API uses 24kHz, mono, 16-bit PCM
  Uint8List _pcmToWav(Uint8List pcmData) {
    const sampleRate = 24000;  // Realtime API specification
    const channels = 1;         // Mono
    const bitsPerSample = 16;   // 16-bit PCM
    
    final dataSize = pcmData.length;
    final fileSize = dataSize + 36;  // File size minus RIFF header
    
    final header = ByteData(44);
    
    // RIFF chunk
    header.setUint32(0, 0x46464952, Endian.big);    // "RIFF"
    header.setUint32(4, fileSize, Endian.little);
    header.setUint32(8, 0x45564157, Endian.big);    // "WAVE"
    
    // fmt chunk
    header.setUint32(12, 0x20746d66, Endian.big);   // "fmt "
    header.setUint32(16, 16, Endian.little);        // fmt chunk size
    header.setUint16(20, 1, Endian.little);         // PCM format
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * channels * bitsPerSample ~/ 8, Endian.little);
    header.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    
    // data chunk
    header.setUint32(36, 0x61746164, Endian.big);   // "data"
    header.setUint32(40, dataSize, Endian.little);
    
    // Combine header and PCM data
    return Uint8List.fromList([
      ...header.buffer.asUint8List(),
      ...pcmData,
    ]);
  }
  
  /// Calculate audio level for visualization
  void _calculateAudioLevel(Uint8List chunk) {
    if (chunk.isEmpty) return;
    
    double sum = 0;
    int samples = 0;
    
    // Process PCM16 samples
    for (int i = 0; i < chunk.length - 1; i += 2) {
      // Convert bytes to 16-bit signed integer
      int sample = chunk[i] | (chunk[i + 1] << 8);
      if (sample > 32767) sample = sample - 65536;  // Convert to signed
      
      sum += sample.abs();
      samples++;
    }
    
    // Calculate average and normalize to 0-1
    if (samples > 0) {
      double average = sum / samples;
      double level = (average / 32768.0).clamp(0.0, 1.0);
      _audioLevelController.add(level);
    }
  }
  
  /// Check if currently recording
  bool get isRecording => _isRecording;
  
  /// Check if currently playing
  bool get isPlaying => _isPlaying;
  
  /// Clear audio queue
  void clearQueue() {
    _audioQueue.clear();
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    // Stop recording
    await stopRecording();
    
    // Stop playback
    _stopPlaybackQueue();
    _audioQueue.clear();
    
    // Dispose all players
    await _audioPlayer.dispose();
    for (final player in _playerPool) {
      await player.dispose();
    }
    
    // Close stream controllers
    await _audioLevelController.close();
    await _audioDataController.close();
    
    // Dispose recorder
    await _recorder.dispose();
  }
}
// 임시 모의 클래스 (나중에 flutter_sound로 교체)
class _MockAudioPlayer {
  void dispose() {}
  Future<void> play() async {}
  Future<void> stop() async {}
  Future<void> setVolume(double volume) async {}
  Stream<dynamic> get playerStateStream => Stream.value(null);
  bool get isPlaying => false;
}
