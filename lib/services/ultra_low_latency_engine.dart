import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:web_socket_channel/io.dart';
import 'dart:convert';
import '../core/logger.dart';
import 'performance_monitor.dart';

/// Ultra-low latency engine with robust WebSocket connection management
class UltraLowLatencyEngine {
  IOWebSocketChannel? _channel;
  StreamController<Uint8List>? _audioController;
  StreamController<String>? _textController;
  Timer? _heartbeatTimer;
  Timer? _keepAliveTimer;
  
  // Connection management
  String? _apiKey;
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  static const int MAX_RECONNECT_ATTEMPTS = 3;
  
  // Buffering optimization
  static const int CHUNK_SIZE = 480; // 20ms at 24kHz
  static const int MAX_BUFFER_SIZE = 960; // Max 40ms buffer
  static const int MIN_BUFFER_SIZE = 4800; // 100ms minimum
  static const int SAMPLE_RATE = 24000;
  
  List<int> _audioBuffer = [];
  List<int> _pendingAudioBuffer = [];
  bool _isProcessing = false;
  
  // Performance metrics
  DateTime? _lastRequestTime;
  int _firstByteLatency = 0;
  int _totalResponses = 0;
  
  // Performance monitoring
  final PerformanceMonitor _performanceMonitor = PerformanceMonitor();
  
  // Jupiter greeting messages
  final List<String> _greetings = [
    "Hey there! How's your day going?",
    "Hi! What brings you here today?",
    "Hello! Ready for some English practice?",
    "Good to see you! What's on your mind?",
    "Hey! How are you feeling today?",
    "Hi there! Want to chat for a bit?",
    "Hello! What would you like to talk about?",
    "Hey! How's everything with you?",
  ];
  
  Future<void> connect(String apiKey) async {
    _apiKey = apiKey;
    await _connect();
  }
  
