import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:record/record.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import '../core/logger.dart';

class AccurateSpeechService {
  final AudioRecorder _recorder = AudioRecorder();
  List<int> _audioBuffer = [];
  Timer? _silenceTimer;
  Timer? _vadTimer;
  bool _isRecording = false;
  bool _isUserSpeaking = false;
  double _lastAudioLevel = 0.0;
  int _silenceCounter = 0;
  
  final _transcriptionController = StreamController<String>.broadcast();
  final _audioLevelController = StreamController<double>.broadcast();
  final _recordingStatusController = StreamController<bool>.broadcast();
  
  Stream<String> get transcriptionStream => _transcriptionController.stream;
  Stream<double> get audioLevelStream => _audioLevelController.stream;
  Stream<bool> get recordingStatusStream => _recordingStatusController.stream;
  
  static const double SILENCE_THRESHOLD = 0.02;
  static const int SILENCE_DURATION_MS = 1500;
  static const int VAD_CHECK_INTERVAL_MS = 100;

  Future<String> recordAndTranscribe({
    String? language = 'en',
    bool enablePunctuation = true,
  }) async {
    try {
      Logger.info('Starting recording for transcription');
      
      if (!await _recorder.hasPermission()) {
        throw Exception('Microphone permission denied');
      }

      final tempDir = await getTemporaryDirectory();
      final audioPath = '${tempDir.path}/temp_audio_${DateTime.now().millisecondsSinceEpoch}.wav';
      
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          bitRate: 128000,
          numChannels: 1,
        ),
        path: audioPath,
      );
      
      _isRecording = true;
      _recordingStatusController.add(true);
      _startVoiceActivityDetection();
      
      final result = await _waitForSpeechCompletion();
      
      if (!result) {
        await _recorder.stop();
        throw Exception('No speech detected');
      }
      
      final path = await _recorder.stop();
      _isRecording = false;
      _recordingStatusController.add(false);
      
      if (path == null) {
        throw Exception('Failed to save audio recording');
      }
      
      final audioFile = File(path);
      final audioBytes = await audioFile.readAsBytes();
      
      final transcription = await _transcribeWithWhisper(
        audioBytes,
        language: language,
        enablePunctuation: enablePunctuation,
      );
      
      await audioFile.delete();
      
