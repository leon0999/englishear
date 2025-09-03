import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:record/record.dart';
// import 'package:audioplayers/audioplayers.dart';  // Removed - using just_audio instead
import 'package:just_audio/just_audio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../core/logger.dart';

class RealtimeVoiceService {
  WebSocketChannel? _channel;
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription? _audioStreamSubscription;
  StreamSubscription? _websocketSubscription;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  bool _isRecording = false;
  bool _isReconnecting = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3;
  
  final _transcriptController = StreamController<String>.broadcast();
  final _responseController = StreamController<String>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();
  final _audioLevelController = StreamController<double>.broadcast();
  
  Stream<String> get transcriptStream => _transcriptController.stream;
  Stream<String> get responseStream => _responseController.stream;
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  Stream<double> get audioLevelStream => _audioLevelController.stream;
  
  bool get isConnected => _isConnected;
  bool get isRecording => _isRecording;

  Future<void> initialize() async {
    try {
      AppLogger.info('Initializing Realtime Voice Service');
      
      // Clean up any existing connection first
      await _cleanup();
      
      final apiKey = dotenv.env['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('OpenAI API key not found');
      }

      // Note: OpenAI Realtime API requires proper authentication headers
      // The WebSocket connection needs to be established with headers
      final headers = {
        'Authorization': 'Bearer $apiKey',
        'OpenAI-Beta': 'realtime=v1',
      };
      
      _channel = WebSocketChannel.connect(
        Uri.parse('wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17'),
      );

      // Wait for connection to be established
      await Future.delayed(Duration(milliseconds: 100));
      await _configureSession();
      _listenToResponses();
      
      _isConnected = true;
      _connectionStatusController.add(true);
      
      AppLogger.info('Realtime Voice Service initialized successfully');
      _reconnectAttempts = 0;  // Reset attempts on successful connection
    } catch (e) {
      AppLogger.error('Failed to initialize Realtime Voice Service', e);
      _isConnected = false;
      _connectionStatusController.add(false);
      _scheduleReconnect();
      rethrow;
    }
  }


  Future<void> _configureSession() async {
    _channel!.sink.add(jsonEncode({
      'type': 'session.update',
      'session': {
        'modalities': ['text', 'audio'],
        'instructions': '''You're an English conversation tutor having a natural conversation with a learner.
        Speak naturally with appropriate pauses and conversational fillers.
        Keep responses concise (2-3 sentences max).
        Correct major errors gently by rephrasing.
        Encourage the learner with positive feedback.''',
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
        'tools': [],
        'tool_choice': 'none',
        'temperature': 0.8,
        'max_response_output_tokens': 4096,
      }
    }));
  }

  Future<void> startConversation() async {
    try {
      if (!_isConnected) {
        await initialize();
      }

      if (!await _recorder.hasPermission()) {
        throw Exception('Microphone permission denied');
      }

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 24000,
          numChannels: 1,
          bitRate: 128000,
        ),
      );

      _isRecording = true;
      AppLogger.info('Started recording audio');

