import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:io' show File, Platform;
import 'package:path_provider/path_provider.dart';
import 'openai_realtime_websocket.dart';
import '../core/logger.dart';
import '../utils/audio_utils.dart';

/// Enhanced Audio Streaming Service for Realtime API
/// Fixes AI echo issue and implements Upgrade Replay
class EnhancedAudioStreamingService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final OpenAIRealtimeWebSocket _websocket;
  
  StreamSubscription? _audioStreamSubscription;
  StreamSubscription? _audioDataSubscription;
  StreamSubscription? _eventSubscription;
  
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isSpeaking = false;  // Track if user is speaking
  bool _aiIsResponding = false;  // Track if AI is responding
  
  // Audio buffer and queue management
  final List<int> _audioBuffer = [];
  final List<Uint8List> _audioQueue = [];
  Timer? _playbackTimer;
  
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
  
  /// Initialize service and auto-start microphone
  Future<void> initialize() async {
    try {
      // Request microphone permission
      if (!await _recorder.hasPermission()) {
        AppLogger.warning('Microphone permission not granted');
        return;
      }
      
      // Auto-start continuous listening after permission granted
      await Future.delayed(const Duration(seconds: 1)); // Brief delay for UI
      await startContinuousListening();
    } catch (e) {
      AppLogger.error('Failed to initialize audio service', e);
    }
  }
  
  /// Setup all event listeners
  void _setupListeners() {
    // Listen for audio data from AI
    _audioDataSubscription = _websocket.audioDataStream.listen((audioData) {
      // Only play AI audio if user is not speaking
      if (!_isSpeaking) {
        _handleIncomingAudio(audioData);
      }
    });
    
    // Listen for WebSocket events
    _listenToWebSocketEvents();
  }
  
  /// Listen to specific WebSocket events
  void _listenToWebSocketEvents() {
    // This method would need access to raw WebSocket events
    // For now, we'll handle it through the existing streams
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
      await _audioPlayer.stop();
      _audioQueue.clear();
      _audioBuffer.clear();
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
      _updateConversationState();
      
      AppLogger.info('Audio streaming stopped, AI response requested');
      
    } catch (e) {
      AppLogger.error('Failed to stop audio streaming', e);
    }
  }
  
  /// Handle incoming audio from Realtime API
  void _handleIncomingAudio(Uint8List audioData) {
    // Ignore if user is speaking
    if (_isSpeaking) {
      AppLogger.info('Ignoring AI audio - user is speaking');
      return;
    }
    
    if (audioData.isEmpty) return;
    
    // Add to queue for smooth playback
    _audioQueue.add(audioData);
    
    // Save AI audio for conversation history
    conversationHistory.add(ConversationSegment(
      role: 'assistant',
      audioData: audioData,
      timestamp: DateTime.now(),
    ));
    
    // Start playback if not already playing
    if (!_isPlaying) {
      _startPlayback();
    }
  }
  
  /// Start audio playback with queue management
  void _startPlayback() {
    if (_isPlaying || _isSpeaking) return;
    
    _isPlaying = true;
    AppLogger.info('Starting AI audio playback');
    
    // Process audio queue
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) async {
      if (_audioQueue.isEmpty) {
        // No more audio to play
        _stopPlayback();
        return;
      }
      
      // Stop if user starts speaking
      if (_isSpeaking) {
        _stopPlayback();
        return;
      }
      
      // Get next audio chunk
      final audioChunk = _audioQueue.removeAt(0);
      await _playAudioChunk(audioChunk);
    });
  }
  
  /// Stop audio playback
  void _stopPlayback() {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    _isPlaying = false;
    _aiIsResponding = false;
    _audioQueue.clear();
    _updateConversationState();
    AppLogger.info('AI audio playback stopped');
  }
  
  /// Play a single audio chunk
  Future<void> _playAudioChunk(Uint8List chunk) async {
    try {
      // Stop if user is speaking
      if (_isSpeaking) {
        await _audioPlayer.stop();
        return;
      }
      
      // Convert PCM to WAV (essential for iOS)
      final wavData = AudioUtils.pcmToWav(
        chunk,
        sampleRate: 24000,
        channels: 1,
        bitsPerSample: 16,
      );
      
      // For iOS: Use memory-based audio source
      if (Platform.isIOS) {
        // Create data URI for in-memory playback
        final base64Audio = base64Encode(wavData);
        final dataUri = Uri.parse('data:audio/wav;base64,$base64Audio');
        
        await _audioPlayer.setAudioSource(
          AudioSource.uri(dataUri),
        );
        await _audioPlayer.play();
      } else {
        // For other platforms: Use temporary file
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav');
        await tempFile.writeAsBytes(wavData);
        
        await _audioPlayer.setFilePath(tempFile.path);
        await _audioPlayer.play();
        
        // Clean up after playback
        _audioPlayer.processingStateStream.listen((state) {
          if (state == ProcessingState.completed) {
            if (tempFile.existsSync()) {
              tempFile.deleteSync();
            }
          }
        });
      }
    } catch (e) {
      AppLogger.error('Failed to play audio chunk', e);
    }
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
    _stopPlayback();
    
    await _audioStreamSubscription?.cancel();
    await _audioDataSubscription?.cancel();
    await _eventSubscription?.cancel();
    
    await _recorder.dispose();
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