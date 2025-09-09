import 'dart:async';
import 'dart:typed_data';
import 'dart:collection';
import '../core/logger.dart';
import 'improved_audio_service.dart';
// import 'webrtc_audio_service.dart'; // Temporarily disabled due to build issues

/// Real-time conversation engine with parallel processing
/// Inspired by Moshi's dual-stream architecture
class RealtimeConversationEngine {
  // Audio services
  final ImprovedAudioService _audioService = ImprovedAudioService();
  // final WebRTCAudioService? _webrtcService = WebRTCAudioService(); // Temporarily disabled
  
  // Dual stream processing (like Moshi)
  final StreamController<AudioStream> _userStreamController = StreamController.broadcast();
  final StreamController<AudioStream> _aiStreamController = StreamController.broadcast();
  
  // Conversation state
  ConversationMode _mode = ConversationMode.idle;
  bool _isProcessing = false;
  
  // Parallel processing queues
  final Queue<ProcessingTask> _userTasks = Queue();
  final Queue<ProcessingTask> _aiTasks = Queue();
  
  // Voice Activity Detection (VAD)
  final VoiceActivityDetector _vad = VoiceActivityDetector();
  
  // Interruption handling
  bool _allowInterruptions = true;
  DateTime? _lastUserActivity;
  DateTime? _lastAiActivity;
  
  // Performance metrics
  final PerformanceMonitor _performanceMonitor = PerformanceMonitor();
  
  // Stream getters
  Stream<AudioStream> get userStream => _userStreamController.stream;
  Stream<AudioStream> get aiStream => _aiStreamController.stream;
  
  /// Initialize the conversation engine
  Future<void> initialize({bool useWebRTC = false}) async {
    AppLogger.test('==================== CONVERSATION ENGINE INIT ====================');
    
    await _audioService.initialize();
    
    if (useWebRTC) {
      // await _webrtcService?.initialize(); // Temporarily disabled
      _setupWebRTCStreams();
    }
    
    _startParallelProcessing();
    
    AppLogger.success('✅ Conversation engine initialized with parallel processing');
  }
  
  /// Setup WebRTC streams for ultra-low latency
  void _setupWebRTCStreams() {
    // _webrtcService?.audioDataStream.listen((data) { // Temporarily disabled
    //   _processIncomingAudio(data, StreamSource.remote);
    // });
  }
  
  /// Start parallel processing loops
  void _startParallelProcessing() {
    // User stream processor
    Timer.periodic(const Duration(milliseconds: 10), (_) {
      if (_userTasks.isNotEmpty && !_isProcessing) {
        _processUserTask();
      }
    });
    
    // AI stream processor
    Timer.periodic(const Duration(milliseconds: 10), (_) {
      if (_aiTasks.isNotEmpty && !_isProcessing) {
        _processAiTask();
      }
    });
    
    AppLogger.info('🔄 Started parallel processing loops (10ms intervals)');
  }
  
  /// Process incoming audio with VAD and interruption detection
  void _processIncomingAudio(Uint8List audioData, StreamSource source) {
    final timestamp = DateTime.now();
    
    // Voice Activity Detection
    final hasVoice = _vad.detectVoice(audioData);
    
    if (source == StreamSource.user) {
      _lastUserActivity = timestamp;
      
      if (hasVoice) {
        // Check for interruption
        if (_shouldInterruptAi()) {
          _handleInterruption();
        }
        
        // Add to user processing queue
        _userTasks.add(ProcessingTask(
          data: audioData,
          timestamp: timestamp,
          hasVoice: hasVoice,
        ));
      }
    } else {
      _lastAiActivity = timestamp;
      
      // Add to AI processing queue
      _aiTasks.add(ProcessingTask(
        data: audioData,
        timestamp: timestamp,
        hasVoice: hasVoice,
      ));
    }
    
    _updateConversationMode();
  }
  
  /// Check if AI should be interrupted
  bool _shouldInterruptAi() {
    if (!_allowInterruptions) return false;
    
    // Check if AI is currently speaking
    if (_lastAiActivity != null) {
      final timeSinceAi = DateTime.now().difference(_lastAiActivity!).inMilliseconds;
      return timeSinceAi < 500; // Interrupt if AI spoke within last 500ms
    }
    
    return false;
  }
  
  /// Handle interruption gracefully
  void _handleInterruption() {
    AppLogger.info('🎯 User interruption detected - stopping AI speech');
    
    // Clear AI audio queue
    _audioService.clearQueue();
    _aiTasks.clear();
    
    // Notify AI to stop generating
    _aiStreamController.add(AudioStream(
      type: StreamType.control,
      control: ControlMessage.stop,
    ));
    
    _mode = ConversationMode.userSpeaking;
  }
  
  /// Process user task from queue
  Future<void> _processUserTask() async {
    if (_userTasks.isEmpty) return;
    
    final task = _userTasks.removeFirst();
    _performanceMonitor.startMeasurement('user_processing');
    
    try {
      // Process in parallel with AI
      final processedAudio = await _enhanceUserAudio(task.data);
      
      // Emit to user stream
      _userStreamController.add(AudioStream(
        type: StreamType.audio,
        data: processedAudio,
        timestamp: task.timestamp,
        metadata: {
          'hasVoice': task.hasVoice,
          'source': 'user',
        },
      ));
      
      final latency = _performanceMonitor.endMeasurement('user_processing');
      AppLogger.debug('👤 User audio processed in ${latency}ms');
      
    } catch (e) {
      AppLogger.error('Failed to process user audio', e);
    }
  }
  
