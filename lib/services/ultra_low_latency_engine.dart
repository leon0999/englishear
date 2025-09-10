import 'dart:async';
import 'dart:typed_data';
import 'package:web_socket_channel/io.dart';
import 'dart:convert';
import '../core/logger.dart';
import 'performance_monitor.dart';

/// Ultra-low latency engine for real-time conversation
/// Target: < 200ms end-to-end latency like Moshi AI
class UltraLowLatencyEngine {
  IOWebSocketChannel? _channel;
  StreamController<Uint8List>? _audioController;
  StreamController<String>? _textController;
  Timer? _heartbeatTimer;
  
  // Buffering optimization for minimal latency
  static const int CHUNK_SIZE = 480; // 20ms at 24kHz
  static const int MAX_BUFFER_SIZE = 960; // Max 40ms buffer
  static const int SAMPLE_RATE = 24000;
  
  List<int> _audioBuffer = [];
  bool _isProcessing = false;
  bool _isConnected = false;
  
  // Performance metrics
  DateTime? _lastRequestTime;
  int _firstByteLatency = 0;
  int _totalResponses = 0;
  
  // Performance monitoring
  final PerformanceMonitor _performanceMonitor = PerformanceMonitor();
  
  Future<void> connect(String apiKey) async {
    AppLogger.test('==================== ULTRA LOW LATENCY ENGINE START ====================');
    
    try {
      final uri = Uri.parse(
        'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17'
      );
      
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'OpenAI-Beta': 'realtime=v1',
        },
        pingInterval: Duration(seconds: 20),
      );
      
      _audioController = StreamController<Uint8List>.broadcast();
      _textController = StreamController<String>.broadcast();
      
      // Send optimized configuration for minimum latency with slower speech
      final config = {
        'type': 'session.update',
        'session': {
          'modalities': ['text', 'audio'],
          'instructions': '''You are a helpful English tutor for language learners. 
          IMPORTANT: Speak slowly and clearly with natural pauses between sentences. 
          Use simple vocabulary and short sentences. 
          Pronounce each word distinctly for better understanding.
          Keep responses concise and educational.''',
          'voice': 'nova',  // Changed from 'alloy' to 'nova' for clearer pronunciation
          'input_audio_format': 'pcm16',
          'output_audio_format': 'pcm16',
          'input_audio_transcription': {
            'model': 'whisper-1'
          },
          'turn_detection': {
            'type': 'server_vad',
            'threshold': 0.5,
            'prefix_padding_ms': 300,     // Increased for better speech detection
            'silence_duration_ms': 500,   // Increased for natural conversation flow
          },
          'temperature': 0.6,  // Lower temperature for more consistent responses
          'max_response_output_tokens': 1024  // Keep responses concise
        }
      };
      
      _channel!.sink.add(jsonEncode(config));
      
      // Start performance monitoring for connection
      _performanceMonitor.startOperation('websocket_connect');
      