      _audioStreamSubscription = stream.listen(
        (chunk) {
          if (_isConnected && chunk.isNotEmpty) {
            _sendAudioChunk(chunk);
            _calculateAudioLevel(chunk);
          }
        },
        onError: (error) {
          AppLogger.error('Audio stream error', error);
        },
      );
    } catch (e) {
      AppLogger.error('Failed to start conversation', e);
      _isRecording = false;
      rethrow;
    }
  }

  void _sendAudioChunk(Uint8List chunk) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode({
        'type': 'input_audio_buffer.append',
        'audio': base64Encode(chunk),
      }));
    }
  }

  void _calculateAudioLevel(Uint8List chunk) {
    double sum = 0;
    for (int i = 0; i < chunk.length; i += 2) {
      int sample = chunk[i] | (chunk[i + 1] << 8);
      if (sample > 32767) sample = sample - 65536;
      sum += sample.abs();
    }
    double average = sum / (chunk.length / 2);
    double level = (average / 32768).clamp(0.0, 1.0);
    _audioLevelController.add(level);
  }

  Future<void> stopConversation() async {
    try {
      AppLogger.info('Stopping conversation');
      
      await _audioStreamSubscription?.cancel();
      await _recorder.stop();
      
      if (_isConnected && _channel != null) {
        _channel!.sink.add(jsonEncode({
          'type': 'input_audio_buffer.commit',
        }));
      }
      
      _isRecording = false;
      _audioLevelController.add(0.0);
    } catch (e) {
      AppLogger.error('Failed to stop conversation', e);
    }
  }

  void _listenToResponses() {
    // Cancel any existing subscription first
    _websocketSubscription?.cancel();
    
    // Use asBroadcastStream to allow multiple listeners if needed
    final broadcastStream = _channel!.stream.asBroadcastStream();
    
    _websocketSubscription = broadcastStream.listen(
      (message) {
        try {
          final data = jsonDecode(message);
          _handleWebSocketMessage(data);
        } catch (e) {
          AppLogger.error('Failed to parse WebSocket message', e);
        }
      },
      onError: (error) {
        AppLogger.error('WebSocket error', error);
        _handleDisconnection();
      },
      onDone: () {
        AppLogger.info('WebSocket connection closed');
        _handleDisconnection();
      },
      cancelOnError: false,
    );
  }

  void _handleWebSocketMessage(Map<String, dynamic> data) {
    switch (data['type']) {
      case 'response.audio.delta':
        if (data['delta'] != null) {
          _playAudioChunk(base64Decode(data['delta']));
        }
        break;
        
      case 'response.audio_transcript.delta':
        if (data['delta'] != null) {
          _responseController.add(data['delta']);
        }
        break;
        
      case 'response.audio_transcript.done':
        if (data['transcript'] != null) {
          _responseController.add('\n[Complete: ${data['transcript']}]\n');
        }
        break;
        
      case 'input_audio_buffer.speech_started':
        AppLogger.info('User started speaking');
        break;
        
      case 'input_audio_buffer.speech_stopped':
        AppLogger.info('User stopped speaking');
        break;
        
      case 'conversation.item.created':
        if (data['item'] != null) {
          _handleConversationItem(data['item']);
        }
        break;
        
      case 'error':
        AppLogger.error('Realtime API error', data['error']);
        break;
        
      case 'session.created':
        AppLogger.info('Session created successfully');
        _isConnected = true;
        _connectionStatusController.add(true);
        break;
        
      case 'session.updated':
        AppLogger.info('Session updated successfully');
        break;
    }
  }

  void _handleConversationItem(Map<String, dynamic> item) {
    if (item['role'] == 'user' && item['content'] != null) {
      for (var content in item['content']) {
        if (content['type'] == 'input_audio' && content['transcript'] != null) {
          _transcriptController.add(content['transcript']);
        }
      }
    }
  }

  Future<void> _playAudioChunk(Uint8List audioData) async {
    try {
      if (audioData.isEmpty) return;
      
      await _audioPlayer.play(
        BytesSource(audioData),
        mode: PlayerMode.lowLatency,
      );
    } catch (e) {
      AppLogger.error('Failed to play audio chunk', e);
    }
  }

  void _handleDisconnection() {
    _isConnected = false;
    _isRecording = false;
    _connectionStatusController.add(false);
    _audioLevelController.add(0.0);
    _scheduleReconnect();
  }
  
  void _scheduleReconnect() {
    if (_isReconnecting || _reconnectAttempts >= _maxReconnectAttempts) {
      if (_reconnectAttempts >= _maxReconnectAttempts) {
        AppLogger.error('Max reconnection attempts reached');
      }
      return;
    }
    
    _isReconnecting = true;
    _reconnectAttempts++;
    
    final delay = Duration(seconds: _reconnectAttempts * 2);
    AppLogger.info('Attempting reconnection $_reconnectAttempts/$_maxReconnectAttempts in ${delay.inSeconds}s');
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      _isReconnecting = false;
      try {
        await initialize();
      } catch (e) {
        AppLogger.error('Reconnection attempt $_reconnectAttempts failed', e);
      }
    });
  }
  
  Future<void> _cleanup() async {
    _reconnectTimer?.cancel();
    await _websocketSubscription?.cancel();
    await _audioStreamSubscription?.cancel();
    _channel?.sink.close();
    _websocketSubscription = null;
    _audioStreamSubscription = null;
    _channel = null;
  }

  Future<void> sendTextMessage(String message) async {
    if (!_isConnected || _channel == null) {
      throw Exception('Not connected to Realtime API');
    }

    _channel!.sink.add(jsonEncode({
      'type': 'conversation.item.create',
      'item': {
        'type': 'message',
        'role': 'user',
        'content': [
          {
            'type': 'input_text',
            'text': message,
          }
        ],
      }
    }));

    _channel!.sink.add(jsonEncode({
      'type': 'response.create',
    }));
  }

  Future<void> dispose() async {
    AppLogger.info('Disposing Realtime Voice Service');
    
    await stopConversation();
    await _cleanup();
    _reconnectTimer?.cancel();
    
    await _recorder.dispose();
    await _audioPlayer.dispose();
    
    await _transcriptController.close();
    await _responseController.close();
    await _connectionStatusController.close();
    await _audioLevelController.close();
    
    _isConnected = false;
    _isRecording = false;
  }
}