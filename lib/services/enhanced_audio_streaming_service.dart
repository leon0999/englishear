import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:record/record.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';
import 'openai_realtime_websocket.dart';
import '../core/logger.dart';

/// Enhanced Audio Streaming Service for Realtime API with Direct PCM Streaming
class EnhancedAudioStreamingService {
  final AudioRecorder _recorder = AudioRecorder();
  FlutterSoundPlayer? _soundPlayer;
  final OpenAIRealtimeWebSocket _websocket;
  
  StreamSubscription? _audioStreamSubscription;
  StreamSubscription? _audioDataSubscription;
  
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isSpeaking = false;
  bool _aiIsResponding = false;
  bool _isInitialized = false;
  
  // Conversation history for Upgrade Replay
  final List<ConversationSegment> conversationHistory = [];
  
  // Stream controllers
  final _audioLevelController = StreamController<double>.broadcast();
  final _conversationStateController = StreamController<ConversationState>.broadcast();
  
  Stream<double> get audioLevelStream => _audioLevelController.stream;
  Stream<ConversationState> get conversationStateStream => _conversationStateController.stream;
  
  EnhancedAudioStreamingService(this._websocket) {
    _setupListeners();
  }
  
  /// Initialize service with PCM streaming support
  Future<void> initialize() async {
    AppLogger.info('🎵 Initializing audio service...');
    
    try {
      // 먼저 오디오 세션 설정
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration.speech());
      await session.setActive(true);
      
      // Request microphone permission
      if (!await _recorder.hasPermission()) {
        AppLogger.warning('Microphone permission not granted');
        return;
      }
      
      // FlutterSound 플레이어 초기화
      _soundPlayer = FlutterSoundPlayer();
      await _soundPlayer!.openPlayer();
      
      // StreamController 제거 - 직접 foodSink 사용으로 변경
      
      // 플레이어 시작
      await _soundPlayer!.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: 24000,
        bufferSize: 8192,
        interleaved: false,
      );
      
      await _soundPlayer!.setVolume(1.0);
      _isInitialized = true;
      
      AppLogger.info('✅ Audio streaming ready');
      
