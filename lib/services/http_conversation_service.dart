import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import '../core/logger.dart';

/// HTTP-based conversation service using OpenAI Chat API
/// Replaces WebSocket Realtime API with stable HTTP endpoints
class HTTPConversationService {
  final String apiKey;
  final List<Map<String, String>> conversationHistory = [];
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // Stream controllers for UI updates
  final _transcriptController = StreamController<String>.broadcast();
  final _responseController = StreamController<String>.broadcast();
  final _audioLevelController = StreamController<double>.broadcast();
  final _connectionStatusController = StreamController<bool>.broadcast();
  
  Stream<String> get transcriptStream => _transcriptController.stream;
  Stream<String> get responseStream => _responseController.stream;
  Stream<double> get audioLevelStream => _audioLevelController.stream;
  Stream<bool> get connectionStatusStream => _connectionStatusController.stream;
  
  bool _isRecording = false;
  bool _isProcessing = false;
  StreamSubscription? _audioStreamSubscription;
  List<int> _audioBuffer = [];
  Timer? _silenceTimer;
  
  HTTPConversationService() : apiKey = dotenv.env['OPENAI_API_KEY'] ?? '' {
    if (apiKey.isEmpty) {
      AppLogger.error('OpenAI API key not found in environment');
    }
  }
  
  /// Initialize the service
  Future<void> initialize() async {
    try {
      AppLogger.info('Initializing HTTP Conversation Service');
      
      // Add system message for conversation context
      conversationHistory.clear();
      conversationHistory.add({
        'role': 'system',
        'content': '''You are an English conversation tutor having a natural conversation with a learner.
        Be conversational, friendly, and encouraging.
        Keep responses concise (2-3 sentences max).
        Correct major errors gently by rephrasing.
        Provide positive feedback and encouragement.'''
      });
      
      _connectionStatusController.add(true);
      AppLogger.info('HTTP Conversation Service initialized successfully');
    } catch (e) {
      AppLogger.error('Failed to initialize HTTP Conversation Service', e);
      _connectionStatusController.add(false);
      rethrow;
    }
  }
  
  /// Start recording audio for conversation
  Future<void> startRecording() async {
    try {
      if (_isRecording) {
        AppLogger.warning('Already recording');
        return;
      }
      
      if (!await _recorder.hasPermission()) {
        throw Exception('Microphone permission denied');
      }
      
      _audioBuffer.clear();
      
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 128000,
        ),
      );
      
      _isRecording = true;
      AppLogger.info('Started recording audio');
      
