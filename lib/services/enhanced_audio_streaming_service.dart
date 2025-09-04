import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:record/record.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'dart:io' show Platform;
import 'openai_realtime_websocket.dart';
import '../core/logger.dart';
import '../utils/audio_utils.dart';

/// Enhanced Audio Streaming Service for Realtime API with PCM Direct Playback
/// No WAV conversion - Direct PCM streaming for natural voice
class EnhancedAudioStreamingService {
  final AudioRecorder _recorder = AudioRecorder();
  FlutterSoundPlayer? _soundPlayer;
  final OpenAIRealtimeWebSocket _websocket;
  
  StreamSubscription? _audioStreamSubscription;
  StreamSubscription? _audioDataSubscription;
  StreamController<Uint8List>? _audioStreamController;
  
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isSpeaking = false;  // Track if user is speaking
  bool _aiIsResponding = false;  // Track if AI is responding
  bool _playerInitialized = false;
  
  // Audio buffer for PCM data
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
  
  /// Initialize service with PCM streaming support
  Future<void> initialize() async {
    try {
      AppLogger.info('🎵 Initializing PCM audio streaming...');
      
      // Request microphone permission
      if (!await _recorder.hasPermission()) {
        AppLogger.warning('Microphone permission not granted');
        return;
      }
      
      // Initialize flutter_sound player
      _soundPlayer = FlutterSoundPlayer();
      _audioStreamController = StreamController<Uint8List>.broadcast();
      
      // Open the player
      await _soundPlayer!.openPlayer();
      _playerInitialized = true;
      
      // Configure audio session for iOS
      if (Platform.isIOS) {
        await _soundPlayer!.setVolume(1.0);
      }
      
      AppLogger.info('✅ PCM streaming ready');
      
      // Auto-start continuous listening after initialization
      await Future.delayed(const Duration(seconds: 1));
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
      if (!_isSpeaking && audioData.isNotEmpty) {
        _handleIncomingAudio(audioData);
      }
    });
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
      await stopAudioOutput();
      _audioQueue.clear();
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
  
  /// Handle incoming PCM audio from Realtime API
  void _handleIncomingAudio(Uint8List audioData) async {
    // Ignore if user is speaking
    if (_isSpeaking) {
      AppLogger.info('Ignoring AI audio - user is speaking');
      return;
    }
    
    if (audioData.isEmpty) return;
    
    AppLogger.info('🔊 Received PCM audio: ${audioData.length} bytes');
    
    // Add to queue for streaming
    _audioQueue.add(audioData);
    
    // Save AI audio for conversation history
    conversationHistory.add(ConversationSegment(
      role: 'assistant',
      audioData: audioData,
      timestamp: DateTime.now(),
    ));
    
    // Start PCM streaming if not already playing
    if (!_isPlaying) {
      _startPCMStreaming();
    }
  }
  
  /// Start PCM audio streaming directly without WAV conversion
  void _startPCMStreaming() async {
    if (_isPlaying || _isSpeaking || !_playerInitialized) return;
    
    _isPlaying = true;
    AppLogger.info('🎵 Starting PCM audio streaming');
    
    // Process audio queue with WAV conversion for compatibility
    _playbackTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (_audioQueue.isEmpty) {
        // No more audio to play
        _stopPCMStreaming();
        return;
      }
      
      // Stop if user starts speaking
      if (_isSpeaking) {
        _stopPCMStreaming();
        return;
      }
      
      // Play next chunk
      if (_audioQueue.isNotEmpty && !_soundPlayer!.isPlaying) {
        final pcmChunk = _audioQueue.removeAt(0);
        
        try {
          // Convert PCM to WAV for compatibility
          final wavData = AudioUtils.pcmToWav(pcmChunk, sampleRate: 24000);
          
          // Play WAV data
          await _soundPlayer!.startPlayer(
            fromDataBuffer: wavData,
            codec: Codec.pcm16WAV,
            whenFinished: () {
              AppLogger.debug('Finished playing chunk');
            },
          );
          
          AppLogger.debug('Playing audio chunk: ${pcmChunk.length} bytes');
        } catch (e) {
          AppLogger.error('Failed to play audio chunk', e);
        }
      }
    });
  }
  
  /// Stop PCM streaming
  Future<void> _stopPCMStreaming() async {
    _playbackTimer?.cancel();
    _playbackTimer = null;
    
    if (_soundPlayer != null && _soundPlayer!.isPlaying) {
      await _soundPlayer!.stopPlayer();
    }
    
    _isPlaying = false;
    _aiIsResponding = false;
    _audioQueue.clear();
    _updateConversationState();
    
    AppLogger.info('PCM streaming stopped');
  }
  
  /// Stop audio output immediately
  Future<void> stopAudioOutput() async {
    await _stopPCMStreaming();
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
    await stopAudioOutput();
    
    await _audioStreamSubscription?.cancel();
    await _audioDataSubscription?.cancel();
    
    await _recorder.dispose();
    
    if (_soundPlayer != null) {
      await _soundPlayer!.closePlayer();
    }
    
    await _audioStreamController?.close();
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