      // Auto-start continuous listening after initialization
      await Future.delayed(const Duration(seconds: 1));
      await startContinuousListening();
      
    } catch (e) {
      AppLogger.error('❌ Audio init error', e);
      // 에러 발생 시 재시도
      await _retryInitialize();
    }
  }
  
  Future<void> _retryInitialize() async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      
      _soundPlayer = FlutterSoundPlayer();
      await _soundPlayer!.openPlayer();
      
      // 다른 방식으로 시도 - 모든 필수 매개변수 포함
      await _soundPlayer!.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: 24000,
        bufferSize: 16384,       // 버퍼 크기 증가
        interleaved: false,      // 필수
      );
      
      _isInitialized = true;
      AppLogger.info('✅ Audio streaming ready (retry)');
    } catch (e) {
      AppLogger.error('❌ Retry failed', e);
    }
  }
  
  /// Setup all event listeners
  void _setupListeners() {
    // Listen for audio data from AI
    _audioDataSubscription = _websocket.audioDataStream.listen((audioData) {
      // Only play AI audio if user is not speaking
      if (!_isSpeaking && audioData.isNotEmpty) {
        addAudioData(audioData);
      }
    });
  }
  
  /// Add audio data to play
  void addAudioData(Uint8List pcmData) {
    if (!_isInitialized || pcmData.isEmpty) return;
    
    AppLogger.info('🔊 Playing Jupiter voice: ${pcmData.length} bytes');
    
    try {
      // Alternative 접근법 - 직접 파일 재생 방식
      _playPCMDirectly(pcmData);
    } catch (e) {
      AppLogger.error('❌ Error playing audio', e);
    }
    
    // Save AI audio for conversation history
    conversationHistory.add(ConversationSegment(
      role: 'assistant',
      audioData: pcmData,
      timestamp: DateTime.now(),
    ));
  }
  
  /// Start continuous listening mode (auto-start)
  Future<void> startContinuousListening() async {
    if (_isRecording) {
      AppLogger.info('Already in continuous listening mode');
      return;
    }
    
    AppLogger.info('Starting continuous listening mode');
    await startStreaming();
  }
  
  /// Start streaming audio to Realtime API
  Future<void> startStreaming() async {
    try {
      if (_isRecording) {
        AppLogger.warning('Already recording');
        return;
      }
      
      // Stop any AI audio playback when user starts speaking
      stopListening();
      _aiIsResponding = false;
      
      // Check microphone permission
      if (!await _recorder.hasPermission()) {
        throw Exception('Microphone permission denied');
      }
      
      AppLogger.info('User started speaking - stopping AI response');
      _isSpeaking = true;
      _updateConversationState();
      
      // Clear any previous audio buffer
      _websocket.clearAudioBuffer();
      
      // Start recording with PCM16 format at 24kHz
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 24000,
          numChannels: 1,
          bitRate: 128000,
        ),
      );
      
      _isRecording = true;
      final audioChunks = <int>[];
      
      // Stream audio chunks to WebSocket
      _audioStreamSubscription = stream.listen(
        (chunk) {
          // Send audio chunk to Realtime API
          _websocket.sendAudio(Uint8List.fromList(chunk));
          
          // Save for conversation history
          audioChunks.addAll(chunk);
          
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
      
      AppLogger.info('User stopped speaking');
      _isSpeaking = false;
      _updateConversationState();
      
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
      _aiIsResponding = true;
      resumeListening();
      _updateConversationState();
      
      AppLogger.info('Audio streaming stopped, AI response requested');
      
    } catch (e) {
      AppLogger.error('Failed to stop audio streaming', e);
    }
  }
  
  /// Stop listening (pause AI audio)
  void stopListening() {
    // 마이크 일시정지 - AI 오디오 재생 중단
    _isPlaying = false;
  }
  
  /// Resume listening (resume AI audio)
  void resumeListening() {
    // 마이크 재개 - AI 오디오 재생 재개
    _isPlaying = true;
  }
  
  /// Play PCM data directly using file-based approach
  Future<void> _playPCMDirectly(Uint8List pcmData) async {
    try {
      // 임시 파일로 저장 후 재생
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/jupiter_${DateTime.now().millisecondsSinceEpoch}.wav');
      
      // PCM을 WAV로 변환
      final wavData = _pcmToWav(pcmData);
      await tempFile.writeAsBytes(wavData);
      
      AppLogger.info('🎵 Created temp WAV file: ${tempFile.path}');
      
      // 새 플레이어 인스턴스로 재생
      final player = FlutterSoundPlayer();
      await player.openPlayer();
      
      // 재생 시작
      await player.startPlayer(fromURI: tempFile.path);
      AppLogger.info('✅ Jupiter voice playback started');
      
      // 재생 완료 후 정리 - 3초 후 자동 정리
      Timer(const Duration(seconds: 3), () async {
        try {
          await player.stopPlayer();
          await player.closePlayer();
          if (tempFile.existsSync()) {
            tempFile.deleteSync();
            AppLogger.info('🗑️ Temp file cleaned up');
          }
        } catch (e) {
          AppLogger.error('Error cleaning up player', e);
        }
      });
      
    } catch (e) {
      AppLogger.error('❌ Failed to play PCM directly', e);
    }
  }

  /// Convert PCM to WAV format for direct playback
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

  /// Clear audio queue
  void clearQueue() {
    // Alternative 방식에서는 개별 플레이어들이므로 특별한 클리어 불필요
    AppLogger.info('Queue cleared (alternative file-based approach)');
  }
  
  /// Calculate audio level for visualization
  void _calculateAudioLevel(Uint8List chunk) {
    if (chunk.isEmpty) return;
    
    double sum = 0;
    for (int i = 0; i < chunk.length; i += 2) {
      int sample = chunk[i] | (chunk[i + 1] << 8);
      if (sample > 32767) sample = sample - 65536;
      sum += sample.abs();
    }
    
    double average = sum / (chunk.length / 2);
    double level = (average / 32768).clamp(0.0, 1.0);
    
    _audioLevelController.add(level);
  }
  
  /// Update conversation state
  void _updateConversationState() {
    _conversationStateController.add(ConversationState(
      isUserSpeaking: _isSpeaking,
      isAiResponding: _aiIsResponding,
      isRecording: _isRecording,
      isPlaying: _isPlaying,
    ));
  }
  
  /// Toggle recording (press to talk)
  Future<void> toggleRecording() async {
    if (_isRecording) {
      await stopStreaming();
    } else {
      await startStreaming();
    }
  }
  
  /// Get conversation history for Upgrade Replay
  List<ConversationSegment> getConversationHistory() {
    return List.unmodifiable(conversationHistory);
  }
  
  /// Clear conversation history
  void clearConversationHistory() {
    conversationHistory.clear();
  }
  
  /// Check if currently recording
  bool get isRecording => _isRecording;
  
  /// Check if currently playing
  bool get isPlaying => _isPlaying;
  
  /// Check if user is speaking
  bool get isSpeaking => _isSpeaking;
  
  /// Dispose resources
  Future<void> dispose() async {
    await stopStreaming();
    
    await _audioStreamSubscription?.cancel();
    await _audioDataSubscription?.cancel();
    
    await _recorder.dispose();
    
    // StreamController 제거됨 - 더 이상 정리할 필요 없음
    await _soundPlayer?.stopPlayer();
    await _soundPlayer?.closePlayer();
    
    await _audioLevelController.close();
    await _conversationStateController.close();
  }
}

/// Conversation segment for history tracking
class ConversationSegment {
  final String role;
  final Uint8List audioData;
  final DateTime timestamp;
  final String? text;
  
  ConversationSegment({
    required this.role,
    required this.audioData,
    required this.timestamp,
    this.text,
  });
}

/// Conversation state
class ConversationState {
  final bool isUserSpeaking;
  final bool isAiResponding;
  final bool isRecording;
  final bool isPlaying;
  
  ConversationState({
    required this.isUserSpeaking,
    required this.isAiResponding,
    required this.isRecording,
    required this.isPlaying,
  });
}