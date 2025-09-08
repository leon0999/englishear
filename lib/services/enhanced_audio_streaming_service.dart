import 'dart:typed_data';
import 'dart:convert';
import '../utils/audio_utils.dart';
import 'dart:async';
import 'dart:io';
import 'dart:collection';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:audio_session/audio_session.dart' as audio_session;
import 'package:path_provider/path_provider.dart';
import 'openai_realtime_websocket.dart';
import '../core/logger.dart';

/// Enhanced Audio Streaming Service for Realtime API with Direct PCM Streaming
class EnhancedAudioStreamingService {
  final AudioRecorder _recorder = AudioRecorder();
  late AudioPlayer _audioPlayer;
  
  // Swift와 같은 오디오 큐 시스템
  final Queue<Uint8List> _audioQueue = Queue<Uint8List>();
  bool _isPlayingQueue = false;  // 큐 재생 상태
  Timer? _playbackTimer;
  bool _isProcessingAudio = false;  // 오디오 처리 중 플래그
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
      _isSpeaking = false;  // Reset speaking state when AI completes
      AppLogger.test('Reset speaking state - AI response complete');
      _updateConversationState();
    };
  }
  
  /// Initialize service with PCM streaming support
  Future<void> initialize() async {
    AppLogger.test('==================== AUDIO SERVICE INIT START ====================');
    AppLogger.info('🎵 Initializing audio service...');
    
    // 초기 상태 리셋
    _isSpeaking = false;
    _aiIsResponding = false;
    _isPlaying = false;
    _isRecording = false;
    AppLogger.test('🔄 Initial state reset - _isSpeaking: false');
    
    // AudioPlayer 초기화
    _audioPlayer = AudioPlayer();
    AppLogger.test('✅ AudioPlayer initialized');
    
    try {
      // 오디오 세션 설정 - speech 설정 사용 (더 안정적)
      AppLogger.test('Setting up audio session...');
      final session = await audio_session.AudioSession.instance;
      await session.configure(audio_session.AudioSessionConfiguration.speech());
      await session.setActive(true);
      AppLogger.success('Audio session configured and activated');
      
      // Request microphone permission
      AppLogger.test('Checking microphone permission...');
      final hasPermission = await _recorder.hasPermission();
      AppLogger.audio('Microphone permission status', data: {'hasPermission': hasPermission});
      if (!hasPermission) {
        AppLogger.warning('Microphone permission not granted');
        return;
      }
      AppLogger.success('Microphone permission granted');
      
      // AudioPlayer 초기화 - WAV 파일 재생용
      AppLogger.test('Initializing AudioPlayer...');
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.setPlayerMode(PlayerMode.mediaPlayer);
      
      _isInitialized = true;
      
      AppLogger.success('Audio streaming ready (WAV mode)');
      AppLogger.test('==================== AUDIO SERVICE INIT COMPLETE ====================');
      
      // Auto-start continuous listening after initialization
      await Future.delayed(const Duration(seconds: 1));
      await startContinuousListening();
      
    } catch (e, stackTrace) {
      AppLogger.error('❌ Audio init error', e, stackTrace);
      AppLogger.test('Attempting retry initialization...');
      // 에러 발생 시 재시도
      await _retryInitialize();
    }
  }
  
  Future<void> _retryInitialize() async {
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.setVolume(1.0);
      
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
        _audioPlayer.stop();
        return;
      }
      
      // AI 오디오 재생 조건을 더 유연하게 변경
      if (audioData.isNotEmpty) {
        AppLogger.test('📻 Received AI audio: ${audioData.length} bytes');
        AppLogger.test('   Current _isSpeaking: $_isSpeaking');
        AppLogger.test('   Current _aiIsResponding: $_aiIsResponding');
        
        // 더 적극적으로 오디오 재생 - _isSpeaking이 false일 때 바로 재생
        if (!_isSpeaking) {
          AppLogger.success('[AUDIO] Playing AI audio - user not speaking');
          addAudioData(audioData);
        } else {
          AppLogger.warning('[AUDIO] Skipping AI audio - user is speaking');
          // 상태를 다시 확인하고 필요시 리셋
          AppLogger.test('Double-checking speaking state...');
        }
      }
    });
  }
  
  /// Add audio data to play (Swift와 같은 큐 방식)
  void addAudioData(Uint8List pcmData) {
    AppLogger.info('🎯 [AUDIO TEST] addAudioData called with ${pcmData.length} bytes');
    
    if (!_isInitialized) {
      AppLogger.error('❌ [AUDIO TEST] Player not initialized! _isInitialized: $_isInitialized');
      return;
    }
    
    if (pcmData.isEmpty) {
      AppLogger.error('❌ [AUDIO TEST] Empty PCM data received!');
      return;
    }
    
    AppLogger.info('🔊 [AUDIO TEST] Adding to queue: ${pcmData.length} bytes');
    
    // Swift처럼 큐에 추가
    _audioQueue.add(pcmData);
    AppLogger.info('📦 [AUDIO TEST] Queue size: ${_audioQueue.length}');
    
    // 즉시 재생 처리 시작 (재생 중이 아니라면)
    _startPlaybackProcessing();
    
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
          final audioData = Uint8List.fromList(chunk);
          
          // Send audio chunk to Realtime API
          _websocket.sendAudio(audioData);
          
          // Save for conversation history
          audioChunks.addAll(chunk);
          
          // Also save to conversation history immediately for replay
          if (audioData.isNotEmpty) {
            conversationHistory.add(ConversationSegment(
              role: 'user',
              audioData: audioData,
              timestamp: DateTime.now(),
            ));
          }
          
          // Calculate audio level for visualization
          _calculateAudioLevel(audioData);
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
      if (!_isInitialized) {
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
        await _audioPlayer.stop();
        AppLogger.info('⏹️ Previous playback stopped');
      } catch (e) {
        AppLogger.warning('Could not stop previous playback: $e');
      }
      
      // 오디오 세션 활성화 확인
      final session = await audio_session.AudioSession.instance;
      await session.setActive(true);
      
      // 새 파일 재생 시작
      AppLogger.info('▶️ Starting playback...');
      await _audioPlayer.play(DeviceFileSource(tempFile.path));
      
      // 재생 완료 리스너 설정
      _audioPlayer.onPlayerComplete.listen((_) async {
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
      });
      
      AppLogger.info('✅ Jupiter voice playback started successfully');
      
    } catch (e) {
      AppLogger.error('❌ Failed to play PCM as WAV: ${e.toString()}', e);
      
      // 상세 디버그 정보
      AppLogger.error('Debug info - PCM size: ${pcmData.length}, Initialized: $_isInitialized');
      
      rethrow; // 재시도 로직에서 처리하도록 예외 재전파
    }
  }
  
  /// Start playback processing with timer
  void _startPlaybackProcessing() {
    if (_audioQueue.isEmpty) return;
    
    // 타이머가 없으면 생성
    _playbackTimer ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
      _processAudioQueue();
    });
    
    // 즉시 처리도 시작
    _processAudioQueue();
  }
  
  /// Process audio queue
  Future<void> _processAudioQueue() async {
    if (_isProcessingAudio || _audioQueue.isEmpty) return;
    
    _isProcessingAudio = true;
    
    try {
      // 큐에서 데이터 가져오기
      final audioData = _audioQueue.removeFirst();
      AppLogger.info('🎵 [AUDIO TEST] Processing chunk: ${audioData.length} bytes, remaining: ${_audioQueue.length}');
      
      // WAV 파일 생성 및 재생
      await _playWavAudio(audioData);
      
    } catch (e) {
      AppLogger.error('❌ Error processing audio', e);
    } finally {
      _isProcessingAudio = false;
      
      // 큐가 비었으면 타이머 정지
      if (_audioQueue.isEmpty) {
        _playbackTimer?.cancel();
        _playbackTimer = null;
        AppLogger.info('✅ [AUDIO TEST] All audio chunks played');
      }
    }
  }
  
  /// Start playback if needed (Swift 방식) - 기존 호환성용
  void _startPlaybackIfNeeded() {
    _startPlaybackProcessing();
  }
  
  /// Play WAV audio directly
  Future<void> _playWavAudio(Uint8List pcmData) async {
    try {
      AppLogger.info('🎵 Starting WAV playback process...');
      
      // WAV 헤더 추가
      final wavData = _createWavFile(pcmData);
      
      // 임시 파일 생성
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/jupiter_$timestamp.wav');
      
      AppLogger.info('📁 Creating temp file: ${tempFile.path}');
      await tempFile.writeAsBytes(wavData);
      AppLogger.info('🎵 WAV file created: ${tempFile.path} (${wavData.length} bytes)');
      
      // 이전 재생 중지
      await _audioPlayer.stop();
      AppLogger.info('⏹️ Previous playback stopped');
      
      // 새로운 재생 시작
      AppLogger.info('▶️ Starting playback...');
      await _audioPlayer.play(DeviceFileSource(tempFile.path));
      AppLogger.info('✅ Jupiter voice playback started successfully');
      
      // 재생 완료 리스너
      _audioPlayer.onPlayerComplete.listen((_) async {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
            AppLogger.info('🗑️ Temp file cleaned up');
          }
        } catch (e) {
          AppLogger.warning('Could not delete temp file: $e');
        }
      });
      
    } catch (e) {
      AppLogger.error('❌ WAV playback error', e);
    }
  }
  
  /// Create WAV file from PCM data
  Uint8List _createWavFile(Uint8List pcmData) {
    // WAV 헤더 생성 (44 bytes)
    const channels = 1;
    const sampleRate = 24000;
    const bitsPerSample = 16;
    
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = pcmData.length;
    final fileSize = dataSize + 36;
    
    final header = BytesBuilder();
    
    // RIFF header
    header.add(utf8.encode('RIFF'));
    header.add(_int32ToBytes(fileSize));
    header.add(utf8.encode('WAVE'));
    
    // fmt chunk
    header.add(utf8.encode('fmt '));
    header.add(_int32ToBytes(16)); // fmt chunk size
    header.add(_int16ToBytes(1)); // PCM format
    header.add(_int16ToBytes(channels));
    header.add(_int32ToBytes(sampleRate));
    header.add(_int32ToBytes(byteRate));
    header.add(_int16ToBytes(blockAlign));
    header.add(_int16ToBytes(bitsPerSample));
    
    // data chunk
    header.add(utf8.encode('data'));
    header.add(_int32ToBytes(dataSize));
    header.add(pcmData);
    
    return header.toBytes();
  }
  
  Uint8List _int16ToBytes(int value) {
    return Uint8List(2)..buffer.asByteData().setInt16(0, value, Endian.little);
  }
  
  Uint8List _int32ToBytes(int value) {
    return Uint8List(4)..buffer.asByteData().setInt32(0, value, Endian.little);
  }
  
  /// Clear audio queue
  void clearQueue() {
    _audioQueue.clear();
    _isPlayingQueue = false;
    _isProcessingAudio = false;
    _playbackTimer?.cancel();
    _playbackTimer = null;
    AppLogger.info('🗑️ [AUDIO TEST] Queue cleared');
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
  
  /// Reset speaking state (called from app lifecycle)
  void resetSpeakingState() {
    AppLogger.test('Resetting speaking state');
    _isSpeaking = false;
    _aiIsResponding = false;
    _updateConversationState();
  }
  
  /// Reset all state (called when app resumes)
  Future<void> resetState() async {
    AppLogger.test('Resetting audio service state');
    _isSpeaking = false;
    _aiIsResponding = false;
    _isPlaying = false;
    
    // Clear audio queue
    clearQueue();
    
    // Stop any ongoing playback
    await _audioPlayer.stop();
    
    // Update conversation state
    _updateConversationState();
    
    AppLogger.success('Audio service state reset complete');
  }
  
  /// Reinitialize service (for app resume)
  Future<void> reinitialize() async {
    AppLogger.test('==================== AUDIO SERVICE REINIT START ====================');
    AppLogger.info('🔄 Reinitializing audio service...');
    
    // 상태 강제 리셋
    _isSpeaking = false;
    _aiIsResponding = false;
    _isPlaying = false;
    _isRecording = false;
    AppLogger.test('🔄 Force state reset - _isSpeaking: false, _aiIsResponding: false');
    
    // StreamController 재생성
    try {
      // 기존 컨트롤러 정리
      await _audioLevelController.close();
      await _conversationStateController.close();
    } catch (e) {
      AppLogger.warning('Could not close existing controllers: $e');
    }
    
    // 새 컨트롤러 생성
    _audioLevelController = StreamController<double>.broadcast();
    _conversationStateController = StreamController<ConversationState>.broadcast();
    AppLogger.test('✅ StreamControllers recreated');
    
    // AudioPlayer 재초기화
    try {
      await _audioPlayer.stop();
      await _audioPlayer.dispose();
    } catch (e) {
      AppLogger.warning('Could not dispose audio player: $e');
    }
    
    // 새 AudioPlayer 생성
    _audioPlayer = AudioPlayer();
    AppLogger.test('✅ AudioPlayer recreated');
    
    // Wait a bit for cleanup
    await Future.delayed(const Duration(milliseconds: 200));
    
    // Reinitialize
    await initialize();
    
    AppLogger.test('==================== AUDIO SERVICE REINIT COMPLETE ====================');
  }
  
  /// Pause streaming (for app pause)
  void pauseStreaming() {
    AppLogger.info('Pausing audio streaming');
    _isPlaying = false;
    _audioPlayer.stop();
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    await stopStreaming();
    
    await _audioStreamSubscription?.cancel();
    await _audioDataSubscription?.cancel();
    
    await _recorder.dispose();
    
    // AudioPlayer 정리
    await _audioPlayer.stop();
    await _audioPlayer.dispose();
    
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