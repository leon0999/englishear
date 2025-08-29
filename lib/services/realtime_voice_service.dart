import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../core/logger.dart';

class RealtimeVoiceService {
  WebSocketChannel? _channel;
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription? _audioStreamSubscription;
  StreamSubscription? _websocketSubscription;
  bool _isConnected = false;
  bool _isRecording = false;
  
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
      Logger.info('Initializing Realtime Voice Service');
      
      final apiKey = dotenv.env['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('OpenAI API key not found');
      }

      _channel = WebSocketChannel.connect(
        Uri.parse('wss://api.openai.com/v1/realtime?model=gpt-4o-realtime-preview-2024-12-17'),
        protocols: ['realtime.openai.com'],
      );

      await _sendAuthMessage(apiKey);
      await _configureSession();
      _listenToResponses();
      
      _isConnected = true;
      _connectionStatusController.add(true);
      
      Logger.info('Realtime Voice Service initialized successfully');
    } catch (e) {
      Logger.error('Failed to initialize Realtime Voice Service', error: e);
      _isConnected = false;
      _connectionStatusController.add(false);
      rethrow;
    }
  }

  Future<void> _sendAuthMessage(String apiKey) async {
    _channel!.sink.add(jsonEncode({
      'type': 'session.update',
      'session': {
        'authorization': 'Bearer $apiKey',
      }
    }));
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
        'voice': 'nova',
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
      Logger.info('Started recording audio');

      _audioStreamSubscription = stream.listen(
        (chunk) {
          if (_isConnected && chunk.isNotEmpty) {
            _sendAudioChunk(chunk);
            _calculateAudioLevel(chunk);
          }
        },
        onError: (error) {
          Logger.error('Audio stream error', error: error);
        },
      );
    } catch (e) {
      Logger.error('Failed to start conversation', error: e);
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
      Logger.info('Stopping conversation');
      
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
      Logger.error('Failed to stop conversation', error: e);
    }
  }

  void _listenToResponses() {
    _websocketSubscription = _channel!.stream.listen(
      (message) {
        try {
          final data = jsonDecode(message);
          _handleWebSocketMessage(data);
        } catch (e) {
          Logger.error('Failed to parse WebSocket message', error: e);
        }
      },
      onError: (error) {
        Logger.error('WebSocket error', error: error);
        _handleDisconnection();
      },
      onDone: () {
        Logger.info('WebSocket connection closed');
        _handleDisconnection();
      },
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
        Logger.info('User started speaking');
        break;
        
      case 'input_audio_buffer.speech_stopped':
        Logger.info('User stopped speaking');
        break;
        
      case 'conversation.item.created':
        if (data['item'] != null) {
          _handleConversationItem(data['item']);
        }
        break;
        
      case 'error':
        Logger.error('Realtime API error', error: data['error']);
        break;
        
      case 'session.created':
        Logger.info('Session created successfully');
        break;
        
      case 'session.updated':
        Logger.info('Session updated successfully');
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
      Logger.error('Failed to play audio chunk', error: e);
    }
  }

  void _handleDisconnection() {
    _isConnected = false;
    _isRecording = false;
    _connectionStatusController.add(false);
    _audioLevelController.add(0.0);
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
    Logger.info('Disposing Realtime Voice Service');
    
    await stopConversation();
    await _audioStreamSubscription?.cancel();
    await _websocketSubscription?.cancel();
    
    _channel?.sink.close();
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