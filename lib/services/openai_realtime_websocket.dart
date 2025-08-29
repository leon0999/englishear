import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../core/logger.dart';

/// OpenAI Realtime API WebSocket Service
/// Provides real-time voice conversation using GPT-4 Realtime model
class OpenAIRealtimeWebSocket {
  WebSocketChannel? _channel;
  final String apiKey;
  
  // Stream controllers for UI updates
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
  
  // Connection state
  bool _isConnected = false;
  String? _sessionId;
  
  OpenAIRealtimeWebSocket() : apiKey = dotenv.env['OPENAI_API_KEY'] ?? '' {
    if (apiKey.isEmpty) {
      AppLogger.error('OpenAI API key not found in environment');
    }
  }
  
  /// Connect to OpenAI Realtime WebSocket
  Future<void> connect() async {
    try {
      AppLogger.info('Connecting to OpenAI Realtime API...');
      
      // Create WebSocket connection
      _channel = WebSocketChannel.connect(
        Uri.parse('wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17'),
      );
      
      // Add authentication headers via subprotocol (web limitation)
      // Note: In web, headers cannot be set directly, we'll send auth after connection
      
      // Listen to WebSocket events
      _channel!.stream.listen(
        _handleServerEvent,
        onError: (error) {
          AppLogger.error('WebSocket error', error);
          _errorController.add('Connection error: $error');
          _handleDisconnection();
        },
        onDone: () {
          AppLogger.info('WebSocket connection closed');
          _handleDisconnection();
        },
      );
      
      // Send authentication and session setup
      await _setupSession();
      
    } catch (e) {
      AppLogger.error('Failed to connect to Realtime API', e);
      _errorController.add('Failed to connect: $e');
      _handleDisconnection();
      rethrow;
    }
  }
  