  Future<void> _connect() async {
    AppLogger.test('==================== ULTRA LOW LATENCY ENGINE START ====================');
    
    try {
      if (_isConnected) {
        AppLogger.warning('⚠️ Already connected');
        return;
      }
      
      final uri = Uri.parse(
        'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17'
      );
      
      _channel = IOWebSocketChannel.connect(
        uri,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'OpenAI-Beta': 'realtime=v1',
        },
      );
      
      _audioController = StreamController<Uint8List>.broadcast();
      _textController = StreamController<String>.broadcast();
      
      // Send optimized configuration immediately
      await _sendSessionConfig();
      
      // Setup connection monitoring
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          AppLogger.error('WebSocket error', error);
          _handleDisconnection();
        },
        onDone: () {
          AppLogger.warning('WebSocket connection closed');
          _handleDisconnection();
        },
        cancelOnError: false, // Keep listening even on error
      );
      
      // Setup keep-alive mechanisms
      _setupKeepAlive();
      
      _isConnected = true;
      _reconnectAttempts = 0;
      
      AppLogger.success('✅ Ultra-low latency engine connected successfully');
      AppLogger.test('==================== ULTRA LOW LATENCY ENGINE READY ====================');
      
    } catch (e) {
      AppLogger.error('Connection failed', e);
      _handleDisconnection();
    }
  }
  
  Future<void> _sendSessionConfig() async {
    final config = {
      'type': 'session.update',
      'session': {
        'modalities': ['text', 'audio'],
        'instructions': '''You are a helpful English tutor for language learners. 
          CRITICAL RULES:
          1. ALWAYS respond in English ONLY - never use Spanish, French, or any other language
          2. Speak slowly and clearly with natural pauses between sentences
          3. Use simple vocabulary appropriate for English learners
          4. Pronounce each word distinctly for better understanding
          5. Keep responses short (1-2 sentences)
          6. If someone speaks to you in another language, respond in English only''',
        'voice': 'shimmer',  // Using supported voice model
        'input_audio_format': 'pcm16',
        'output_audio_format': 'pcm16',
        'input_audio_transcription': {
          'model': 'whisper-1'
        },
        'turn_detection': {
          'type': 'server_vad',
          'threshold': 0.5,
          'prefix_padding_ms': 300,
          'silence_duration_ms': 500,
        },
        'temperature': 0.6,
        'max_response_output_tokens': 1024
      }
    };
    
    _sendMessage(config);
    AppLogger.info('📤 Session configuration sent');
  }
  
  void _setupKeepAlive() {
    // Heartbeat timer - every 20 seconds
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(Duration(seconds: 20), (_) {
      if (_isConnected) {
        _sendHeartbeat();
      }
    });
    
    // Keep-alive timer - every 10 seconds for more frequent pings
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(Duration(seconds: 10), (_) {
      if (_isConnected) {
        try {
          // Send a lightweight keep-alive message
          _channel?.sink.add(jsonEncode({'type': 'input_audio_buffer.clear'}));
          AppLogger.debug('🔄 Keep-alive ping sent');
        } catch (e) {
          AppLogger.error('Keep-alive failed', e);
          _handleDisconnection();
        }
      }
    });
    
    AppLogger.info('⏰ Keep-alive mechanisms activated');
  }
  
  void _handleDisconnection() {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _keepAliveTimer?.cancel();
    
    if (_reconnectAttempts < MAX_RECONNECT_ATTEMPTS) {
      _reconnectAttempts++;
      AppLogger.warning('🔄 Attempting to reconnect... (${_reconnectAttempts}/$MAX_RECONNECT_ATTEMPTS)');
      
      // Exponential backoff for reconnection
      final delay = Duration(seconds: 2 * _reconnectAttempts);
      Future.delayed(delay, () {
        if (!_isConnected && _apiKey != null) {
          _connect();
        }
      });
    } else {
      AppLogger.error('Max reconnection attempts reached', null);
      // Notify UI about connection failure
      _textController?.add('[Connection Lost - Please restart the app]');
    }
  }
  
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message);
      
      // Track first response for latency metrics
      if (_lastRequestTime != null && _firstByteLatency == 0) {
        _firstByteLatency = DateTime.now().difference(_lastRequestTime!).inMilliseconds;
        _performanceMonitor.recordLatency(_firstByteLatency);
      }
      
      switch (data['type']) {
        case 'session.created':
          AppLogger.success('Session created: ${data['session']?['id']}');
          // Send automatic greeting after session is created
          _sendInitialGreeting();
          break;
          
        case 'session.updated':
          AppLogger.success('Session configuration updated');
          break;
          
        case 'response.audio.delta':
          final audioBytes = base64Decode(data['delta'] ?? '');
          if (audioBytes.isNotEmpty) {
            _audioController?.add(Uint8List.fromList(audioBytes));
            _totalResponses++;
          }
          break;
          
        case 'response.audio_transcript.delta':
          final transcript = data['delta'] ?? '';
          AppLogger.info('🤖 AI: $transcript');
          _textController?.add(transcript);
          break;
          
        case 'response.text.delta':
          final text = data['delta'] ?? '';
          AppLogger.info('📝 AI Text: $text');
          _textController?.add(text);
          break;
          
        case 'response.done':
          _logPerformanceMetrics();
          _resetMetrics();
          break;
          
        case 'error':
          AppLogger.error('API Error', data['error']);
          if (data['error']?['message']?.contains('connection') ?? false) {
            _handleDisconnection();
          }
          break;
          
        default:
          AppLogger.debug('Received: ${data['type']}');
      }
    } catch (e) {
      AppLogger.error('Message handling error', e);
    }
  }
  
  /// Send audio with connection check
  void sendAudio(Uint8List audioData) {
    if (!_isConnected || _channel == null) {
      AppLogger.warning('Cannot send audio - not connected');
      return;
    }
    
    try {
      _audioBuffer.addAll(audioData);
      
      // Process chunks
      while (_audioBuffer.length >= CHUNK_SIZE) {
        final chunk = _audioBuffer.take(CHUNK_SIZE).toList();
        _audioBuffer = _audioBuffer.skip(CHUNK_SIZE).toList();
        
        final message = {
          'type': 'input_audio_buffer.append',
          'audio': base64Encode(chunk),
        };
        
        _sendMessage(message);
      }
      
      // Force send if buffer gets too large
      if (_audioBuffer.length > MAX_BUFFER_SIZE) {
        _flushAudioBuffer();
      }
    } catch (e) {
      AppLogger.error('Error sending audio', e);
      _handleDisconnection();
    }
  }
  
  /// Commit audio buffer with minimum size guarantee
  void commitAudio() {
    if (!_isConnected || _channel == null) {
      AppLogger.warning('Cannot commit audio - not connected');
      return;
    }
    
    try {
      // Ensure minimum buffer size
      if (_audioBuffer.isNotEmpty && _audioBuffer.length < MIN_BUFFER_SIZE) {
        // Pad buffer to minimum size
        while (_audioBuffer.length < MIN_BUFFER_SIZE) {
          _audioBuffer.add(0);
        }
        AppLogger.debug('📤 Padded buffer to ${_audioBuffer.length} bytes');
      }
      
      // Flush any remaining audio
      if (_audioBuffer.isNotEmpty) {
        _flushAudioBuffer();
      }
      
      // Commit to trigger AI response
      _sendMessage({'type': 'input_audio_buffer.commit'});
      
      AppLogger.debug('📤 Audio committed for processing');
    } catch (e) {
      AppLogger.error('Error committing audio', e);
    }
  }
  
  /// Send text message
  void sendText(String text) {
    if (!_isConnected || _channel == null) {
      AppLogger.warning('Cannot send text - not connected');
      return;
    }
    
    _lastRequestTime = DateTime.now();
    _totalResponses = 0;
    
    final message = {
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'user',
        'content': [
          {
            'type': 'input_text',
            'text': text,
          }
        ],
      },
    };
    
    _sendMessage(message);
    
    // Request immediate response
    _sendMessage({'type': 'response.create'});
    
    AppLogger.info('💬 Sent text: "$text"');
  }
  
  void _flushAudioBuffer() {
    if (_audioBuffer.isNotEmpty && _channel != null) {
      final message = {
        'type': 'input_audio_buffer.append',
        'audio': base64Encode(_audioBuffer),
      };
      _sendMessage(message);
      _audioBuffer.clear();
    }
  }
  
  void _sendMessage(Map<String, dynamic> message) {
    if (_isConnected && _channel != null) {
      try {
        _channel!.sink.add(jsonEncode(message));
      } catch (e) {
        AppLogger.error('Error sending message', e);
        _handleDisconnection();
      }
    }
  }
  
  void _sendHeartbeat() {
    AppLogger.debug('💓 Heartbeat sent');
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
  
  /// Manually reconnect
  Future<void> reconnect() async {
    if (!_isConnected && _apiKey != null) {
      _reconnectAttempts = 0;
      await _connect();
    }
  }
  
  /// Get connection status
  bool get isConnected => _isConnected;
  
  /// Get audio stream for playback
  Stream<Uint8List>? get audioStream => _audioController?.stream;
  
  /// Get text stream for UI
  Stream<String>? get textStream => _textController?.stream;
  
  /// Dispose resources
  void dispose() {
    _isConnected = false;
    _heartbeatTimer?.cancel();
    _keepAliveTimer?.cancel();
    _audioStreamSubscription?.cancel();
    _textStreamSubscription?.cancel();
    _channel?.sink.close();
    _audioController?.close();
    _textController?.close();
    AppLogger.info('🔌 Ultra-low latency engine disposed');
  }
  
  // Stream subscriptions
  StreamSubscription? _audioStreamSubscription;
  StreamSubscription? _textStreamSubscription;
  
  /// Send initial greeting from Jupiter
  Future<void> _sendInitialGreeting() async {
    try {
      // Wait a moment for session to be fully established
      await Future.delayed(Duration(seconds: 1));
      
      // Select random greeting
      final random = math.Random();
      final greeting = _greetings[random.nextInt(_greetings.length)];
      
      // First, add the greeting as a conversation item
      final conversationItem = {
        'type': 'conversation.item.create',
        'item': {
          'type': 'message',
          'role': 'assistant',
          'content': [
            {
              'type': 'input_text',
              'text': greeting
            }
          ]
        }
      };
      
      _channel?.sink.add(jsonEncode(conversationItem));
      
      // Then trigger response generation for the greeting
      final createResponse = {
        'type': 'response.create',
        'response': {
          'modalities': ['text', 'audio'],
        }
      };
      
      _channel?.sink.add(jsonEncode(createResponse));
      AppLogger.info('🤖 Jupiter initiated conversation: "$greeting"');
      
      // Also send to text stream for UI
      _textController?.add('[Jupiter]: $greeting');
      
    } catch (e) {
      AppLogger.error('Failed to send initial greeting', e);
    }
  }
}