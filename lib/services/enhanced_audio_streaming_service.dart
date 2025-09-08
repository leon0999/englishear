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
  
  // Timer 기반 오디오 큐 시스템
  final List<Uint8List> _audioQueue = [];
  bool _isPlaying = false;  // 현재 재생 중
  Timer? _processTimer;  // 큐 처리 타이머 (500ms 주기로 변경)
  StreamSubscription? _playerCompleteSubscription;  // 재생 완료 리스너
  final OpenAIRealtimeWebSocket _websocket;
  Completer<void>? _playbackCompleter;  // 재생 완료 대기용
  
  // 24kHz, 16-bit PCM 설정
  static const int sampleRate = 24000;
  static const int bytesPerSample = 2;
  static const int channels = 1;
  
  StreamSubscription? _audioStreamSubscription;
  StreamSubscription? _audioDataSubscription;
  
  bool _isRecording = false;
  bool _isSpeaking = false;
  bool _jupiterSpeaking = false;  // Jupiter AI 음성 재생 상태
  bool _aiIsResponding = false;
  bool _isInitialized = false;
  
  // Conversation history for Upgrade Replay
  final List<ConversationSegment> conversationHistory = [];
  
  // Stream controllers
  StreamController<double>? _audioLevelController;
  StreamController<ConversationState>? _conversationStateController;
  
  Stream<double> get audioLevelStream => _audioLevelController?.stream ?? const Stream.empty();
  Stream<ConversationState> get conversationStateStream => _conversationStateController?.stream ?? const Stream.empty();
  
  EnhancedAudioStreamingService(this._websocket) {
    // Initialize StreamControllers in constructor
    _audioLevelController = StreamController<double>.broadcast();
    _conversationStateController = StreamController<ConversationState>.broadcast();
    AppLogger.test('StreamControllers initialized in constructor');
    
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
    _audioQueue.clear();
    AppLogger.test('🔄 Initial state reset - all flags set to false');
    
    // AudioPlayer 초기화
    _audioPlayer = AudioPlayer();
    await _audioPlayer.setReleaseMode(ReleaseMode.stop);
    // 음성 속도 조절 (0.9 = 10% 느리게)
    await _audioPlayer.setPlaybackRate(0.9);
    AppLogger.test('✅ AudioPlayer initialized with 0.9x playback rate');
    
    // Timer 기반 큐 처리 시작 (500ms마다로 변경 - 더 안정적)
    _processTimer?.cancel();
    _processTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_isPlaying && _audioQueue.isNotEmpty && !_isSpeaking) {
        _processQueue();
      }
    });
    AppLogger.test('✅ Process timer started (500ms interval)');
    
    // StreamController 재초기화 (이미 생성자에서 초기화됨)
    if (_audioLevelController == null || _audioLevelController!.isClosed) {
      _audioLevelController = StreamController<double>.broadcast();
      AppLogger.test('✅ AudioLevelController recreated');
    }
    if (_conversationStateController == null || _conversationStateController!.isClosed) {
      _conversationStateController = StreamController<ConversationState>.broadcast();
      AppLogger.test('✅ ConversationStateController recreated');
    }
    
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
  
  /// Add audio data to play
  void addAudioData(Uint8List pcmData) {
    if (!_isInitialized) {
      AppLogger.error('❌ [AUDIO] Player not initialized!');
      return;
    }
    
    if (pcmData.isEmpty) {
      AppLogger.error('❌ [AUDIO] Empty PCM data received!');
      return;
    }
    
    // 사용자가 말하고 있으면 오디오 스킵
    if (_isSpeaking) {
      AppLogger.warning('⚠️ [AUDIO] Skipping audio - user is speaking');
      return;
    }
    
    // 큐에 추가
    _audioQueue.add(pcmData);
    AppLogger.info('📦 [AUDIO] Added ${pcmData.length} bytes, queue size: ${_audioQueue.length}');
    
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
      
      // 오디오 큐 클리어 및 재생 중지
      _audioQueue.clear();
      await _audioPlayer.stop();
      _isPlaying = false;
      
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
      if (_audioLevelController != null && !_audioLevelController!.isClosed) {
        _audioLevelController!.add(0.0);
      }
      
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
    AppLogger.info('🛑 [AUDIO] Stopping audio playback');
    _isSpeaking = true;
    _jupiterSpeaking = false;
    _audioQueue.clear();
    _audioPlayer.stop();
    _isPlaying = false;
    _playbackCompleter?.complete();
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
  
  /// Process audio queue (called by timer every 500ms)
  Future<void> _processQueue() async {
    // 이미 재생 중이거나 큐가 비었거나 사용자가 말하고 있으면 스킵
    if (_isPlaying || _audioQueue.isEmpty || _isSpeaking) {
      return;
    }
    
    // 최소 8개 청크가 모일 때까지 대기 (충분한 버퍼링)
    if (_audioQueue.length < 8 && _aiIsResponding) {
      return;
    }
    
    _isPlaying = true;
    _jupiterSpeaking = true;  // Jupiter 음성 재생 시작
    _playbackCompleter = Completer<void>();
    
    try {
      // 전체 큐 처리 (끊김 없이)
      final allChunks = List<Uint8List>.from(_audioQueue);
      _audioQueue.clear();
      
      int totalSize = 0;
      for (final chunk in allChunks) {
        totalSize += chunk.length;
      }
      
      if (totalSize == 0 || allChunks.isEmpty) {
        _isPlaying = false;
        _jupiterSpeaking = false;
        return;
      }
      
      AppLogger.info('🎵 [AUDIO] Playing: $totalSize bytes from ${allChunks.length} chunks');
      
      // 모든 청크를 하나로 합치기
      final combinedData = Uint8List(totalSize);
      int offset = 0;
      for (final chunk in allChunks) {
        combinedData.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      
      // 페이드 인/아웃 적용으로 부드러운 전환
      _applyFadeInOut(combinedData);
      
      // WAV 파일 생성 및 재생
      await _playWavWithProperTiming(combinedData);
      
    } catch (e) {
      AppLogger.error('❌ [AUDIO] Playback error: $e', e);
    } finally {
      _isPlaying = false;
      _jupiterSpeaking = false;  // Jupiter 음성 재생 종료
      _playbackCompleter?.complete();
    }
  }
  
  /// Combine multiple chunks into single data
  Uint8List _combineChunks(List<Uint8List> chunks, int totalSize) {
    final combined = Uint8List(totalSize);
    int offset = 0;
    for (final chunk in chunks) {
      combined.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return combined;
  }
  
  /// Play WAV audio with proper timing
  Future<void> _playWavWithProperTiming(Uint8List pcmData) async {
    try {
      // WAV 헤더 추가
      final wavData = _createWavFile(pcmData);
      
      // 임시 파일 생성
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final tempFile = File('${tempDir.path}/jupiter_$timestamp.wav');
      
      await tempFile.writeAsBytes(wavData);
      
      // 사용자가 말하기 시작했으면 중단
      if (_isSpeaking) {
        AppLogger.info('🛑 [AUDIO] User speaking - abort playback');
        await tempFile.delete();
        return;
      }
      
      AppLogger.info('▶️ [AUDIO] Starting playback...');
      
      // 재생 완료 리스너 설정
      final completer = Completer<void>();
      StreamSubscription? subscription;
      
      subscription = _audioPlayer.onPlayerComplete.listen((_) {
        completer.complete();
        subscription?.cancel();
      });
      
      // 재생 시작
      await _audioPlayer.play(DeviceFileSource(tempFile.path));
      
      // 재생 완료 대기
      await completer.future;
      
      AppLogger.info('🏁 [AUDIO] Playback completed');
      
      // 파일 삭제
      try {
        await tempFile.delete();
      } catch (e) {
        // 무시
      }
      
    } catch (e) {
      AppLogger.error('❌ [AUDIO] WAV playback error', e);
    }
  }
  
  
  
  /// Create WAV file from PCM data with correct header
  Uint8List _createWavFile(Uint8List pcmData) {
    final wavHeader = Uint8List(44);
    final dataSize = pcmData.length;
    final fileSize = dataSize + 36;
    
    // RIFF header
    wavHeader.setRange(0, 4, 'RIFF'.codeUnits);
    wavHeader.buffer.asByteData().setUint32(4, fileSize, Endian.little);
    wavHeader.setRange(8, 12, 'WAVE'.codeUnits);
    
    // fmt chunk
    wavHeader.setRange(12, 16, 'fmt '.codeUnits);
    wavHeader.buffer.asByteData().setUint32(16, 16, Endian.little); // fmt chunk size
    wavHeader.buffer.asByteData().setUint16(20, 1, Endian.little); // PCM format
    wavHeader.buffer.asByteData().setUint16(22, channels, Endian.little);
    wavHeader.buffer.asByteData().setUint32(24, sampleRate, Endian.little);
    wavHeader.buffer.asByteData().setUint32(28, sampleRate * channels * bytesPerSample, Endian.little);
    wavHeader.buffer.asByteData().setUint16(32, channels * bytesPerSample, Endian.little);
    wavHeader.buffer.asByteData().setUint16(34, bytesPerSample * 8, Endian.little);
    
    // data chunk
    wavHeader.setRange(36, 40, 'data'.codeUnits);
    wavHeader.buffer.asByteData().setUint32(40, dataSize, Endian.little);
    
    // Combine header and PCM data
    return Uint8List.fromList([...wavHeader, ...pcmData]);
  }
  
  Uint8List _int16ToBytes(int value) {
    return Uint8List(2)..buffer.asByteData().setInt16(0, value, Endian.little);
  }
  
  Uint8List _int32ToBytes(int value) {
    return Uint8List(4)..buffer.asByteData().setInt32(0, value, Endian.little);
  }
  
  /// Apply fade in/out for smooth transitions
  void _applyFadeInOut(Uint8List data) {
    if (data.length < 960) return; // Too short for fade
    
    final fadeLength = 480; // 10ms at 24kHz
    final dataView = data.buffer.asByteData();
    
    // Fade in
    for (int i = 0; i < fadeLength && i * 2 < data.length; i++) {
      final factor = i / fadeLength;
      final sample = dataView.getInt16(i * 2, Endian.little);
      dataView.setInt16(i * 2, (sample * factor).toInt(), Endian.little);
    }
    
    // Fade out
    final startFadeOut = data.length - (fadeLength * 2);
    if (startFadeOut > 0) {
      for (int i = 0; i < fadeLength && startFadeOut + i * 2 < data.length - 1; i++) {
        final factor = 1.0 - (i / fadeLength);
        final sample = dataView.getInt16(startFadeOut + i * 2, Endian.little);
        dataView.setInt16(startFadeOut + i * 2, (sample * factor).toInt(), Endian.little);
      }
    }
  }
  
  /// Clear audio queue
  void clearQueue() {
    _audioQueue.clear();
    _isPlaying = false;
    AppLogger.info('🗑️ [AUDIO] Queue cleared');
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
    
    // null 체크 추가
    if (_audioLevelController != null && !_audioLevelController!.isClosed) {
      _audioLevelController!.add(level);
    }
  }
  
  /// Update conversation state
  void _updateConversationState() {
    // null 체크 추가
    if (_conversationStateController != null && !_conversationStateController!.isClosed) {
      _conversationStateController!.add(ConversationState(
        isUserSpeaking: _isSpeaking,
        isAiResponding: _aiIsResponding,
        isRecording: _isRecording,
        isPlaying: _isPlaying,
      ));
    } else {
      AppLogger.warning('ConversationStateController is null or closed');
    }
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
  
  /// Check if Jupiter is speaking
  bool get isJupiterSpeaking => _jupiterSpeaking;
  
  /// Wait for playback completion
  Future<void> waitForCompletion() async {
    if (_playbackCompleter != null && !_playbackCompleter!.isCompleted) {
      await _playbackCompleter!.future;
    }
  }
  
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
    _jupiterSpeaking = false;
    _aiIsResponding = false;
    _isPlaying = false;
    _playbackCompleter?.complete();
    
    // Clear audio queue
    clearQueue();
    
    // Stop any ongoing playback
    try {
      await _audioPlayer.stop();
    } catch (e) {
      AppLogger.warning('Could not stop audio player: $e');
    }
    
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
    AppLogger.test('🔄 Force state reset - all flags set to false');
    
    // 오디오 큐 클리어
    clearQueue();
    
    // Timer 재시작
    _processTimer?.cancel();
    _processTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      if (!_isPlaying && _audioQueue.isNotEmpty && !_isSpeaking) {
        _processQueue();
      }
    });
    
    // StreamController 재생성
    try {
      // 기존 컨트롤러 정리
      await _audioLevelController?.close();
      await _conversationStateController?.close();
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
    
    // 오디오 세션 재설정 (OSStatus 에러 방지)
    try {
      final session = await audio_session.AudioSession.instance;
      await session.setActive(false);
      await Future.delayed(const Duration(milliseconds: 100));
      await session.setActive(true);
      AppLogger.success('Audio session reactivated');
    } catch (e) {
      AppLogger.warning('⚠️ Audio session error (ignored): $e');
    }
    
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
    _processTimer?.cancel();
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    await stopStreaming();
    
    await _audioStreamSubscription?.cancel();
    await _audioDataSubscription?.cancel();
    await _playerCompleteSubscription?.cancel();
    _processTimer?.cancel();
    
    await _recorder.dispose();
    
    // AudioPlayer 정리
    await _audioPlayer.stop();
    await _audioPlayer.dispose();
    
    await _audioLevelController?.close();
    await _conversationStateController?.close();
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