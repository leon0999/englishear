import 'dart:typed_data';
import '../utils/audio_utils.dart';
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
    
    // Set up callback for response completion
    _websocket.onResponseCompleted = () {
      AppLogger.info('🎯 Response completed - allowing AI audio playback');
      _aiIsResponding = false;
      _updateConversationState();
    };
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
      
      // FlutterSound 플레이어 초기화 - WAV 파일 재생용
      _soundPlayer = FlutterSoundPlayer();
      await _soundPlayer!.openPlayer();
      await _soundPlayer!.setVolume(1.0);
      
      _isInitialized = true;
      
      AppLogger.info('✅ Audio streaming ready (WAV mode)');
      
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
      await _soundPlayer!.setVolume(1.0);
      
      _isInitialized = true;
      AppLogger.info('✅ Audio streaming ready (retry - WAV mode)');
    } catch (e) {
      AppLogger.error('❌ Retry failed', e);
    }
  }
  
  /// Setup all event listeners
  void _setupListeners() {
    // Listen for audio data from AI
    _audioDataSubscription = _websocket.audioDataStream.listen((audioData) {
      // 빈 데이터는 인터럽션 신호로 처리
      if (audioData.isEmpty) {
        AppLogger.info('🛑 Received interrupt signal - stopping AI audio');
        _soundPlayer?.stopPlayer();
        return;
      }
      
      // AI 오디오 재생 조건을 더 유연하게 변경
      if (audioData.isNotEmpty) {
        AppLogger.info('📻 Received AI audio: ${audioData.length} bytes, Speaking: $_isSpeaking, AI Responding: $_aiIsResponding');
        
        // AI가 응답 중이고 사용자가 말하고 있지 않으면 재생
        if (!_isSpeaking) {
          addAudioData(audioData);
        } else {
          AppLogger.info('⏸️ Skipping AI audio - user is speaking');
        }
      }
    });
  }
  
  /// Add audio data to play
  Future<void> addAudioData(Uint8List pcmData) async {
    if (!_isInitialized || pcmData.isEmpty) return;
    
    AppLogger.info('🔊 Playing Jupiter voice: ${pcmData.length} bytes');
    
    try {
      // WAV 파일 방식으로 재생
      await _playPCMAsWAV(pcmData);
    } catch (e) {
      AppLogger.error('❌ Error playing audio', e);
      // 재시도 로직 추가
      await _retryAudioPlayback(pcmData);
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
      _aiIsResponding = true; // Set AI as responding
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
      _isSpeaking = false; // Ensure speaking state is false
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
  
  /// Retry audio playback with fallback
  Future<void> _retryAudioPlayback(Uint8List pcmData) async {
    AppLogger.info('🔄 Retrying audio playback...');
    
    try {
      // 짧은 지연 후 재시도
      await Future.delayed(const Duration(milliseconds: 100));
      
      // 플레이어 상태 체크 및 재초기화
      if (_soundPlayer == null || !_isInitialized) {
        await _retryInitialize();
      }
      
      // 재시도
      await _playPCMAsWAV(pcmData);
      AppLogger.info('✅ Audio retry successful');
    } catch (e) {
      AppLogger.error('❌ Audio retry failed', e);
    }
  }

  /// Play PCM data as WAV file
  Future<void> _playPCMAsWAV(Uint8List pcmData) async {
    try {
      AppLogger.info('🎵 Starting WAV playback process...');
      
      // 플레이어 상태 확인
      if (_soundPlayer == null) {
        throw Exception('SoundPlayer is null');
      }
      if (!_isInitialized) {
        throw Exception('Audio service not initialized');
      }
      
      // 임시 파일로 저장 후 재생
      final tempDir = await getTemporaryDirectory();
      if (!await tempDir.exists()) {
        throw Exception('Temp directory does not exist');
      }
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/jupiter_$timestamp.wav');
      
      AppLogger.info('📁 Creating temp file: ${tempFile.path}');
      
      // PCM을 WAV로 변환 (audio_utils 사용)
      final wavData = AudioUtils.pcmToWav(pcmData);
      await tempFile.writeAsBytes(wavData);
      
      // 파일 생성 확인
      if (!await tempFile.exists()) {
        throw Exception('Failed to create WAV file');
      }
      
      AppLogger.info('🎵 WAV file created: ${tempFile.path} (${wavData.length} bytes)');
      
      // 이전 재생 중지
      try {
        await _soundPlayer!.stopPlayer();
        AppLogger.info('⏹️ Previous playback stopped');
      } catch (e) {
        AppLogger.warning('Could not stop previous playback: $e');
      }
      
      // 새 파일 재생 시작
      AppLogger.info('▶️ Starting playback...');
      await _soundPlayer!.startPlayer(
        fromURI: tempFile.path,
        whenFinished: () async {
          AppLogger.info('🏁 Playback finished');
          // 재생 완료 후 파일 정리
          try {
            if (await tempFile.exists()) {
              await tempFile.delete();
              AppLogger.info('🗑️ Temp WAV file cleaned up');
            }
          } catch (e) {
            AppLogger.error('Error deleting temp file', e);
          }
        },
      );
      
      AppLogger.info('✅ Jupiter voice playback started successfully');
      
    } catch (e) {
      AppLogger.error('❌ Failed to play PCM as WAV: ${e.toString()}', e);
      
      // 상세 디버그 정보
      AppLogger.error('Debug info - PCM size: ${pcmData.length}, Initialized: $_isInitialized, Player: ${_soundPlayer != null}');
      
      rethrow; // 재시도 로직에서 처리하도록 예외 재전파
    }
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