  /// Setup session with authentication
  Future<void> _setupSession() async {
    // Send session update with auth token
    _sendEvent({
      'type': 'session.update',
      'session': {
        'modalities': ['text', 'audio'],
        'instructions': '''You are an English conversation tutor having a natural conversation with a learner.
Be conversational, friendly, and encouraging.
Keep responses concise (2-3 sentences max).
Correct major errors gently by rephrasing.
Provide positive feedback and encouragement.''',
        'voice': 'nova',  // Natural female voice
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
    });
    
    // Add auth header in first message (workaround for web)
    _sendEvent({
      'type': 'input_audio_buffer.clear',
      'auth': apiKey,  // Send API key
    });
  }
  
  /// Send event to WebSocket
  void _sendEvent(Map<String, dynamic> event) {
    if (_channel == null) {
      AppLogger.error('Cannot send event: WebSocket not connected');
      return;
    }
    
    try {
      final jsonEvent = jsonEncode(event);
      _channel!.sink.add(jsonEvent);
      AppLogger.info('Sent event: ${event['type']}');
    } catch (e) {
      AppLogger.error('Failed to send event', e);
    }
  }
  
  /// Handle server events
  void _handleServerEvent(dynamic message) {
    try {
      final event = jsonDecode(message);
      final eventType = event['type'];
      
      AppLogger.info('Received event: $eventType');
      
      switch (eventType) {
        case 'error':
          final error = event['error'];
          AppLogger.error('Server error: ${error['message']}');
          _errorController.add(error['message']);
          
          // Check if it's an auth error
          if (error['code'] == 'invalid_api_key' || error['code'] == 'unauthorized') {
            _handleAuthError();
          }
          break;
          
        case 'session.created':
          _sessionId = event['session']['id'];
          _isConnected = true;
          _connectionStatusController.add(true);
          AppLogger.info('Session created: $_sessionId');
          break;
          
        case 'session.updated':
          AppLogger.info('Session updated successfully');
          break;
          
        case 'conversation.item.created':
          final item = event['item'];
          if (item['role'] == 'assistant' && item['type'] == 'message') {
            // AI response started
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
          // Audio chunk received
          final audioDelta = event['delta'];
          if (audioDelta != null) {
            final audioBytes = base64Decode(audioDelta);
            _audioDataController.add(audioBytes);
          }
          break;
          
        case 'response.audio_transcript.delta':
          // Transcript chunk received
          final textDelta = event['delta'];
          if (textDelta != null) {
            _responseController.add(textDelta);
          }
          break;
          
        case 'response.audio_transcript.done':
          // Complete transcript received
          final transcript = event['transcript'];
          if (transcript != null) {
            _responseController.add(transcript);
          }
          break;
          
        case 'conversation.item.input_audio_transcription.completed':
          // User's speech transcribed
          final transcript = event['transcript'];
          if (transcript != null) {
            _transcriptController.add(transcript);
          }
          break;
          
        case 'response.done':
          AppLogger.info('Response completed');
          break;
          
        case 'rate_limits.updated':
          final limits = event['rate_limits'];
          AppLogger.info('Rate limits: $limits');
          break;
      }
    } catch (e) {
      AppLogger.error('Failed to handle server event', e);
    }
  }
  
  /// Handle authentication error
  void _handleAuthError() {
    AppLogger.error('Authentication failed - API key may be invalid or lacks Realtime API access');
    _errorController.add('Realtime API access denied. Falling back to HTTP API.');
    disconnect();
  }
  
  /// Handle disconnection
  void _handleDisconnection() {
    _isConnected = false;
    _connectionStatusController.add(false);
    _sessionId = null;
  }
  
  /// Send audio data
  void sendAudio(Uint8List audioData) {
    if (!_isConnected) {
      AppLogger.warning('Cannot send audio: Not connected');
      return;
    }
    
    final base64Audio = base64Encode(audioData);
    _sendEvent({
      'type': 'input_audio_buffer.append',
      'audio': base64Audio,
    });
  }
  
  /// Clear audio buffer
  void clearAudioBuffer() {
    _sendEvent({
      'type': 'input_audio_buffer.clear',
    });
  }
  
  /// Commit audio buffer and create response
  void commitAudioAndRespond() {
    // Commit the audio buffer
    _sendEvent({
      'type': 'input_audio_buffer.commit',
    });
    
    // Create response
    _sendEvent({
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
    
    _sendEvent({
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
    
    // Create response
    _sendEvent({
      'type': 'response.create',
    });
  }
  
  /// Test connection
  Future<bool> testConnection() async {
    try {
      AppLogger.info('Testing Realtime API access...');
      
      final testChannel = WebSocketChannel.connect(
        Uri.parse('wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17'),
      );
      
      // Send test auth
      testChannel.sink.add(jsonEncode({
        'type': 'session.update',
        'auth': apiKey,
      }));
      
      // Wait for response
      final completer = Completer<bool>();
      
      testChannel.stream.listen(
        (message) {
          final event = jsonDecode(message);
          if (event['type'] == 'error') {
            AppLogger.error('Realtime API test failed: ${event['error']['message']}');
            completer.complete(false);
          } else if (event['type'] == 'session.created') {
            AppLogger.info('Realtime API test successful!');
            completer.complete(true);
          }
        },
        onError: (error) {
          AppLogger.error('Realtime API test error', error);
          completer.complete(false);
        },
      );
      
      // Timeout after 5 seconds
      final result = await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => false,
      );
      
      testChannel.sink.close();
      return result;
      
    } catch (e) {
      AppLogger.error('Realtime API test failed', e);
      return false;
    }
  }
  
  /// Check if connected
  bool get isConnected => _isConnected;
  
  /// Disconnect from WebSocket
  void disconnect() {
    AppLogger.info('Disconnecting from Realtime API');
    _channel?.sink.close();
    _handleDisconnection();
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    disconnect();
    await _connectionStatusController.close();
    await _transcriptController.close();
    await _responseController.close();
    await _audioDataController.close();
    await _errorController.close();
  }
}