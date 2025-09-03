import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../core/logger.dart';

/// iOS 전용 WebSocket 서비스
/// iOS에서는 dart:io WebSocket이 헤더와 함께 정상 작동
class IOSWebSocketService {
  WebSocket? _webSocket;
  final String apiKey;
  
  // Stream controllers
  final _connectionStatusController = StreamController<bool>.broadcast();
  final _transcriptController = StreamController<String>.broadcast();
  final _responseController = StreamController<String>.broadcast();
  final _audioDataController = StreamController<Uint8List>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  
  // Public streams
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  Stream<String> get transcriptStream => _transcriptController.stream;
  Stream<String> get responseStream => _responseController.stream;
  Stream<Uint8List> get audioDataStream => _audioDataController.stream;
  Stream<String> get errorStream => _errorController.stream;
  
  bool _isConnected = false;
  String? _sessionId;
  
  IOSWebSocketService() : apiKey = dotenv.env['OPENAI_API_KEY'] ?? '' {
    if (apiKey.isEmpty) {
      AppLogger.error('OpenAI API key not found in environment');
    }
  }
  
  /// Connect to Realtime API (iOS Native)
  Future<bool> connectToRealtimeAPI() async {
    try {
      AppLogger.info('🍎 Connecting to Realtime API on iOS...');
      
      // iOS에서는 dart:io WebSocket이 정상 작동
      _webSocket = await WebSocket.connect(
        'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17',
        headers: {
          'Authorization': 'Bearer $apiKey',
          'OpenAI-Beta': 'realtime=v1',
        },
      );
      
      AppLogger.info('✅ Connected to Realtime API on iOS');
      _isConnected = true;
      _connectionStatusController.add(true);
      
      // Listen to WebSocket events
      _webSocket!.listen(
        _handleServerMessage,
        onError: (error) {
          AppLogger.error('❌ iOS WebSocket error', error);
          _errorController.add('Connection error: $error');
          _handleDisconnection();
        },
        onDone: () {
          AppLogger.info('iOS WebSocket closed');
          _handleDisconnection();
        },
      );
      
      // Send initial session configuration
      await _setupSession();
      
      return true;
    } catch (e) {
      AppLogger.error('❌ iOS connection failed', e);
      _errorController.add('Failed to connect: $e');
      _handleDisconnection();
      return false;
    }
  }
  
  /// Setup session configuration
  Future<void> _setupSession() async {
    final sessionConfig = {
      'type': 'session.update',
      'session': {
        'modalities': ['text', 'audio'],
        'instructions': '''You are an English conversation tutor having a natural conversation with a learner.
Be conversational, friendly, and encouraging.
Keep responses concise (2-3 sentences max).
Correct major errors gently by rephrasing.
Provide positive feedback and encouragement.''',
        'voice': 'alloy',  // Changed from 'nova' - not supported
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
        'temperature': 0.8,
        'max_response_output_tokens': 150,
      }
    };
    
    sendMessage(sessionConfig);
    AppLogger.info('📱 Session configuration sent');
  }
  
  /// Handle server messages
  void _handleServerMessage(dynamic data) {
    try {
      final message = jsonDecode(data);
      final messageType = message['type'];
      
      AppLogger.info('📱 iOS received: $messageType');
      
      switch (messageType) {
        case 'error':
          final error = message['error'];
          AppLogger.error('Server error: ${error['message']}');
          _errorController.add(error['message']);
          break;
          
        case 'session.created':
          _sessionId = message['session']['id'];
          AppLogger.info('Session created: $_sessionId');
          break;
          
        case 'session.updated':
          AppLogger.info('Session updated successfully');
          break;
          
        case 'conversation.item.created':
          final item = message['item'];
          if (item['role'] == 'assistant' && item['type'] == 'message') {
            final content = item['content'];
            if (content != null && content.isNotEmpty) {
              final textContent = content[0];
              if (textContent['type'] == 'text') {
                _responseController.add(textContent['text'] ?? '');
              }
            }
          }
          break;
          
        case 'response.audio.delta':
          final audioDelta = message['delta'];
          if (audioDelta != null) {
            final audioBytes = base64Decode(audioDelta);
            _audioDataController.add(audioBytes);
          }
          break;
          
        case 'response.audio_transcript.delta':
          final textDelta = message['delta'];
          if (textDelta != null) {
            _responseController.add(textDelta);
          }
          break;
          
        case 'conversation.item.input_audio_transcription.completed':
          final transcript = message['transcript'];
          if (transcript != null) {
            _transcriptController.add(transcript);
          }
          break;
          
        case 'response.done':
          AppLogger.info('Response completed');
          break;
          
        case 'rate_limits.updated':
          final limits = message['rate_limits'];
          AppLogger.info('Rate limits: $limits');
          break;
      }
    } catch (e) {
      AppLogger.error('Failed to handle server message', e);
    }
  }
  
