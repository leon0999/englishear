import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
// import 'package:audioplayers/audioplayers.dart';  // Removed - using just_audio instead
import 'package:just_audio/just_audio.dart';
import 'openai_realtime_websocket.dart';
import '../core/logger.dart';

/// Audio Streaming Service for Realtime API
/// Handles audio recording, streaming, and playback
class AudioStreamingService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final OpenAIRealtimeWebSocket _websocket;
  
  StreamSubscription? _audioStreamSubscription;
  StreamSubscription? _audioDataSubscription;
  
  bool _isRecording = false;
  bool _isPlaying = false;
  
  // Audio buffer for playback
  final List<int> _audioBuffer = [];
  Timer? _playbackTimer;
  
  // Stream controllers
  final _audioLevelController = StreamController<double>.broadcast();
  Stream<double> get audioLevelStream => _audioLevelController.stream;
  
  AudioStreamingService(this._websocket) {
    _setupAudioDataListener();
  }
  
  /// Setup listener for incoming audio data
  void _setupAudioDataListener() {
    _audioDataSubscription = _websocket.audioDataStream.listen((audioData) {
      _handleIncomingAudio(audioData);
    });
  }
  
  /// Start streaming audio to Realtime API
  Future<void> startStreaming() async {
    try {
      if (_isRecording) {
        AppLogger.warning('Already recording');
        return;
      }
      
      // Check microphone permission
      if (!await _recorder.hasPermission()) {
        throw Exception('Microphone permission denied');
      }
      
      AppLogger.info('Starting audio streaming to Realtime API');
      
      // Clear any previous audio buffer
      _websocket.clearAudioBuffer();
      
      // Start recording with PCM16 format at 24kHz (Realtime API requirement)
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 24000,  // Realtime API requires 24kHz
          numChannels: 1,     // Mono audio
          bitRate: 128000,
        ),
      );
      
      _isRecording = true;
      
      // Stream audio chunks to WebSocket
      _audioStreamSubscription = stream.listen(
        (chunk) {
          // Send audio chunk to Realtime API
          _websocket.sendAudio(Uint8List.fromList(chunk));
          
          // Calculate audio level for visualization
          _calculateAudioLevel(Uint8List.fromList(chunk));
        },
        onError: (error) {
          AppLogger.error('Audio stream error', error);
          stopStreaming();
        },
      );
      
      AppLogger.info('Audio streaming started');
      
    } catch (e) {
      AppLogger.error('Failed to start audio streaming', e);
      _isRecording = false;
      rethrow;
    }
  }
  
  /// Stop streaming and trigger response
  Future<void> stopStreaming() async {
    try {
      if (!_isRecording) return;
      
      AppLogger.info('Stopping audio streaming');
      
      // Cancel audio stream subscription
      await _audioStreamSubscription?.cancel();
      _audioStreamSubscription = null;
      
      // Stop recording
      await _recorder.stop();
      _isRecording = false;
      
      // Reset audio level
      _audioLevelController.add(0.0);
      
      // Commit audio and request response from Realtime API
      _websocket.commitAudioAndRespond();
      
      AppLogger.info('Audio streaming stopped, response requested');
      
    } catch (e) {
      AppLogger.error('Failed to stop audio streaming', e);
    }
  }
  
  /// Handle incoming audio from Realtime API
  void _handleIncomingAudio(Uint8List audioData) {
    if (audioData.isEmpty) return;
    
    // Add to buffer
    _audioBuffer.addAll(audioData);
    
    // Start playback if not already playing
    if (!_isPlaying && _audioBuffer.length > 1024) {  // Buffer threshold
      _startPlayback();
    }
  }
  
  /// Start audio playback
  void _startPlayback() {
    if (_isPlaying) return;
    
    _isPlaying = true;
    AppLogger.info('Starting audio playback');
    
    // Create periodic timer to play audio chunks
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_audioBuffer.isEmpty) {
        // No more audio to play
        _stopPlayback();
        return;
      }
      
      // Extract chunk to play (2400 samples = 100ms at 24kHz)
      final chunkSize = 4800;  // 2400 samples * 2 bytes per sample
      final chunk = _audioBuffer.take(chunkSize).toList();
      _audioBuffer.removeRange(0, chunk.length);
      
      // Play audio chunk
      _playAudioChunk(Uint8List.fromList(chunk));
    });
  }
  
  /// Stop audio playback
  void _stopPlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _isPlaying = false;
    _audioBuffer.clear();
    AppLogger.info('Audio playback stopped');
  }
  
  /// Play a single audio chunk
  Future<void> _playAudioChunk(Uint8List chunk) async {
    try {
      // For web, we need to convert PCM to a playable format
      // This is a simplified version - in production, use Web Audio API
      await _audioPlayer.play(
        BytesSource(chunk),
        mode: PlayerMode.lowLatency,
      );
    } catch (e) {
      AppLogger.error('Failed to play audio chunk', e);
    }
  }
  
  /// Calculate audio level for visualization
  void _calculateAudioLevel(Uint8List chunk) {
    if (chunk.isEmpty) return;
    
    double sum = 0;
    for (int i = 0; i < chunk.length; i += 2) {
      // Convert PCM16 bytes to sample value
      int sample = chunk[i] | (chunk[i + 1] << 8);
      if (sample > 32767) sample = sample - 65536;
      sum += sample.abs();
    }
    
    // Calculate average and normalize to 0-1
    double average = sum / (chunk.length / 2);
    double level = (average / 32768).clamp(0.0, 1.0);
    
    _audioLevelController.add(level);
  }
  
  /// Toggle recording (press to talk)
  Future<void> toggleRecording() async {
    if (_isRecording) {
      await stopStreaming();
    } else {
      await startStreaming();
    }
  }
  
  /// Check if currently recording
  bool get isRecording => _isRecording;
  
  /// Check if currently playing
  bool get isPlaying => _isPlaying;
  
  /// Dispose resources
  Future<void> dispose() async {
    await stopStreaming();
    _stopPlayback();
    
    await _audioStreamSubscription?.cancel();
    await _audioDataSubscription?.cancel();
    
    await _recorder.dispose();
    await _audioPlayer.dispose();
    
    await _audioLevelController.close();
  }
}