      Logger.info('Transcription completed: $transcription');
      return transcription;
      
    } catch (e) {
      Logger.error('Failed to record and transcribe', error: e);
      _isRecording = false;
      _recordingStatusController.add(false);
      rethrow;
    }
  }

  Future<String> _transcribeWithWhisper(
    Uint8List audioData, {
    String? language = 'en',
    bool enablePunctuation = true,
  }) async {
    try {
      final apiKey = dotenv.env['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('OpenAI API key not found');
      }

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
          contentType: MediaType('audio', 'wav'),
        ),
      );
      
      request.fields['model'] = 'whisper-1';
      if (language != null) {
        request.fields['language'] = language;
      }
      request.fields['response_format'] = 'verbose_json';
      
      if (enablePunctuation) {
        request.fields['prompt'] = 'Please include proper punctuation and capitalization.';
      }
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode != 200) {
        throw Exception('Whisper API error: ${response.body}');
      }
      
      final result = jsonDecode(response.body);
      
      if (result['text'] == null || result['text'].isEmpty) {
        throw Exception('No transcription available');
      }
      
      _transcriptionController.add(result['text']);
      
      if (result['duration'] != null && result['duration'] > 0) {
        Logger.info('Audio duration: ${result['duration']}s');
      }
      
      return result['text'];
      
    } catch (e) {
      Logger.error('Whisper transcription failed', error: e);
      rethrow;
    }
  }

  void _startVoiceActivityDetection() {
    _vadTimer?.cancel();
    _silenceCounter = 0;
    _isUserSpeaking = false;
    
    _vadTimer = Timer.periodic(Duration(milliseconds: VAD_CHECK_INTERVAL_MS), (timer) async {
      if (!_isRecording) {
        timer.cancel();
        return;
      }
      
      final amplitude = await _recorder.getAmplitude();
      final normalizedLevel = _normalizeAmplitude(amplitude.current);
      
      _audioLevelController.add(normalizedLevel);
      _lastAudioLevel = normalizedLevel;
      
      if (normalizedLevel > SILENCE_THRESHOLD) {
        _isUserSpeaking = true;
        _silenceCounter = 0;
        _resetSilenceTimer();
      } else if (_isUserSpeaking) {
        _silenceCounter++;
        
        if (_silenceCounter * VAD_CHECK_INTERVAL_MS >= SILENCE_DURATION_MS) {
          Logger.info('Silence detected, stopping recording');
          _vadTimer?.cancel();
          _silenceTimer?.cancel();
        }
      }
    });
  }

  double _normalizeAmplitude(double amplitude) {
    if (amplitude.isInfinite || amplitude.isNaN) {
      return 0.0;
    }
    
    const double minDb = -45.0;
    const double maxDb = 0.0;
    
    final clampedDb = amplitude.clamp(minDb, maxDb);
    final normalized = (clampedDb - minDb) / (maxDb - minDb);
    
    return normalized.clamp(0.0, 1.0);
  }

  void _resetSilenceTimer() {
    _silenceTimer?.cancel();
    _silenceTimer = Timer(Duration(milliseconds: SILENCE_DURATION_MS), () {
      if (_isRecording && _isUserSpeaking) {
        Logger.info('Silence timer triggered');
        _vadTimer?.cancel();
      }
    });
  }

  Future<bool> _waitForSpeechCompletion() async {
    final completer = Completer<bool>();
    int checkCount = 0;
    const maxChecks = 300; // 30 seconds max
    
    Timer.periodic(Duration(milliseconds: 100), (timer) {
      checkCount++;
      
      if (!_isRecording || !_isUserSpeaking && _silenceCounter * VAD_CHECK_INTERVAL_MS >= SILENCE_DURATION_MS) {
        timer.cancel();
        completer.complete(_isUserSpeaking || _lastAudioLevel > SILENCE_THRESHOLD);
      } else if (checkCount >= maxChecks) {
        timer.cancel();
        completer.complete(true);
      }
    });
    
    return completer.future;
  }

  Future<void> startContinuousRecording() async {
    if (_isRecording) return;
    
    try {
      if (!await _recorder.hasPermission()) {
        throw Exception('Microphone permission denied');
      }

      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          bitRate: 128000,
        ),
      );

      _isRecording = true;
      _recordingStatusController.add(true);
      _audioBuffer.clear();
      
      stream.listen(
        (chunk) {
          _audioBuffer.addAll(chunk);
          _processAudioChunk(chunk);
        },
        onError: (error) {
          Logger.error('Audio stream error', error: error);
        },
      );
      
      _startVoiceActivityDetection();
      
    } catch (e) {
      Logger.error('Failed to start continuous recording', error: e);
      rethrow;
    }
  }

  void _processAudioChunk(Uint8List chunk) {
    double sum = 0;
    for (int i = 0; i < chunk.length; i += 2) {
      int sample = chunk[i] | (chunk[i + 1] << 8);
      if (sample > 32767) sample = sample - 65536;
      sum += sample.abs();
    }
    double average = sum / (chunk.length / 2);
    double level = (average / 32768).clamp(0.0, 1.0);
    
    _audioLevelController.add(level);
    
    if (level > SILENCE_THRESHOLD) {
      _isUserSpeaking = true;
      _resetSilenceTimer();
    }
  }

  Future<String> stopAndTranscribe() async {
    if (!_isRecording) {
      throw Exception('Not recording');
    }
    
    try {
      await _recorder.stop();
      _isRecording = false;
      _recordingStatusController.add(false);
      
      if (_audioBuffer.isEmpty) {
        throw Exception('No audio data captured');
      }
      
      final audioData = Uint8List.fromList(_audioBuffer);
      _audioBuffer.clear();
      
      return await _transcribeWithWhisper(audioData);
      
    } catch (e) {
      Logger.error('Failed to stop and transcribe', error: e);
      rethrow;
    }
  }

  Future<void> dispose() async {
    Logger.info('Disposing Accurate Speech Service');
    
    _vadTimer?.cancel();
    _silenceTimer?.cancel();
    
    if (_isRecording) {
      await _recorder.stop();
    }
    
    await _recorder.dispose();
    
    await _transcriptionController.close();
    await _audioLevelController.close();
    await _recordingStatusController.close();
    
    _audioBuffer.clear();
    _isRecording = false;
    _isUserSpeaking = false;
  }
}