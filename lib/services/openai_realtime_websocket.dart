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
  
  // Jupiter AI state and callbacks
  String _currentAiTranscript = '';
  Function(String)? onAiTranscriptUpdate;
  Function(String)? onSpeakingStateChange;
  
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
      if (apiKey.isEmpty) {
        throw Exception('OpenAI API key not found in environment');
      }
      
      AppLogger.info('🔗 Connecting to OpenAI Realtime API...');
      AppLogger.info('API key present: ${apiKey.substring(0, 10)}...');
      
      // Use platform-specific WebSocket implementation
      if (Platform.isIOS || Platform.isAndroid) {
        // iOS/Android: Use dart:io WebSocket with headers
        _iosWebSocket = await WebSocket.connect(
          'wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17',
          headers: {
            'Authorization': 'Bearer $apiKey',
            'OpenAI-Beta': 'realtime=v1',
          },
        ).timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Connection timeout');
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
        'modalities': ['text', 'audio'],  // Both text and audio for Jupiter AI
        'instructions': '''You are Jupiter, a friendly and engaging AI English conversation partner.
Your role is to help users practice English through natural conversation.

IMPORTANT RULES:
1. Keep responses concise (1-2 sentences) for natural conversation flow
2. Ask follow-up questions to keep the conversation going
3. Gently correct grammar mistakes by using the correct form naturally
4. Be encouraging and supportive
5. Speak at a moderate pace for language learners
6. Use common, everyday vocabulary
7. Use casual fillers like "um", "well" occasionally for naturalness''',
        'voice': 'alloy',  // Most natural sounding voice
        'input_audio_format': 'pcm16',
        'output_audio_format': 'pcm16',
        'input_audio_transcription': {
          'model': 'whisper-1'
        },
        'turn_detection': {
          'type': 'server_vad',
          'threshold': 0.5,  // Balanced threshold for learners
          'prefix_padding_ms': 300,
          'silence_duration_ms': 700,  // Natural pause for learners
        },
        'temperature': 0.8,  // Good variety in responses
        'max_response_output_tokens': 150,  // Concise but complete responses
      }
    });
    
    AppLogger.info('ℹ️ Session update sent with text+audio modalities for Jupiter AI');
    
    // Clear input audio buffer to start fresh
    _sendEvent({
      'type': 'input_audio_buffer.clear',
      // 'auth' parameter removed - not supported by API
    });
  }
  
  /// Send event to WebSocket (public method for external use)
  void sendEvent(Map<String, dynamic> event) => _sendEvent(event);
  
  /// Send event to WebSocket (internal)
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
          AppLogger.info('✅ Session created: $_sessionId');
          
          // Clear transcript when new session starts
          _currentAiTranscript = '';
          onAiTranscriptUpdate?.call('');
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
          if (item['role'] == 'assistant') {
            // Jupiter AI response started
            AppLogger.info('🤖 Jupiter is responding...');
            _updateSpeakingState('ai');
          }
          break;
          
        case 'response.audio.delta':
          // Audio chunk received from Jupiter
          final audioDelta = event['delta'];
          if (audioDelta != null) {
            final audioBytes = base64Decode(audioDelta);
            _audioDataController.add(audioBytes);
            AppLogger.debug('🔊 Playing audio: ${audioBytes.length} bytes');
          }
          break;
          
        case 'response.audio_transcript.delta':
          // Jupiter's response text delta
          final transcript = event['delta'] ?? '';
          _currentAiTranscript += transcript;
          _updateAiTranscript(_currentAiTranscript);
          break;
          
        case 'response.audio_transcript.done':
          // Complete Jupiter transcript
          final fullTranscript = event['transcript'] ?? '';
          AppLogger.info('🤖 [Jupiter]: $fullTranscript');
          _updateAiTranscript(fullTranscript);
          _currentAiTranscript = '';
          break;
          
        case 'conversation.item.input_audio_transcription.completed':
          // Ignore user transcript to prevent text display
          AppLogger.debug('User speech detected but transcript ignored');
          break;
          
        case 'input_audio_buffer.speech_started':
          // User started speaking - important for interruption handling
          AppLogger.info('🎙️ User started speaking');
          _handleUserSpeechStarted();
          _updateSpeakingState('user');
          break;
          
        case 'input_audio_buffer.speech_stopped':
          // User stopped speaking
          AppLogger.info('🤐 User stopped speaking');
          _updateSpeakingState('idle');
          break;
          
        case 'response.done':
          AppLogger.info('✅ Response completed');
          _updateSpeakingState('idle');
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
    AppLogger.info('🎙️ User speech started - sending interrupt signal');
    _audioDataController.add(Uint8List(0));  // Send empty data as stop signal
  }
  
  /// Update AI transcript for UI display
  void _updateAiTranscript(String transcript) {
    onAiTranscriptUpdate?.call(transcript);
  }
  
  /// Update speaking state for UI
  void _updateSpeakingState(String state) {
    // 'user', 'ai', 'idle' states
    onSpeakingStateChange?.call(state);
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
            'type': 'input_text',
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
  
  /// Start conversation with Jupiter greeting
  void startConversationWithGreeting() {
    if (!_isConnected) {
      AppLogger.warning('Cannot start conversation: Not connected');
      return;
    }
    
    // Send a request for Jupiter to start the conversation
    sendText('Please start the conversation by greeting me in a friendly way.');
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