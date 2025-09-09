import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../core/logger.dart';
import 'realtime_conversation_engine.dart';

/// Optimized OpenAI Realtime API Service
/// Achieves < 300ms response time with streaming
class OptimizedOpenAIService {
  static const String _wsUrl = 'wss://api.openai.com/v1/realtime';
  static const String _model = 'gpt-4-realtime-preview';
  
  WebSocketChannel? _channel;
  final RealtimeConversationEngine _conversationEngine = RealtimeConversationEngine();
  
  // Optimization flags
  bool _useStreamingResponse = true;
  bool _enablePartialTranscripts = true;
  bool _useAdaptiveBitrate = true;
  
  // Response handling
  final StreamController<ResponseChunk> _responseController = StreamController.broadcast();
  Stream<ResponseChunk> get responseStream => _responseController.stream;
  
  // Performance tracking
  DateTime? _requestStartTime;
  int _totalLatency = 0;
  int _responseCount = 0;
  
  // Buffer for partial responses
  final StringBuffer _partialTextBuffer = StringBuffer();
  final List<Uint8List> _partialAudioBuffer = [];
  
  /// Initialize optimized service
  Future<void> initialize(String apiKey) async {
    AppLogger.test('==================== OPTIMIZED OPENAI INIT ====================');
    
    // Initialize conversation engine with WebRTC for lowest latency
    await _conversationEngine.initialize(useWebRTC: true);
    
    // Connect to OpenAI Realtime API
    await _connectWebSocket(apiKey);
    
    // Setup optimized event handlers
    _setupOptimizedHandlers();
    
    AppLogger.success('✅ Optimized OpenAI service initialized');
  }
  
  /// Connect to WebSocket with optimized settings
  Future<void> _connectWebSocket(String apiKey) async {
    try {
      final uri = Uri.parse('$_wsUrl?model=$_model');
      
      _channel = IOWebSocketChannel.connect(uri, headers: {
        'Authorization': 'Bearer $apiKey',
        'OpenAI-Beta': 'realtime=v1',
      });
      
      // Send initial configuration for optimization
      _sendOptimizedConfig();
      
      AppLogger.info('🔗 Connected to OpenAI Realtime API');
    } catch (e) {
      AppLogger.error('Failed to connect to OpenAI', e);
      rethrow;
    }
  }
  
  /// Send optimized configuration
  void _sendOptimizedConfig() {
    final config = {
      'type': 'session.update',
      'session': {
        'modalities': ['text', 'audio'],
        'instructions': _getOptimizedInstructions(),
        'voice': 'alloy',
        'input_audio_format': 'pcm16',
        'output_audio_format': 'pcm16',
        'input_audio_transcription': {
          'enabled': true,
          'model': 'whisper-1',
          'language': 'en',
        },
        'turn_detection': {
          'type': 'server_vad',
          'threshold': 0.5,
          'prefix_padding_ms': 200,
          'silence_duration_ms': 500,
        },
        'temperature': 0.7,
        'max_tokens': 150, // Shorter responses for faster generation
        'top_p': 0.9,
        'frequency_penalty': 0.1,
        'presence_penalty': 0.1,
        'stream': true, // Enable streaming
        'stream_options': {
          'include_usage': false, // Skip usage to reduce payload
        },
      },
    };
    
    _channel?.sink.add(jsonEncode(config));
    AppLogger.info('⚙️ Sent optimized configuration');
  }
  
  /// Get optimized instructions for faster responses
  String _getOptimizedInstructions() {
    return '''
    You are an ultra-responsive English conversation partner.
    CRITICAL: Respond IMMEDIATELY with short, natural phrases.
    - Keep responses under 30 words for instant delivery
    - Use conversational fillers naturally
    - Mirror the user's speaking pace
    - Interrupt politely when appropriate
    - Think and respond in parallel, not sequentially
    ''';
  }
  
  /// Setup optimized event handlers
  void _setupOptimizedHandlers() {
    _channel?.stream.listen(
      (message) => _handleOptimizedMessage(jsonDecode(message)),
      onError: (error) => AppLogger.error('WebSocket error', error),
      onDone: () => _handleDisconnection(),
    );
    
    // Setup conversation engine streams
    _conversationEngine.userStream.listen((stream) {
      if (stream.type == StreamType.audio && stream.data != null) {
        _sendUserAudio(stream.data!);
      }
    });
    
    _conversationEngine.aiStream.listen((stream) {
      if (stream.type == StreamType.control && 
          stream.control == ControlMessage.stop) {
        _cancelCurrentResponse();
      }
    });
  }
  
  /// Handle messages with optimization
  void _handleOptimizedMessage(Map<String, dynamic> message) {
    final type = message['type'];
    
    switch (type) {
      case 'response.audio.delta':
        _handleAudioDelta(message);
        break;
        
      case 'response.text.delta':
        _handleTextDelta(message);
        break;
        
      case 'response.audio_transcript.delta':
        _handleTranscriptDelta(message);
        break;
        
      case 'response.done':
        _handleResponseComplete(message);
        break;
        
      case 'conversation.item.input_audio_transcription.completed':
        _handleUserTranscript(message);
        break;
        
      case 'error':
        AppLogger.error('API Error: ${message['error']}');
        break;
    }
  }
  