  /// Handle disconnection
  void _handleDisconnection() {
    _isConnected = false;
    _connectionStatusController.add(false);
    _sessionId = null;
  }
  
  /// Send message to WebSocket
  void sendMessage(Map<String, dynamic> message) {
    if (_webSocket != null && _isConnected) {
      _webSocket!.add(jsonEncode(message));
      AppLogger.info('📤 Sent: ${message['type']}');
    } else {
      AppLogger.warning('Cannot send message: Not connected');
    }
  }
  
  /// Send audio data
  void sendAudio(Uint8List audioData) {
    if (!_isConnected) {
      AppLogger.warning('Cannot send audio: Not connected');
      return;
    }
    
    final base64Audio = base64Encode(audioData);
    sendMessage({
      'type': 'input_audio_buffer.append',
      'audio': base64Audio,
    });
  }
  
  /// Clear audio buffer
  void clearAudioBuffer() {
    sendMessage({
      'type': 'input_audio_buffer.clear',
    });
  }
  
  /// Commit audio and create response
  void commitAudioAndRespond() {
    sendMessage({
      'type': 'input_audio_buffer.commit',
    });
    
    sendMessage({
      'type': 'response.create',
      'response': {
        'modalities': ['text', 'audio'],
      }
    });
  }
  
  /// Send text message
  void sendText(String text) {
    if (!_isConnected) {
      AppLogger.warning('Cannot send text: Not connected');
      return;
    }
    
    sendMessage({
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text': text,
          }
        ],
      }
    });
    
    sendMessage({
      'type': 'response.create',
    });
  }
  
  /// Test connection
  Future<bool> testConnection() async {
    try {
      AppLogger.info('Testing iOS Realtime API access...');
      
      final testSocket = await WebSocket.connect(
        'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17',
        headers: {
          'Authorization': 'Bearer $apiKey',
          'OpenAI-Beta': 'realtime=v1',
        },
      );
      
      final completer = Completer<bool>();
      
      testSocket.listen(
        (data) {
          final message = jsonDecode(data);
          if (message['type'] == 'session.created') {
            AppLogger.info('✅ iOS Realtime API test successful!');
            completer.complete(true);
          } else if (message['type'] == 'error') {
            AppLogger.error('iOS Realtime API test failed: ${message['error']['message']}');
            completer.complete(false);
          }
        },
        onError: (error) {
          AppLogger.error('iOS test error', error);
          completer.complete(false);
        },
      );
      
      // Send test message
      testSocket.add(jsonEncode({
        'type': 'session.update',
        'session': {
          'modalities': ['text'],
        }
      }));
      
      final result = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
      
      testSocket.close();
      return result;
      
    } catch (e) {
      AppLogger.error('iOS Realtime API test failed', e);
      return false;
    }
  }
  
  /// Check if connected
  bool get isConnected => _isConnected;
  
  /// Get session ID
  String? get sessionId => _sessionId;
  
  /// Close connection
  void close() {
    AppLogger.info('Closing iOS WebSocket connection');
    _webSocket?.close();
    _handleDisconnection();
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    close();
    await _connectionStatusController.close();
    await _transcriptController.close();
    await _responseController.close();
    await _audioDataController.close();
    await _errorController.close();
  }
}