  /// Process AI task from queue
  Future<void> _processAiTask() async {
    if (_aiTasks.isEmpty) return;
    
    final task = _aiTasks.removeFirst();
    _performanceMonitor.startMeasurement('ai_processing');
    
    try {
      // Add to audio playback queue immediately (no waiting)
      _audioService.addAudioChunk(task.data, chunkId: 'ai_${task.timestamp.millisecondsSinceEpoch}');
      
      // Emit to AI stream
      _aiStreamController.add(AudioStream(
        type: StreamType.audio,
        data: task.data,
        timestamp: task.timestamp,
        metadata: {
          'source': 'ai',
        },
      ));
      
      final latency = _performanceMonitor.endMeasurement('ai_processing');
      AppLogger.debug('🤖 AI audio processed in ${latency}ms');
      
    } catch (e) {
      AppLogger.error('Failed to process AI audio', e);
    }
  }
  
  /// Enhance user audio (noise reduction, normalization)
  Future<Uint8List> _enhanceUserAudio(Uint8List rawAudio) async {
    // Apply audio enhancements
    // In production, use actual DSP algorithms
    return rawAudio;
  }
  
  /// Update conversation mode based on activity
  void _updateConversationMode() {
    final now = DateTime.now();
    
    if (_lastUserActivity != null && 
        now.difference(_lastUserActivity!).inMilliseconds < 500) {
      _mode = ConversationMode.userSpeaking;
    } else if (_lastAiActivity != null && 
               now.difference(_lastAiActivity!).inMilliseconds < 500) {
      _mode = ConversationMode.aiSpeaking;
    } else {
      _mode = ConversationMode.idle;
    }
  }
  
  /// Start conversation with full-duplex support
  Future<void> startConversation() async {
    AppLogger.info('🎤 Starting full-duplex conversation');
    
    _mode = ConversationMode.active;
    
    // Start recording with real-time streaming
    await _audioService.startRecording((audioData) {
      _processIncomingAudio(audioData, StreamSource.user);
    });
  }
  
  /// Stop conversation
  Future<void> stopConversation() async {
    AppLogger.info('🛑 Stopping conversation');
    
    _mode = ConversationMode.idle;
    await _audioService.stopRecording();
    
    // Clear all queues
    _userTasks.clear();
    _aiTasks.clear();
    _audioService.clearQueue();
  }
  
  /// Send AI response audio
  void sendAiAudio(Uint8List audioData) {
    _processIncomingAudio(audioData, StreamSource.ai);
  }
  
  /// Get performance metrics
  Map<String, dynamic> getPerformanceMetrics() {
    return _performanceMonitor.getMetrics();
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    await stopConversation();
    await _audioService.dispose();
    // await _webrtcService?.dispose(); // Temporarily disabled
    await _userStreamController.close();
    await _aiStreamController.close();
    
    AppLogger.info('🔚 Conversation engine disposed');
  }
}

/// Voice Activity Detector
class VoiceActivityDetector {
  static const double energyThreshold = 0.01;
  static const int minVoiceFrames = 5;
  
  int _voiceFrameCount = 0;
  
  bool detectVoice(Uint8List audioData) {
    // Calculate energy
    double energy = 0;
    for (int i = 0; i < audioData.length; i += 2) {
      if (i + 1 < audioData.length) {
        final sample = (audioData[i] | (audioData[i + 1] << 8)).toSigned(16) / 32768.0;
        energy += sample * sample;
      }
    }
    
    energy = energy / (audioData.length / 2);
    
    // Check if voice is present
    if (energy > energyThreshold) {
      _voiceFrameCount++;
    } else {
      _voiceFrameCount = 0;
    }
    
    return _voiceFrameCount >= minVoiceFrames;
  }
}

/// Performance monitoring
class PerformanceMonitor {
  final Map<String, DateTime> _startTimes = {};
  final Map<String, List<int>> _measurements = {};
  
  void startMeasurement(String key) {
    _startTimes[key] = DateTime.now();
  }
  
  int endMeasurement(String key) {
    if (!_startTimes.containsKey(key)) return 0;
    
    final duration = DateTime.now().difference(_startTimes[key]!).inMilliseconds;
    _measurements.putIfAbsent(key, () => []).add(duration);
    _startTimes.remove(key);
    
    return duration;
  }
  
  Map<String, dynamic> getMetrics() {
    final metrics = <String, dynamic>{};
    
    _measurements.forEach((key, values) {
      if (values.isNotEmpty) {
        final avg = values.reduce((a, b) => a + b) / values.length;
        final min = values.reduce((a, b) => a < b ? a : b);
        final max = values.reduce((a, b) => a > b ? a : b);
        
        metrics[key] = {
          'avg': avg.toStringAsFixed(2),
          'min': min,
          'max': max,
          'count': values.length,
        };
      }
    });
    
    return metrics;
  }
}

/// Audio stream data
class AudioStream {
  final StreamType type;
  final Uint8List? data;
  final DateTime? timestamp;
  final ControlMessage? control;
  final Map<String, dynamic>? metadata;
  
  AudioStream({
    required this.type,
    this.data,
    this.timestamp,
    this.control,
    this.metadata,
  });
}

/// Processing task
class ProcessingTask {
  final Uint8List data;
  final DateTime timestamp;
  final bool hasVoice;
  
  ProcessingTask({
    required this.data,
    required this.timestamp,
    required this.hasVoice,
  });
}

// Enums
enum ConversationMode { idle, active, userSpeaking, aiSpeaking }
enum StreamSource { user, ai, remote }
enum StreamType { audio, control, metadata }
enum ControlMessage { start, stop, pause, resume }