      // Handle messages with minimal processing
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          AppLogger.error('WebSocket error', error);
          _reconnect();
        },
        onDone: () {
          AppLogger.warning('WebSocket connection closed');
          _reconnect();
        },
      );
      
      // Heartbeat to maintain connection
      _heartbeatTimer = Timer.periodic(Duration(seconds: 30), (_) {
        _sendHeartbeat();
      });
      
      _isConnected = true;
      AppLogger.success('✅ Ultra-low latency engine connected');
      AppLogger.test('==================== ULTRA LOW LATENCY ENGINE READY ====================');
      
    } catch (e) {
      AppLogger.error('Connection failed', e);
      throw e;
    }
  }
  
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      
      switch (data['type']) {
        case 'session.created':
          AppLogger.success('📱 Session created successfully');
          _performanceMonitor.endOperation('websocket_connect', category: 'connection');
          break;
          
        case 'response.audio.delta':
          // Decode and stream audio immediately for minimal latency
          if (data['delta'] != null) {
            final audioBytes = base64Decode(data['delta']);
            _audioController?.add(Uint8List.fromList(audioBytes));
            
            // Track first byte latency
            if (_lastRequestTime != null && _totalResponses == 0) {
              _firstByteLatency = DateTime.now().difference(_lastRequestTime!).inMilliseconds;
              AppLogger.success('🎯 First byte latency: ${_firstByteLatency}ms');
              _performanceMonitor.endOperation('first_byte_response', category: 'audio');
            }
            _totalResponses++;
            
            // Record audio metric
            _performanceMonitor.recordAudioMetric(
              operation: 'audio_delta',
              audioSizeBytes: audioBytes.length,
              processingTimeMs: _firstByteLatency,
              audioQuality: 1.0,
            );
          }
          break;
          
        case 'response.audio_transcript.delta':
          // Stream text in real-time
          if (data['delta'] != null) {
            _textController?.add(data['delta']);
            AppLogger.info('🤖 AI: ${data['delta']}');
          }
          break;
          
        case 'response.done':
          _logPerformanceMetrics();
          _resetMetrics();
          break;
          
        case 'conversation.item.input_audio_transcription.completed':
          final transcript = data['transcript'] ?? '';
          AppLogger.info('👤 User: "$transcript"');
          _lastRequestTime = DateTime.now();
          _totalResponses = 0;
          _performanceMonitor.startOperation('first_byte_response');
          break;
          
        case 'error':
          final errorMsg = data['error']?.toString() ?? 'Unknown error';
          AppLogger.error('API Error: $errorMsg');
          
          // 세션 업데이트 에러인 경우 다시 시도
          if (errorMsg.contains('Unknown parameter')) {
            AppLogger.warning('Retrying with simplified configuration...');
            _sendSimplifiedConfig();
          }
          break;
          
        case 'session.updated':
          AppLogger.success('✅ Session configuration updated successfully');
          break;
      }
    } catch (e) {
      AppLogger.error('Message handling error', e);
    }
  }
  
  /// Send audio with minimal buffering for ultra-low latency
  void sendAudio(Uint8List audioData) {
    if (!_isConnected || _channel == null) return;
    
    // Add to buffer
    _audioBuffer.addAll(audioData);
    
    // Send immediately when we have enough data (20ms chunk)
    while (_audioBuffer.length >= CHUNK_SIZE) {
      final chunk = _audioBuffer.take(CHUNK_SIZE).toList();
      _audioBuffer = _audioBuffer.skip(CHUNK_SIZE).toList();
      
      final message = {
        'type': 'input_audio_buffer.append',
        'audio': base64Encode(chunk),
      };
      
      _channel!.sink.add(jsonEncode(message));
    }
    
    // Force send if buffer gets too large
    if (_audioBuffer.length > MAX_BUFFER_SIZE) {
      _flushAudioBuffer();
    }
  }
  
  /// Commit audio buffer to trigger response
  void commitAudio() {
    // Flush any remaining audio
    _flushAudioBuffer();
    
    // Commit to trigger AI response
    _channel?.sink.add(jsonEncode({'type': 'input_audio_buffer.commit'}));
    
    AppLogger.debug('📤 Audio committed for processing');
  }
  
  /// Send text message for faster text-based interaction
  void sendText(String text) {
    if (!_isConnected || _channel == null) return;
    
    _lastRequestTime = DateTime.now();
    _totalResponses = 0;
    
    final message = {
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'user',
        'content': [
          {
            'type': 'input_text',  // Changed from 'text' to 'input_text'
            'text': text,
          }
        ],
      },
    };
    
    _channel!.sink.add(jsonEncode(message));
    
    // Trigger response immediately
    _channel!.sink.add(jsonEncode({'type': 'response.create'}));
    
    AppLogger.info('💬 Sent text: "$text"');
  }
  
  void _flushAudioBuffer() {
    if (_audioBuffer.isNotEmpty && _channel != null) {
      final message = {
        'type': 'input_audio_buffer.append',
        'audio': base64Encode(_audioBuffer),
      };
      _channel!.sink.add(jsonEncode(message));
      _audioBuffer.clear();
    }
  }
  
  void _sendHeartbeat() {
    if (_isConnected && _channel != null) {
      // OpenAI doesn't require explicit ping, but we can send empty message
      AppLogger.debug('💓 Heartbeat sent');
    }
  }
  
  void _logPerformanceMetrics() {
    if (_lastRequestTime != null) {
      final totalLatency = DateTime.now().difference(_lastRequestTime!).inMilliseconds;
      AppLogger.success('📊 Performance Metrics:');
      AppLogger.success('  • First byte: ${_firstByteLatency}ms');
      AppLogger.success('  • Total latency: ${totalLatency}ms');
      AppLogger.success('  • Response chunks: $_totalResponses');
      
      if (_firstByteLatency < 200) {
        AppLogger.success('  ✅ Achieved Moshi AI level latency!');
      }
    }
  }
  
  void _resetMetrics() {
    _lastRequestTime = null;
    _firstByteLatency = 0;
    _totalResponses = 0;
  }
  
  void _sendSimplifiedConfig() {
    // 간소화된 설정 - 문제가 될 수 있는 파라미터 제거
    final simplifiedConfig = {
      'type': 'session.update',
      'session': {
        'modalities': ['text', 'audio'],
        'instructions': 'You are a helpful English tutor. Respond quickly and naturally.',
        'voice': 'alloy',
        'input_audio_format': 'pcm16',
        'output_audio_format': 'pcm16',
        'turn_detection': {
          'type': 'server_vad',
          'threshold': 0.5,
          'silence_duration_ms': 200,
        },
        'temperature': 0.7,
      }
    };
    
    if (_channel != null) {
      _channel!.sink.add(jsonEncode(simplifiedConfig));
      AppLogger.info('📤 Sent simplified configuration');
    }
  }
  
  Future<void> _reconnect() async {
    if (!_isConnected) return;
    
    AppLogger.warning('🔄 Attempting to reconnect...');
    _isConnected = false;
    
    await Future.delayed(Duration(seconds: 2));
    
    // Note: In production, store API key securely and retrieve here
    // For now, reconnection needs to be handled by the caller
  }
  
  /// Get audio stream for playback
  Stream<Uint8List>? get audioStream => _audioController?.stream;
  
  /// Get text stream for display
  Stream<String>? get textStream => _textController?.stream;
  
  /// Check connection status
  bool get isConnected => _isConnected;
  
  /// Disconnect and cleanup
  void dispose() {
    AppLogger.info('🔚 Disposing ultra-low latency engine');
    
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _channel?.sink.close();
    _audioController?.close();
    _textController?.close();
    _audioBuffer.clear();
    
    AppLogger.test('==================== ULTRA LOW LATENCY ENGINE DISPOSED ====================');
  }
}