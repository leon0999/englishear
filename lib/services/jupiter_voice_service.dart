import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../core/logger.dart';
import 'enhanced_audio_pipeline.dart';
import 'multi_engine_tts.dart';
import 'openai_voice_optimizer.dart';
import 'openai_realtime_websocket.dart';

/// Jupiter AI voice service with RealtimeTTS-inspired enhancements
class JupiterVoiceService extends ChangeNotifier {
  final EnhancedAudioPipeline _pipeline;
  final OpenAIRealtimeWebSocket _websocket;
  
  // Service state
  bool _isInitialized = false;
  bool _isSpeaking = false;
  String _currentScenario = 'casual_chat';
  
  // Metrics
  final Map<String, dynamic> _metrics = {
    'totalUtterances': 0,
    'totalWords': 0,
    'averageLatency': 0.0,
    'lastSpeechTime': null,
  };
  
  // Stream controllers
  final StreamController<Map<String, dynamic>> _metricsController = StreamController.broadcast();
  final StreamController<String> _speechStatusController = StreamController.broadcast();
  
  JupiterVoiceService({
    OpenAIRealtimeWebSocket? websocket,
    EnhancedAudioPipeline? pipeline,
  }) : _websocket = websocket ?? OpenAIRealtimeWebSocket(),
       _pipeline = pipeline ?? EnhancedAudioPipeline(
         tts: MultiEngineTTS(customEngines: [
           OpenAIRealtimeEngine(), // Custom engine for OpenAI Realtime
           EdgeTTSEngine(),
           WebSpeechTTSEngine(),
         ]),
       );
  
  // Getters
  bool get isInitialized => _isInitialized;
  bool get isSpeaking => _isSpeaking;
  String get currentScenario => _currentScenario;
  Map<String, dynamic> get metrics => Map.from(_metrics);
  Stream<Map<String, dynamic>> get metricsStream => _metricsController.stream;
  Stream<String> get speechStatusStream => _speechStatusController.stream;
  
  /// Initialize Jupiter with optimized voice settings
  Future<void> initialize() async {
    if (_isInitialized) {
      AppLogger.warning('Jupiter voice already initialized');
      return;
    }
    
    try {
      AppLogger.info('==================== JUPITER VOICE INIT START ====================');
      
      // Connect WebSocket if not connected
      if (!_websocket.isConnected) {
        await _websocket.connect();
      }
      
      // Apply optimized voice configuration
      final config = OpenAIVoiceOptimizer.getOptimalConfig(profile: 'natural');
      await _websocket.send(jsonEncode(config));
      
      AppLogger.success('Jupiter voice configuration applied');
      
      // Listen to WebSocket events
      _setupWebSocketListeners();
      
      // Listen to pipeline volume changes
      _pipeline.volumeStream.listen((volume) {
        _metrics['currentVolume'] = volume;
        _notifyMetrics();
      });
      
      _isInitialized = true;
      notifyListeners();
      
      AppLogger.success('==================== JUPITER VOICE INIT COMPLETE ====================');
    } catch (e) {
      AppLogger.error('Jupiter voice initialization failed', data: {'error': e.toString()});
      _isInitialized = false;
      throw e;
    }
  }
  
  /// Speak text with scenario-based optimization
  Future<void> speak(String text, {String? scenario}) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    if (_isSpeaking) {
      AppLogger.warning('Jupiter is already speaking, queuing text');
    }
    
