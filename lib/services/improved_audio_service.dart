import 'dart:typed_data';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:audio_session/audio_session.dart' as audio_session;
import 'package:path_provider/path_provider.dart';
import '../core/logger.dart';
import 'dart:io';

/// Improved Audio Service with crossfade and zero-gap playback
/// Inspired by Moshi's continuous streaming approach
class ImprovedAudioService {
  final AudioRecorder _recorder = AudioRecorder();
  late final AudioPlayer _primaryPlayer;
  late final AudioPlayer _secondaryPlayer;
  
  // Double buffering for seamless playback
  bool _usePrimaryPlayer = true;
  
  // Advanced audio queue with overlap handling
  final Queue<AudioChunk> _audioQueue = Queue();
  bool _isProcessing = false;
  Timer? _processTimer;
  
  // Crossfade parameters
  static const int crossfadeSamples = 480; // 20ms at 24kHz
  static const int sampleRate = 24000;
  static const int bytesPerSample = 2;
  
  // Stream controllers
  final _audioLevelController = StreamController<double>.broadcast();
  final _playbackStateController = StreamController<PlaybackState>.broadcast();
  
  Stream<double> get audioLevelStream => _audioLevelController.stream;
  Stream<PlaybackState> get playbackStateStream => _playbackStateController.stream;
  
  // Recording state
  bool _isRecording = false;
  StreamSubscription? _recordingSubscription;
  
  // Playback state
  bool _isPlaying = false;
  int _currentChunkId = 0;
  
  ImprovedAudioService() {
    _initializePlayers();
  }
  
  void _initializePlayers() {
    _primaryPlayer = AudioPlayer();
    _secondaryPlayer = AudioPlayer();
    
    // Configure both players
    for (final player in [_primaryPlayer, _secondaryPlayer]) {
      player.setReleaseMode(ReleaseMode.stop);
      player.setVolume(1.0);
      // Slightly slower playback for better comprehension
      player.setPlaybackRate(0.95);
    }
    
    AppLogger.info('🎵 Audio players initialized with double buffering');
  }
  
