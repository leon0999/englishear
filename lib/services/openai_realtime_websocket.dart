import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show WebSocket, Platform;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../core/logger.dart';

/// OpenAI Realtime API WebSocket Service
/// Provides real-time voice conversation using GPT-4 Realtime model
class OpenAIRealtimeWebSocket {
  WebSocketChannel? _channel;
  WebSocket? _iosWebSocket;  // iOS-specific WebSocket
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
      
      // Use platform-specific WebSocket implementation
      if (Platform.isIOS || Platform.isAndroid) {
        // iOS/Android: Use dart:io WebSocket with headers
        _iosWebSocket = await WebSocket.connect(
          'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17',
          headers: {
            'Authorization': 'Bearer $apiKey',
            'OpenAI-Beta': 'realtime=v1',
          },
        );
        
        AppLogger.info('✅ Connected to Realtime API (iOS/Android)');
        _isConnected = true;
        _connectionStatusController.add(true);
        
        // Listen to WebSocket events
        _iosWebSocket!.listen(
          (data) => _handleServerEvent(data),
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
      } else {
        // Web: Use WebSocketChannel (headers not supported)
        _channel = WebSocketChannel.connect(
          Uri.parse('wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17'),
        );
        
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
      }
      
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
    // Send session update with natural conversation settings
    _sendEvent({
      'type': 'session.update',
      'session': {
        'modalities': ['audio'],  // Audio only - no text display
        'instructions': '''You are a friendly native English speaker having a casual conversation.
Speak naturally like a real person would in everyday conversation.
Use casual language, fillers like "um", "well", "you know" occasionally.
Vary your speaking pace and intonation naturally.
Keep responses concise and conversational (1-2 sentences).
Don't sound robotic or overly formal.
React naturally to what the user says with appropriate emotions.''',
        'voice': 'alloy',  // Most natural sounding voice
        'input_audio_format': 'pcm16',
        'output_audio_format': 'pcm16',
        'input_audio_transcription': {
          'model': 'whisper-1'
        },
        'turn_detection': {
          'type': 'server_vad',
          'threshold': 0.7,  // Higher threshold for better detection
          'prefix_padding_ms': 300,
          'silence_duration_ms': 1000,  // Natural pause duration
        },
        'temperature': 0.9,  // More variety in responses
        'max_response_output_tokens': 100,  // Shorter, more natural responses
      }
    });
    
    // Clear input audio buffer to start fresh
    _sendEvent({
      'type': 'input_audio_buffer.clear',
      // 'auth' parameter removed - not supported by API
    });
  }
  
  /// Send event to WebSocket
  void _sendEvent(Map<String, dynamic> event) {
    try {
      final jsonEvent = jsonEncode(event);
      
      if (_iosWebSocket != null) {
        // iOS/Android: Send via dart:io WebSocket
        _iosWebSocket!.add(jsonEvent);
        AppLogger.info('Sent event (iOS): ${event['type']}');
      } else if (_channel != null) {
        // Web: Send via WebSocketChannel
        _channel!.sink.add(jsonEvent);
        AppLogger.info('Sent event (Web): ${event['type']}');
      } else {
        AppLogger.error('Cannot send event: WebSocket not connected');
        return;
      }
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
          // Ignore user items to prevent echo
          if (item['role'] == 'user') {
            AppLogger.info('Ignoring user conversation item to prevent echo');
            return;
          }
          if (item['role'] == 'assistant' && item['type'] == 'message') {
            // AI response started - audio only, no text
            AppLogger.info('AI response started (audio only)');
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
          // Ignore transcript to prevent text display
          AppLogger.debug('Ignoring audio transcript delta');
          break;
          
        case 'response.audio_transcript.done':
          // Ignore transcript to prevent text display
          AppLogger.debug('Ignoring audio transcript done');
          break;
          
        case 'conversation.item.input_audio_transcription.completed':
          // Ignore user transcript to prevent text display
          AppLogger.debug('User speech detected but transcript ignored');
          break;
          
        case 'input_audio_buffer.speech_started':
          // User started speaking - important for interruption handling
          AppLogger.info('User started speaking');
          _handleUserSpeechStarted();
          break;
          
        case 'input_audio_buffer.speech_stopped':
          // User stopped speaking
          AppLogger.info('User stopped speaking');
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
  
  /// Handle user speech started event
  void _handleUserSpeechStarted() {
    // Signal to audio service to stop AI playback
    // This prevents AI echo when user interrupts
    _audioDataController.add(Uint8List(0));  // Send empty data as stop signal
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
  
  /// Alias for sendAudio for better API clarity
  void sendAudioData(Uint8List audioData) => sendAudio(audioData);
  
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
      
      if (Platform.isIOS || Platform.isAndroid) {
        // iOS/Android test with headers
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
            final event = jsonDecode(data);
            if (event['type'] == 'session.created') {
              AppLogger.info('✅ Realtime API test successful!');
              completer.complete(true);
            } else if (event['type'] == 'error') {
              AppLogger.error('Realtime API test failed: ${event['error']['message']}');
              completer.complete(false);
            }
          },
          onError: (error) {
            AppLogger.error('Test connection error', error);
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
      } else {
        // Web test (limited)
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
      }
      
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
    _iosWebSocket?.close();
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