    try {
      final startTime = DateTime.now();
      _isSpeaking = true;
      _currentScenario = scenario ?? 'casual_chat';
      _speechStatusController.add('preparing');
      notifyListeners();
      
      AppLogger.info('Jupiter speaking: "$text" [Scenario: $_currentScenario]');
      
      // Update scenario-specific settings if needed
      if (scenario != null) {
        final scenarioConfig = OpenAIVoiceOptimizer.getScenarioConfig(scenario);
        await _websocket.send(jsonEncode(scenarioConfig));
      }
      
      // Adjust voice based on content
      final contentAdjustments = OpenAIVoiceOptimizer.adjustForContent(text);
      if (contentAdjustments.isNotEmpty) {
        AppLogger.debug('Applying content adjustments', data: contentAdjustments);
      }
      
      _speechStatusController.add('processing');
      
      // Process text through enhanced pipeline
      await _pipeline.processText(text);
      
      // Update metrics
      final latency = DateTime.now().difference(startTime).inMilliseconds;
      _updateMetrics(text, latency);
      
      _isSpeaking = false;
      _speechStatusController.add('complete');
      notifyListeners();
      
      AppLogger.success('Jupiter finished speaking. Latency: ${latency}ms');
    } catch (e) {
      AppLogger.error('Jupiter speech failed', data: {'error': e.toString()});
      _isSpeaking = false;
      _speechStatusController.add('error');
      notifyListeners();
      
      // Fallback to system TTS
      await _fallbackToSystemTTS(text);
    }
  }
  
  /// Stream-based speaking for real-time responses
  Stream<void> speakStream(Stream<String> textStream, {String? scenario}) async* {
    if (!_isInitialized) {
      await initialize();
    }
    
    try {
      _isSpeaking = true;
      _currentScenario = scenario ?? 'casual_chat';
      _speechStatusController.add('streaming');
      notifyListeners();
      
      // Apply scenario settings
      if (scenario != null) {
        final scenarioConfig = OpenAIVoiceOptimizer.getScenarioConfig(scenario);
        await _websocket.send(jsonEncode(scenarioConfig));
      }
      
      // Process text stream through pipeline
      await for (final _ in _pipeline.processTextStream(textStream)) {
        yield null; // Signal progress
      }
      
      _isSpeaking = false;
      _speechStatusController.add('complete');
      notifyListeners();
    } catch (e) {
      AppLogger.error('Jupiter stream speech failed', data: {'error': e.toString()});
      _isSpeaking = false;
      _speechStatusController.add('error');
      notifyListeners();
    }
  }
  
  /// Stop current speech
  Future<void> stop() async {
    if (!_isSpeaking) return;
    
    AppLogger.info('Stopping Jupiter speech');
    await _pipeline.stop();
    _isSpeaking = false;
    _speechStatusController.add('stopped');
    notifyListeners();
  }
  
  /// Change voice profile
  Future<void> changeVoiceProfile(String profile) async {
    if (!_isInitialized) {
      await initialize();
    }
    
    AppLogger.info('Changing voice profile to: $profile');
    
    final config = OpenAIVoiceOptimizer.getOptimalConfig(profile: profile);
    await _websocket.send(jsonEncode(config));
    
    _currentScenario = profile;
    notifyListeners();
  }
  
  /// Get voice diagnostics
  Map<String, dynamic> getVoiceDiagnostics() {
    final currentConfig = OpenAIVoiceOptimizer.getOptimalConfig(profile: _currentScenario);
    return OpenAIVoiceOptimizer.getDiagnostics(currentConfig['session']);
  }
  
  /// Setup WebSocket event listeners
  void _setupWebSocketListeners() {
    // Listen for audio chunks from WebSocket
    _websocket.audioStream.listen((audioData) async {
      if (_isSpeaking && audioData != null) {
        // Process audio through pipeline
        await _pipeline._processAudioChunk(audioData);
      }
    });
    
    // Listen for transcripts
    _websocket.transcriptStream.listen((transcript) {
      AppLogger.debug('Jupiter transcript: $transcript');
    });
    
    // Listen for errors
    _websocket.errorStream.listen((error) {
      AppLogger.error('WebSocket error in Jupiter', data: {'error': error});
      _speechStatusController.add('error');
    });
  }
  
  /// Update speech metrics
  void _updateMetrics(String text, int latencyMs) {
    _metrics['totalUtterances'] = (_metrics['totalUtterances'] ?? 0) + 1;
    _metrics['totalWords'] = (_metrics['totalWords'] ?? 0) + text.split(' ').length;
    
    // Calculate running average latency
    final currentAvg = _metrics['averageLatency'] ?? 0.0;
    final count = _metrics['totalUtterances'] ?? 1;
    _metrics['averageLatency'] = ((currentAvg * (count - 1)) + latencyMs) / count;
    
    _metrics['lastSpeechTime'] = DateTime.now().toIso8601String();
    _metrics['lastLatency'] = latencyMs;
    
    // Get pipeline metrics
    _metrics['pipeline'] = _pipeline.getMetrics();
    
    _notifyMetrics();
  }
  
  /// Notify metrics listeners
  void _notifyMetrics() {
    _metricsController.add(Map.from(_metrics));
  }
  
  /// Fallback to system TTS
  Future<void> _fallbackToSystemTTS(String text) async {
    try {
      AppLogger.warning('Using fallback system TTS');
      // Implementation would use flutter_tts or platform channels
      // For now, just log the fallback
      _speechStatusController.add('fallback');
    } catch (e) {
      AppLogger.error('Fallback TTS also failed', data: {'error': e.toString()});
    }
  }
  
  /// Dispose resources
  @override
  void dispose() {
    _pipeline.dispose();
    _metricsController.close();
    _speechStatusController.close();
    super.dispose();
  }
}

/// Custom TTS engine for OpenAI Realtime API
class OpenAIRealtimeEngine implements TTSEngine {
  @override
  String get name => 'OpenAI Realtime';
  
  @override
  int get priority => 1;
  
  @override
  bool get isAvailable => true; // Assume WebSocket is connected
  
  @override
  Future<Stream<Uint8List>> synthesize(String text, {Map<String, dynamic>? options}) async {
    // This would integrate with the WebSocket to get audio
    // For now, return empty stream as the actual audio comes through WebSocket
    return Stream.empty();
  }
}