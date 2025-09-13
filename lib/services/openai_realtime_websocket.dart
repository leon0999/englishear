import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io' show WebSocket, Platform;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../core/logger.dart';
import 'improved_audio_service.dart';
import 'streaming_audio_service.dart';
import 'conversation_enhancer.dart';

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
  Function()? onResponseCompleted; // Added callback for response completion
  
  // Public streams
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  Stream<String> get transcriptStream => _transcriptController.stream;
  Stream<String> get responseStream => _responseController.stream;
  Stream<Uint8List> get audioDataStream => _audioDataController.stream;
  Stream<String> get errorStream => _errorController.stream;
  
  // Connection state
  bool _isConnected = false;
  String? _sessionId;
  bool _isResponseInProgress = false;  // Flag to prevent duplicate responses
  
  // Audio buffer tracking
  static const int MIN_AUDIO_BUFFER_SIZE = 4800; // 100ms at 24kHz (minimum required)
  int _currentBufferSize = 0; // Track current buffer size
  bool _isAISpeaking = false; // Track AI speaking state
  
  // Audio service for processing
  ImprovedAudioService? _audioService;
  
  // Enhanced audio streaming service
  final StreamingAudioService _streamingService = StreamingAudioService();
  
  // Conversation enhancer for natural dialogue
  final ConversationEnhancer _conversationEnhancer = ConversationEnhancer();
  
  OpenAIRealtimeWebSocket() : apiKey = dotenv.env['OPENAI_API_KEY'] ?? '' {
    if (apiKey.isEmpty) {
      AppLogger.error('OpenAI API key not found in environment');
    }
    _audioService = ImprovedAudioService();
    _audioService?.initialize();
    _streamingService.initialize();
  }
  
  /// Check if WebSocket is connected
  bool get isConnected {
    if (_iosWebSocket != null) {
      return _isConnected && _iosWebSocket?.readyState == WebSocket.open;
    } else if (_channel != null) {
      return _isConnected;
    }
    return false;
  }
  
  /// Reset response state (called when app pauses)
  void resetResponseState() {
    AppLogger.test('Resetting WebSocket response state');
    _isResponseInProgress = false;
    _currentAiTranscript = '';
    onSpeakingStateChange?.call('idle');
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
        'instructions': '''You are Jupiter, a warm and friendly English conversation partner.

SPEAKING STYLE:
- SPEAK VERY SLOWLY AND CLEARLY, as if talking to someone learning English
- Add natural pauses between phrases and sentences
- Use a warm, encouraging, and expressive tone with emotion
- Speak with natural rhythm and intonation variations
- Include occasional conversational fillers like "um", "well", "you know"

CONVERSATION RULES:
1. Keep responses short (1-2 sentences) for natural flow
2. Ask follow-up questions to maintain engagement
3. Gently correct mistakes by using the correct form naturally
4. Be supportive and encouraging
5. Use simple, everyday vocabulary
6. Express emotions through your voice (excitement, curiosity, warmth)

IMPORTANT: Take your time speaking. Pause naturally between thoughts. Speak as if you're carefully explaining to a friend.''',
        'voice': 'alloy',  // More natural and expressive voice
        'input_audio_format': 'pcm16',
        'output_audio_format': 'pcm16',
        'input_audio_transcription': {
          'model': 'whisper-1'
        },
        'turn_detection': {
          'type': 'server_vad',
          'threshold': 0.8,  // Higher threshold to avoid interruptions
          'prefix_padding_ms': 800,  // More padding for learners
          'silence_duration_ms': 2000,  // Longer pause for learners to think
        },
        'temperature': 0.85,  // More natural variety
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
          _isAISpeaking = true; // AI is speaking
          final audioDelta = event['delta'];
          if (audioDelta != null && audioDelta.isNotEmpty) {
            // Decode audio data
            final audioData = base64Decode(audioDelta);
            
            // Stream directly for minimal latency (ChatGPT Voice style)
            _streamingService.addAudioData(audioData);
            
            AppLogger.debug('🎧 Streaming audio chunk: ${audioData.length} bytes');
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
          _handleUserSpeechStopped();
          _updateSpeakingState('idle');
          break;
          
        case 'input_audio_buffer.committed':
          // Audio buffer committed - ensure speaking state is reset
          AppLogger.debug('Audio buffer committed - resetting speaking state');
          _handleUserSpeechStopped();  // Safety reset
          break;
          
        case 'response.done':
          AppLogger.info('✅ Response completed');
          _isResponseInProgress = false;  // Reset flag when response is done
          _isAISpeaking = false; // AI finished speaking
          
          // Flush any remaining audio
          _streamingService.flush();
          
          _updateSpeakingState('idle');
          onResponseCompleted?.call(); // Notify audio service
          break;
          
        case 'response.audio.done':
          AppLogger.info('🔇 Audio playback completed');
          _isAISpeaking = false; // AI finished speaking audio
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
  
  /// Handle user speech stopped event
  void _handleUserSpeechStopped() {
    // Signal to audio service that user has stopped speaking
    AppLogger.info('🎯 User speech stopped - signaling to audio service');
    // This will be handled by the audio service's onResponseCompleted callback
    onResponseCompleted?.call();
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
    
    // Don't send audio if AI is speaking
    if (_isAISpeaking) {
      AppLogger.warning('Cannot send audio: AI is speaking');
      return;
    }
    
    // Track buffer size
    _currentBufferSize += audioData.length;
    
    final base64Audio = base64Encode(audioData);
    _sendEvent({
      'type': 'input_audio_buffer.append',
      'audio': base64Audio,
    });
    
    AppLogger.debug('📤 Audio appended to buffer (${audioData.length} bytes, total: $_currentBufferSize bytes)');
  }
  
  /// Alias for sendAudio for better API clarity
  void sendAudioData(Uint8List audioData) => sendAudio(audioData);
  
  /// Clear audio buffer
  void clearAudioBuffer() {
    _currentBufferSize = 0; // Reset buffer size tracking
    _sendEvent({
      'type': 'input_audio_buffer.clear',
    });
    AppLogger.debug('🗑️ Audio buffer cleared');
  }
  
  /// Commit audio buffer and create response
  void commitAudioAndRespond() {
    // Check if buffer has minimum required size
    if (_currentBufferSize < MIN_AUDIO_BUFFER_SIZE) {
      AppLogger.warning('Buffer too small ($_currentBufferSize bytes < $MIN_AUDIO_BUFFER_SIZE bytes), clearing instead of committing');
      clearAudioBuffer();
      return;
    }
    
    // Commit the audio buffer
    _sendEvent({
      'type': 'input_audio_buffer.commit',
    });
    
    AppLogger.info('📤 Audio buffer committed ($_currentBufferSize bytes)');
    _currentBufferSize = 0; // Reset after commit
    
    // Create response only if not already in progress
    if (!_isResponseInProgress) {
      _isResponseInProgress = true;
      _sendEvent({
        'type': 'response.create',
        'response': {
          'modalities': ['text', 'audio'],
        }
      });
    } else {
      AppLogger.info('⏳ Response already in progress, skipping duplicate request');
    }
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
    
    // Create response only if not already in progress
    if (!_isResponseInProgress) {
      _isResponseInProgress = true;
      _sendEvent({
        'type': 'response.create',
      });
    } else {
      AppLogger.info('⏳ Response already in progress, skipping duplicate request');
    }
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