  /// Initialize audio session for optimal performance
  Future<void> initialize() async {
    AppLogger.test('==================== IMPROVED AUDIO INIT START ====================');
    
    try {
      // Configure audio session for low latency
      final session = await audio_session.AudioSession.instance;
      await session.configure(const audio_session.AudioSessionConfiguration(
        avAudioSessionCategory: audio_session.AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: audio_session.AVAudioSessionCategoryOptions.allowBluetooth |
                                       audio_session.AVAudioSessionCategoryOptions.defaultToSpeaker |
                                       audio_session.AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: audio_session.AVAudioSessionMode.voiceChat, // Optimized for voice
        avAudioSessionRouteSharingPolicy: audio_session.AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: audio_session.AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: audio_session.AndroidAudioAttributes(
          contentType: audio_session.AndroidAudioContentType.speech,
          flags: audio_session.AndroidAudioFlags.none,
          usage: audio_session.AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: audio_session.AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ));
      
      await session.setActive(true);
      AppLogger.success('✅ Audio session configured for low-latency voice');
      
      // Start queue processor with faster interval
      _processTimer?.cancel();
      _processTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (!_isProcessing && _audioQueue.isNotEmpty) {
          _processNextChunk();
        }
      });
      
      AppLogger.test('==================== IMPROVED AUDIO INIT COMPLETE ====================');
    } catch (e) {
      AppLogger.error('Failed to initialize audio session', e);
    }
  }
  
  /// Add audio chunk with crossfade preparation
  void addAudioChunk(Uint8List pcmData, {String? chunkId}) {
    final chunk = AudioChunk(
      id: chunkId ?? 'chunk_${_currentChunkId++}',
      data: pcmData,
      timestamp: DateTime.now(),
    );
    
    _audioQueue.add(chunk);
    AppLogger.debug('📦 Added audio chunk ${chunk.id} (${pcmData.length} bytes)');
    
    // Process immediately if not already processing
    if (!_isProcessing && !_isPlaying) {
      _processNextChunk();
    }
  }
  
  /// Process next chunk with crossfade
  Future<void> _processNextChunk() async {
    if (_audioQueue.isEmpty || _isProcessing) return;
    
    _isProcessing = true;
    final chunk = _audioQueue.removeFirst();
    
    try {
      // Apply crossfade if there was a previous chunk
      Uint8List processedData = chunk.data;
      if (_audioQueue.isNotEmpty) {
        processedData = _applyCrossfade(chunk.data, _audioQueue.first.data);
      }
      
      // Convert to WAV with proper headers
      final wavData = _createWavFromPcm(processedData);
      
      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/audio_${chunk.id}.wav');
      await tempFile.writeAsBytes(wavData);
      
      // Select player (double buffering)
      final player = _usePrimaryPlayer ? _primaryPlayer : _secondaryPlayer;
      _usePrimaryPlayer = !_usePrimaryPlayer;
      
      // Play with minimal gap
      _isPlaying = true;
      _playbackStateController.add(PlaybackState.playing);
      
      await player.play(DeviceFileSource(tempFile.path));
      
      // Clean up
      await tempFile.delete();
      
      AppLogger.success('✅ Played chunk ${chunk.id} with crossfade');
    } catch (e) {
      AppLogger.error('Failed to play chunk ${chunk.id}', e);
    } finally {
      _isProcessing = false;
      _isPlaying = false;
      
      // Check if more chunks to process
      if (_audioQueue.isNotEmpty) {
        // Process next chunk immediately for gapless playback
        Timer.run(() => _processNextChunk());
      } else {
        _playbackStateController.add(PlaybackState.idle);
      }
    }
  }
  
  /// Apply crossfade between chunks
  Uint8List _applyCrossfade(Uint8List current, Uint8List next) {
    final fadeLength = math.min(crossfadeSamples * bytesPerSample, current.length ~/ 4);
    final result = Uint8List.fromList(current);
    
    // Apply fade out to end of current chunk
    for (int i = 0; i < fadeLength; i += bytesPerSample) {
      final index = current.length - fadeLength + i;
      if (index < 0 || index + 1 >= result.length) continue;
      
      final sample = (result[index] | (result[index + 1] << 8));
      final fadeFactor = 1.0 - (i / fadeLength);
      final fadedSample = (sample * fadeFactor).round();
      
      result[index] = fadedSample & 0xFF;
      result[index + 1] = (fadedSample >> 8) & 0xFF;
    }
    
    AppLogger.debug('🎵 Applied crossfade (${fadeLength} bytes)');
    return result;
  }
  
  /// Create WAV header for PCM data
  Uint8List _createWavFromPcm(Uint8List pcmData) {
    final wavHeader = BytesBuilder();
    final dataSize = pcmData.length;
    final fileSize = dataSize + 36;
    
    // RIFF header
    wavHeader.add(utf8.encode('RIFF'));
    wavHeader.add(_int32ToBytes(fileSize));
    wavHeader.add(utf8.encode('WAVE'));
    
    // fmt chunk
    wavHeader.add(utf8.encode('fmt '));
    wavHeader.add(_int32ToBytes(16)); // fmt chunk size
    wavHeader.add(_int16ToBytes(1)); // PCM format
    wavHeader.add(_int16ToBytes(1)); // Mono
    wavHeader.add(_int32ToBytes(sampleRate));
    wavHeader.add(_int32ToBytes(sampleRate * bytesPerSample)); // Byte rate
    wavHeader.add(_int16ToBytes(bytesPerSample)); // Block align
    wavHeader.add(_int16ToBytes(16)); // Bits per sample
    
    // data chunk
    wavHeader.add(utf8.encode('data'));
    wavHeader.add(_int32ToBytes(dataSize));
    wavHeader.add(pcmData);
    
    return wavHeader.toBytes();
  }
  
  /// Start recording with real-time streaming
  Future<void> startRecording(Function(Uint8List) onData) async {
    if (_isRecording) return;
    
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      AppLogger.error('Microphone permission denied');
      return;
    }
    
    try {
      // Configure for low-latency recording
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: sampleRate,
        numChannels: 1,
        autoGain: true,
        echoCancel: true,
        noiseSuppress: true,
      );
      
      final stream = await _recorder.startStream(config);
      _isRecording = true;
      
      _recordingSubscription = stream.listen(
        (data) {
          onData(data);
          _calculateAudioLevel(data);
        },
        onError: (error) {
          AppLogger.error('Recording error', error);
          stopRecording();
        },
      );
      
      AppLogger.success('🎤 Recording started with low-latency config');
    } catch (e) {
      AppLogger.error('Failed to start recording', e);
    }
  }
  
  /// Stop recording
  Future<void> stopRecording() async {
    if (!_isRecording) return;
    
    await _recordingSubscription?.cancel();
    await _recorder.stop();
    _isRecording = false;
    
    AppLogger.info('🛑 Recording stopped');
  }
  
  /// Calculate and emit audio level
  void _calculateAudioLevel(Uint8List data) {
    if (data.isEmpty) return;
    
    double sum = 0;
    for (int i = 0; i < data.length; i += 2) {
      if (i + 1 < data.length) {
        final sample = (data[i] | (data[i + 1] << 8)).toSigned(16);
        sum += sample.abs();
      }
    }
    
    final level = (sum / (data.length / 2)) / 32768.0;
    _audioLevelController.add(math.min(1.0, level * 2));
  }
  
  /// Clear audio queue
  void clearQueue() {
    _audioQueue.clear();
    AppLogger.info('🗑️ Audio queue cleared');
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    _processTimer?.cancel();
    await stopRecording();
    await _primaryPlayer.dispose();
    await _secondaryPlayer.dispose();
    await _audioLevelController.close();
    await _playbackStateController.close();
    
    AppLogger.info('🔚 Audio service disposed');
  }
  
  // Helper methods for byte conversion
  Uint8List _int32ToBytes(int value) {
    return Uint8List.fromList([
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ]);
  }
  
  Uint8List _int16ToBytes(int value) {
    return Uint8List.fromList([
      value & 0xFF,
      (value >> 8) & 0xFF,
    ]);
  }
}

/// Audio chunk with metadata
class AudioChunk {
  final String id;
  final Uint8List data;
  final DateTime timestamp;
  
  AudioChunk({
    required this.id,
    required this.data,
    required this.timestamp,
  });
}

/// Playback state
enum PlaybackState {
  idle,
  playing,
  paused,
  stopped,
}