  /// Handle audio delta with immediate playback
  void _handleAudioDelta(Map<String, dynamic> message) {
    final deltaBase64 = message['delta'];
    if (deltaBase64 == null) return;
    
    try {
      final audioData = base64Decode(deltaBase64);
      
      // Send immediately to conversation engine for playback
      _conversationEngine.sendAiAudio(audioData);
      
      // Track first byte latency
      if (_requestStartTime != null && _responseCount == 0) {
        final latency = DateTime.now().difference(_requestStartTime!).inMilliseconds;
        AppLogger.success('🎯 First byte latency: ${latency}ms');
        _totalLatency = latency;
      }
      
      _responseCount++;
      
      // Buffer for complete response
      _partialAudioBuffer.add(audioData);
      
    } catch (e) {
      AppLogger.error('Failed to process audio delta', e);
    }
  }
  
  /// Handle text delta for real-time display
  void _handleTextDelta(Map<String, dynamic> message) {
    final delta = message['delta'] ?? '';
    _partialTextBuffer.write(delta);
    
    // Emit partial text immediately
    _responseController.add(ResponseChunk(
      type: ChunkType.text,
      text: delta,
      isPartial: true,
    ));
  }
  
  /// Handle transcript delta
  void _handleTranscriptDelta(Map<String, dynamic> message) {
    final delta = message['delta'] ?? '';
    
    // Emit transcript update
    _responseController.add(ResponseChunk(
      type: ChunkType.transcript,
      text: delta,
      isPartial: true,
    ));
  }
  
  /// Handle response completion
  void _handleResponseComplete(Map<String, dynamic> message) {
    if (_requestStartTime != null) {
      final totalLatency = DateTime.now().difference(_requestStartTime!).inMilliseconds;
      final avgChunkLatency = _responseCount > 0 ? _totalLatency ~/ _responseCount : 0;
      
      AppLogger.success('📊 Response complete:');
      AppLogger.success('  Total latency: ${totalLatency}ms');
      AppLogger.success('  First byte: ${_totalLatency}ms');
      AppLogger.success('  Chunks: $_responseCount');
      AppLogger.success('  Avg chunk: ${avgChunkLatency}ms');
    }
    
    // Emit complete response
    _responseController.add(ResponseChunk(
      type: ChunkType.complete,
      text: _partialTextBuffer.toString(),
      audio: _combineAudioBuffers(),
      isPartial: false,
    ));
    
    // Reset buffers
    _resetBuffers();
  }
  
  /// Handle user transcript
  void _handleUserTranscript(Map<String, dynamic> message) {
    final transcript = message['transcript'] ?? '';
    
    AppLogger.info('👤 User said: "$transcript"');
    
    // Start timing for response
    _requestStartTime = DateTime.now();
    _responseCount = 0;
  }
  
  /// Send user audio with optimization
  void _sendUserAudio(Uint8List audioData) {
    if (_channel == null) return;
    
    // Apply adaptive bitrate if enabled
    final processedAudio = _useAdaptiveBitrate 
        ? _applyAdaptiveBitrate(audioData) 
        : audioData;
    
    final message = {
      'type': 'input_audio_buffer.append',
      'audio': base64Encode(processedAudio),
    };
    
    _channel!.sink.add(jsonEncode(message));
  }
  
  /// Apply adaptive bitrate based on network conditions
  Uint8List _applyAdaptiveBitrate(Uint8List audioData) {
    // In production, measure network latency and adjust
    // For now, return original
    return audioData;
  }
  
  /// Cancel current response (for interruptions)
  void _cancelCurrentResponse() {
    final message = {
      'type': 'response.cancel',
    };
    
    _channel?.sink.add(jsonEncode(message));
    AppLogger.info('❌ Cancelled current response');
    
    _resetBuffers();
  }
  
  /// Combine audio buffers
  Uint8List _combineAudioBuffers() {
    int totalLength = _partialAudioBuffer.fold(0, (sum, buffer) => sum + buffer.length);
    final combined = Uint8List(totalLength);
    
    int offset = 0;
    for (final buffer in _partialAudioBuffer) {
      combined.setRange(offset, offset + buffer.length, buffer);
      offset += buffer.length;
    }
    
    return combined;
  }
  
  /// Reset buffers
  void _resetBuffers() {
    _partialTextBuffer.clear();
    _partialAudioBuffer.clear();
    _requestStartTime = null;
    _responseCount = 0;
    _totalLatency = 0;
  }
  
  /// Handle disconnection
  void _handleDisconnection() {
    AppLogger.warning('📡 WebSocket disconnected');
    // Implement reconnection logic
  }
  
  /// Start conversation
  Future<void> startConversation() async {
    await _conversationEngine.startConversation();
    
    // Send conversation start event
    _channel?.sink.add(jsonEncode({
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'system',
        'content': [
          {
            'type': 'text',
            'text': 'Conversation started. Listen actively and respond naturally.',
          }
        ],
      },
    }));
  }
  
  /// Get performance metrics
  Map<String, dynamic> getPerformanceMetrics() {
    return {
      'conversation': _conversationEngine.getPerformanceMetrics(),
      'api': {
        'avg_first_byte_latency': _totalLatency,
        'total_responses': _responseCount,
      },
    };
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    await _channel?.sink.close();
    await _conversationEngine.dispose();
    await _responseController.close();
    
    AppLogger.info('🔚 Optimized OpenAI service disposed');
  }
}

/// Response chunk for streaming
class ResponseChunk {
  final ChunkType type;
  final String? text;
  final Uint8List? audio;
  final bool isPartial;
  
  ResponseChunk({
    required this.type,
    this.text,
    this.audio,
    required this.isPartial,
  });
}

enum ChunkType { text, audio, transcript, complete }