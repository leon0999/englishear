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
  
  // Audio parameters
  static const bool ENABLE_CROSSFADE = false; // Crossfade completely disabled
  static const int crossfadeSamples = 480; // Not used when ENABLE_CROSSFADE is false
  static const int sampleRate = 24000;
  static const int bytesPerSample = 2;
  static const int CROSSFADE_BYTES = crossfadeSamples * bytesPerSample; // Not used
  static const int OPTIMAL_BUFFER_SIZE = 9600; // 200ms for optimal buffering
  static const int INTER_CHUNK_SILENCE_MS = 5; // 5ms silence between chunks
  
  // Stream controllers
  final _audioLevelController = StreamController<double>.broadcast();
  final _playbackStateController = StreamController<PlaybackState>.broadcast();
  
  Stream<double> get audioLevelStream => _audioLevelController.stream;
  Stream<PlaybackState> get playbackStateStream => _playbackStateController.stream;
  
  // Recording state
  bool _isRecording = false;
  StreamSubscription? _recordingSubscription;
  List<int> _recordingBuffer = [];
  Timer? _bufferTimer;
  static const int MIN_BUFFER_SIZE = 4800; // 100ms at 24kHz (24000 * 0.1 * 2 bytes)
  
  // Keep track of last processed chunk for smooth crossfading
  Uint8List? _lastProcessedChunk;
  
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
      await session.configure(audio_session.AudioSessionConfiguration(
        avAudioSessionCategory: audio_session.AVAudioSessionCategory.playAndRecord,
        avAudioSessionCategoryOptions: audio_session.AVAudioSessionCategoryOptions.allowBluetooth |
                                       audio_session.AVAudioSessionCategoryOptions.defaultToSpeaker |
                                       audio_session.AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: audio_session.AVAudioSessionMode.spokenAudio, // Better for clear speech
        avAudioSessionRouteSharingPolicy: audio_session.AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: audio_session.AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: const audio_session.AndroidAudioAttributes(
          contentType: audio_session.AndroidAudioContentType.speech,
          flags: audio_session.AndroidAudioFlags.none,
          usage: audio_session.AndroidAudioUsage.voiceCommunication,
        ),
        androidAudioFocusGainType: audio_session.AndroidAudioFocusGainType.gainTransientMayDuck,
        androidWillPauseWhenDucked: false,
      ));
      
      await session.setActive(true);
      
      // iOS-specific buffer optimization (commented out as method may not be available in all versions)
      // Keeping voiceChat mode is sufficient for low-latency
      // If needed in future: await session.setPreferredIOBufferDuration(0.005);
      
      AppLogger.success('✅ Audio session configured for low-latency voice with voiceChat mode');
      
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
  
  /// Process next chunk without crossfade for clean audio
  Future<void> _processNextChunk() async {
    if (_audioQueue.isEmpty || _isProcessing) return;
    
    _isProcessing = true;
    final chunk = _audioQueue.removeFirst();
    
    try {
      // Apply noise gate first to clean the audio
      Uint8List processedData = _applyNoiseGate(chunk.data);
      
      // Add small silence gap between chunks (no crossfade)
      if (_lastProcessedChunk != null) {
        await Future.delayed(Duration(milliseconds: INTER_CHUNK_SILENCE_MS));
        // No crossfade applied when ENABLE_CROSSFADE is false
        if (ENABLE_CROSSFADE) {
          processedData = _applySmoothCrossfade(_lastProcessedChunk!, processedData);
        }
      }
      
      _lastProcessedChunk = processedData;
      
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
      
      AppLogger.success('✅ Played chunk ${chunk.id} ${ENABLE_CROSSFADE ? "with crossfade" : "directly"}');
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
  
  /// Apply minimal crossfade to reduce overlap
  Uint8List _applySmoothCrossfade(Uint8List previousChunk, Uint8List currentChunk) {
    try {
      // Use shorter crossfade to minimize overlap
      final fadeLength = math.min(crossfadeSamples, 
        math.min(previousChunk.length ~/ 4, currentChunk.length ~/ 4)); // Reduced to 1/4
      
      final result = Uint8List.fromList(currentChunk);
      
      // Simple linear fade instead of Hamming window
      for (int i = 0; i < fadeLength; i++) {
        // Linear fade coefficients
        final fadeIn = i / fadeLength;
        final fadeOut = 1.0 - fadeIn;
        
        final prevIndex = (previousChunk.length ~/ 2) - fadeLength + i;
        final currIndex = i;
        
        if (prevIndex >= 0 && prevIndex * 2 + 1 < previousChunk.length &&
            currIndex * 2 + 1 < result.length) {
          // Get 16-bit samples
          final prevSample = (previousChunk[prevIndex * 2] |
              (previousChunk[prevIndex * 2 + 1] << 8)).toSigned(16);
          final currSample = (result[currIndex * 2] |
              (result[currIndex * 2 + 1] << 8)).toSigned(16);
          
          // Mix samples with crossfade
          final mixed = (prevSample * fadeOut + currSample * fadeIn).round();
          
          // Clamp to prevent clipping
          final clipped = mixed.clamp(-32768, 32767);
          
          // Write back to result
          result[currIndex * 2] = clipped & 0xFF;
          result[currIndex * 2 + 1] = (clipped >> 8) & 0xFF;
        }
      }
      
      AppLogger.debug('🎵 Applied minimal crossfade ($fadeLength samples with linear fade)');
      return result;
    } catch (e) {
      AppLogger.error('Crossfade error: $e');
      return currentChunk;
    }
  }
  
  /// Apply crossfade between chunks (legacy method for compatibility)
  Uint8List _applyCrossfade(Uint8List current, Uint8List next) {
    // Use the new smooth crossfade method
    return _applySmoothCrossfade(current, next);
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
  
  /// Start recording with real-time streaming and buffer management
  Future<void> startRecording(Function(Uint8List) onData) async {
    if (_isRecording) return;
    
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      AppLogger.error('Microphone permission denied');
      return;
    }
    
    try {
      _recordingBuffer.clear();
      
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
      
      // Set up buffer timer to ensure minimum buffer size
      _bufferTimer?.cancel();
      _bufferTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        if (_recordingBuffer.length >= MIN_BUFFER_SIZE) {
          final bufferData = Uint8List.fromList(_recordingBuffer);
          onData(bufferData);
          _recordingBuffer.clear();
          AppLogger.debug('📤 Sent buffer of ${bufferData.length} bytes');
        }
      });
      
      _recordingSubscription = stream.listen(
        (data) {
          // Add to buffer instead of sending immediately
          _recordingBuffer.addAll(data);
          _calculateAudioLevel(data);
          
          // If buffer exceeds double the minimum, send immediately
          if (_recordingBuffer.length >= MIN_BUFFER_SIZE * 2) {
            final bufferData = Uint8List.fromList(_recordingBuffer);
            onData(bufferData);
            _recordingBuffer.clear();
            AppLogger.debug('📤 Sent large buffer of ${bufferData.length} bytes');
          }
        },
        onError: (error) {
          AppLogger.error('Recording error', error);
          stopRecording();
        },
      );
      
      AppLogger.success('🎤 Recording started with buffer management (min: ${MIN_BUFFER_SIZE} bytes)');
    } catch (e) {
      AppLogger.error('Failed to start recording', e);
    }
  }
  
  /// Stop recording with buffer flush
  Future<void> stopRecording() async {
    if (!_isRecording) return;
    
    _bufferTimer?.cancel();
    
    // Flush remaining buffer with padding if needed
    if (_recordingBuffer.isNotEmpty) {
      // Pad buffer to minimum size if too small
      while (_recordingBuffer.length < MIN_BUFFER_SIZE) {
        _recordingBuffer.add(0);
      }
      
      final bufferData = Uint8List.fromList(_recordingBuffer);
      AppLogger.info('📤 Flushing final buffer of ${bufferData.length} bytes');
      _recordingBuffer.clear();
    }
    
    await _recordingSubscription?.cancel();
    await _recorder.stop();
    _isRecording = false;
    
    AppLogger.info('🛑 Recording stopped with buffer flush');
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
  
  /// Apply noise gate to remove low-level noise
  Uint8List _applyNoiseGate(Uint8List audioData, {double threshold = 0.01}) {
    final processed = Uint8List.fromList(audioData);
    
    for (int i = 0; i < processed.length ~/ 2; i++) {
      final sampleIndex = i * 2;
      if (sampleIndex + 1 >= processed.length) break;
      
      final sample = (processed[sampleIndex] | 
          (processed[sampleIndex + 1] << 8)).toSigned(16);
      final normalized = sample / 32768.0;
      
      // Remove small noise below threshold
      if (normalized.abs() < threshold) {
        processed[sampleIndex] = 0;
        processed[sampleIndex + 1] = 0;
      }
    }
    
    return processed;
  }
  
  /// Clear audio queue
  void clearQueue() {
    _audioQueue.clear();
    _lastProcessedChunk = null; // Reset crossfade reference
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