      _audioStreamSubscription = stream.listen(
        (chunk) {
          _audioBuffer.addAll(chunk);
          _calculateAudioLevel(chunk);
          _detectSilence();
        },
        onError: (error) {
          AppLogger.error('Audio stream error', error);
          stopRecording();
        },
      );
    } catch (e) {
      AppLogger.error('Failed to start recording', e);
      _isRecording = false;
      rethrow;
    }
  }
  
  /// Stop recording and process the audio
  Future<void> stopRecording() async {
    try {
      if (!_isRecording) return;
      
      AppLogger.info('Stopping recording');
      
      await _audioStreamSubscription?.cancel();
      await _recorder.stop();
      
      _isRecording = false;
      _audioLevelController.add(0.0);
      _silenceTimer?.cancel();
      
      if (_audioBuffer.isNotEmpty && !_isProcessing) {
        await _processAudioBuffer();
      }
    } catch (e) {
      AppLogger.error('Failed to stop recording', e);
    }
  }
  
  /// Process recorded audio buffer
  Future<void> _processAudioBuffer() async {
    if (_audioBuffer.isEmpty || _isProcessing) return;
    
    _isProcessing = true;
    
    try {
      AppLogger.info('Processing audio buffer (${_audioBuffer.length} bytes)');
      
      // Convert audio buffer to Uint8List
      final audioData = Uint8List.fromList(_audioBuffer);
      _audioBuffer.clear();
      
      // Transcribe audio using Whisper
      final transcript = await transcribeAudio(audioData);
      if (transcript.isEmpty) {
        AppLogger.warning('Empty transcript received');
        return;
      }
      
      _transcriptController.add(transcript);
      AppLogger.info('Transcript: $transcript');
      
      // Get AI response
      final response = await sendMessage(transcript);
      _responseController.add(response);
      AppLogger.info('AI Response: $response');
      
      // Generate and play speech
      final speechData = await generateSpeech(response);
      await _playAudio(speechData);
      
    } catch (e) {
      AppLogger.error('Failed to process audio', e);
      _responseController.add('Sorry, I encountered an error. Please try again.');
    } finally {
      _isProcessing = false;
    }
  }
  
  /// Detect silence to auto-stop recording
  void _detectSilence() {
    _silenceTimer?.cancel();
    
    _silenceTimer = Timer(const Duration(seconds: 2), () {
      if (_isRecording && !_isProcessing) {
        AppLogger.info('Silence detected, auto-stopping recording');
        stopRecording();
      }
    });
  }
  
  /// Calculate audio level for visualization
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
  
  /// Send message to OpenAI Chat API
  Future<String> sendMessage(String userInput) async {
    if (userInput.trim().isEmpty) return '';
    
    try {
      conversationHistory.add({'role': 'user', 'content': userInput});
      
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'gpt-3.5-turbo',  // Changed from gpt-4 for cost efficiency
          'messages': conversationHistory,
          'temperature': 0.8,
          'max_tokens': 150,
          'stream': false,
        }),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final aiResponse = data['choices'][0]['message']['content'];
        conversationHistory.add({'role': 'assistant', 'content': aiResponse});
        return aiResponse;
      } else {
        AppLogger.error('Chat API error: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to get AI response');
      }
    } catch (e) {
      AppLogger.error('Failed to send message', e);
      rethrow;
    }
  }
  
  /// Transcribe audio using Whisper API
  Future<String> transcribeAudio(Uint8List audioData) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.openai.com/v1/audio/transcriptions'),
      );
      
      request.headers['Authorization'] = 'Bearer $apiKey';
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          audioData,
          filename: 'audio.wav',
        ),
      );
      request.fields['model'] = 'whisper-1';
      request.fields['language'] = 'en';
      
      final streamedResponse = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['text'] ?? '';
      } else {
        AppLogger.error('Whisper API error: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to transcribe audio');
      }
    } catch (e) {
      AppLogger.error('Failed to transcribe audio', e);
      rethrow;
    }
  }
  
  /// Generate speech using TTS API
  Future<Uint8List> generateSpeech(String text) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/audio/speech'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'tts-1-hd',
          'input': text,
          'voice': 'nova',
          'response_format': 'mp3',
        }),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        AppLogger.error('TTS API error: ${response.statusCode}');
        throw Exception('Failed to generate speech');
      }
    } catch (e) {
      AppLogger.error('Failed to generate speech', e);
      rethrow;
    }
  }
  
  /// Play audio data
  Future<void> _playAudio(Uint8List audioData) async {
    try {
      if (audioData.isEmpty) return;
      
      await _audioPlayer.play(
        BytesSource(audioData),
        mode: PlayerMode.lowLatency,
      );
      
      AppLogger.info('Playing audio response');
    } catch (e) {
      AppLogger.error('Failed to play audio', e);
    }
  }
  
  /// Send text message directly (without recording)
  Future<void> sendTextMessage(String message) async {
    if (message.trim().isEmpty || _isProcessing) return;
    
    _isProcessing = true;
    
    try {
      _transcriptController.add(message);
      
      final response = await sendMessage(message);
      _responseController.add(response);
      
      final speechData = await generateSpeech(response);
      await _playAudio(speechData);
    } catch (e) {
      AppLogger.error('Failed to send text message', e);
      _responseController.add('Sorry, I encountered an error. Please try again.');
    } finally {
      _isProcessing = false;
    }
  }
  
  /// Clear conversation history
  void clearHistory() {
    conversationHistory.clear();
    conversationHistory.add({
      'role': 'system',
      'content': '''You are an English conversation tutor having a natural conversation with a learner.
        Be conversational, friendly, and encouraging.
        Keep responses concise (2-3 sentences max).
        Correct major errors gently by rephrasing.
        Provide positive feedback and encouragement.'''
    });
    AppLogger.info('Conversation history cleared');
  }
  
  /// Check if service is ready
  bool get isReady => apiKey.isNotEmpty;
  bool get isRecording => _isRecording;
  bool get isProcessing => _isProcessing;
  
  /// Dispose resources
  Future<void> dispose() async {
    AppLogger.info('Disposing HTTP Conversation Service');
    
    await stopRecording();
    await _audioStreamSubscription?.cancel();
    _silenceTimer?.cancel();
    
    await _recorder.dispose();
    await _audioPlayer.dispose();
    
    await _transcriptController.close();
    await _responseController.close();
    await _audioLevelController.close();
    await _connectionStatusController.close();
  }
}