import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
// import 'package:audioplayers/audioplayers.dart';  // Removed - using just_audio instead

import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../core/logger.dart';

enum TTSVoice {
  alloy('alloy', 'Neutral, balanced'),
  echo('echo', 'Smooth, calm'),
  fable('fable', 'Expressive, dynamic'),
  onyx('onyx', 'Deep, authoritative'),
  nova('nova', 'Warm, friendly'),
  shimmer('shimmer', 'Soft, gentle');

  final String value;
  final String description;
  const TTSVoice(this.value, this.description);
}

enum TTSEmotion {
  neutral('neutral', 1.0),
  excited('excited', 1.1),
  thoughtful('thoughtful', 0.9),
  questioning('questioning', 0.95),
  encouraging('encouraging', 1.05),
  gentle('gentle', 0.85);

  final String value;
  final double speedMultiplier;
  const TTSEmotion(this.value, this.speedMultiplier);
}

class TextSegment {
  final String text;
  final TTSEmotion emotion;
  final double? customSpeed;

  TextSegment({
    required this.text,
    this.emotion = TTSEmotion.neutral,
    this.customSpeed,
  });
}

class NaturalTTSService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Queue<Uint8List> _audioQueue = Queue();
  final Queue<TextSegment> _textQueue = Queue();
  
  bool _isPlaying = false;
  bool _isPaused = false;
  double _globalSpeed = 1.0;
  TTSVoice _currentVoice = TTSVoice.nova;
  
  final _playbackStatusController = StreamController<bool>.broadcast();
  final _currentTextController = StreamController<String>.broadcast();
  final _queueSizeController = StreamController<int>.broadcast();
  
  Stream<bool> get playbackStatusStream => _playbackStatusController.stream;
  Stream<String> get currentTextStream => _currentTextController.stream;
  Stream<int> get queueSizeStream => _queueSizeController.stream;
  
  bool get isPlaying => _isPlaying;
  bool get isPaused => _isPaused;
  int get queueSize => _audioQueue.length;

  NaturalTTSService() {
    _audioPlayer.onPlayerComplete.listen((_) {
      _isPlaying = false;
      _playNextInQueue();
    });
  }

  Future<void> speakWithEmotion(
    String text, {
    TTSVoice? voice,
    double speed = 1.0,
    TTSEmotion? emotion,
    bool clearQueue = false,
  }) async {
    try {
      if (clearQueue) {
        await clearAudioQueue();
      }

      _globalSpeed = speed;
      if (voice != null) {
        _currentVoice = voice;
      }

      final segments = _analyzeTextSegments(text, defaultEmotion: emotion);
      
      for (final segment in segments) {
        await _generateAndQueueSegment(segment);
      }
      
      _playNextInQueue();
      
    } catch (e) {
      Logger.error('Failed to speak with emotion', error: e);
      rethrow;
    }
  }

  Future<void> _generateAndQueueSegment(TextSegment segment) async {
    try {
      final apiKey = dotenv.env['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception('OpenAI API key not found');
      }

      final adjustedSpeed = _calculateAdjustedSpeed(segment);
      
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/audio/speech'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'tts-1-hd',
          'input': segment.text,
          'voice': _currentVoice.value,
          'response_format': 'opus',
          'speed': adjustedSpeed,
        }),
      );
      
      if (response.statusCode == 200) {
        _audioQueue.add(response.bodyBytes);
        _textQueue.add(segment);
        _queueSizeController.add(_audioQueue.length);
        Logger.info('Audio segment queued: ${segment.text.substring(0, segment.text.length.clamp(0, 30))}...');
      } else {
        throw Exception('TTS API error: ${response.body}');
      }
      
    } catch (e) {
      Logger.error('Failed to generate audio segment', error: e);
      rethrow;
    }
  }

  double _calculateAdjustedSpeed(TextSegment segment) {
    double speed = _globalSpeed;
    
    if (segment.customSpeed != null) {
      speed = segment.customSpeed!;
    } else {
      speed *= segment.emotion.speedMultiplier;
    }
    
    return speed.clamp(0.25, 4.0);
  }

  Future<void> _playNextInQueue() async {
    if (_isPlaying || _isPaused || _audioQueue.isEmpty) return;
    
    _isPlaying = true;
    _playbackStatusController.add(true);
    
    final audioData = _audioQueue.removeFirst();
    final textSegment = _textQueue.isNotEmpty ? _textQueue.removeFirst() : null;
    
    if (textSegment != null) {
      _currentTextController.add(textSegment.text);
    }
    
    _queueSizeController.add(_audioQueue.length);
    
    try {
      await _audioPlayer.play(
        BytesSource(audioData),
        mode: PlayerMode.lowLatency,
      );
    } catch (e) {
      Logger.error('Failed to play audio', error: e);
      _isPlaying = false;
      _playbackStatusController.add(false);
      
      _playNextInQueue();
    }
  }

  List<TextSegment> _analyzeTextSegments(String text, {TTSEmotion? defaultEmotion}) {
    final List<TextSegment> segments = [];
    
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));
    
    for (final sentence in sentences) {
      if (sentence.trim().isEmpty) continue;
      
      final emotion = defaultEmotion ?? _detectEmotion(sentence);
      segments.add(TextSegment(
        text: sentence.trim(),
        emotion: emotion,
      ));
    }
    
    if (segments.isEmpty && text.trim().isNotEmpty) {
      segments.add(TextSegment(
        text: text.trim(),
        emotion: defaultEmotion ?? TTSEmotion.neutral,
      ));
    }
    
    return segments;
  }

  TTSEmotion _detectEmotion(String text) {
    final lowerText = text.toLowerCase();
    
    if (text.contains('?')) {
      return TTSEmotion.questioning;
    }
    
    if (text.contains('!')) {
      if (lowerText.contains('great') || 
          lowerText.contains('excellent') || 
          lowerText.contains('wonderful')) {
        return TTSEmotion.encouraging;
      }
      return TTSEmotion.excited;
    }
    
    if (text.contains('...') || lowerText.contains('hmm') || lowerText.contains('well')) {
      return TTSEmotion.thoughtful;
    }
    
    if (lowerText.contains('good job') || 
        lowerText.contains('well done') || 
        lowerText.contains('nice')) {
      return TTSEmotion.encouraging;
    }
    
    if (lowerText.contains('sorry') || 
        lowerText.contains('please') || 
        lowerText.contains('thank')) {
      return TTSEmotion.gentle;
    }
    
    return TTSEmotion.neutral;
  }

  Future<void> speakSimple(String text, {TTSVoice? voice, double speed = 1.0}) async {
    await speakWithEmotion(text, voice: voice, speed: speed, emotion: TTSEmotion.neutral);
  }

  Future<void> pause() async {
    if (_isPlaying && !_isPaused) {
      await _audioPlayer.pause();
      _isPaused = true;
      _playbackStatusController.add(false);
      Logger.info('TTS playback paused');
    }
  }

  Future<void> resume() async {
    if (_isPaused) {
      await _audioPlayer.resume();
      _isPaused = false;
      _playbackStatusController.add(true);
      Logger.info('TTS playback resumed');
    }
  }

  Future<void> stop() async {
    await _audioPlayer.stop();
    _isPlaying = false;
    _isPaused = false;
    _playbackStatusController.add(false);
    Logger.info('TTS playback stopped');
  }

  Future<void> clearAudioQueue() async {
    _audioQueue.clear();
    _textQueue.clear();
    _queueSizeController.add(0);
    await stop();
    Logger.info('Audio queue cleared');
  }

  void setVoice(TTSVoice voice) {
    _currentVoice = voice;
    Logger.info('TTS voice changed to: ${voice.value}');
  }

  void setGlobalSpeed(double speed) {
    _globalSpeed = speed.clamp(0.25, 4.0);
    Logger.info('TTS global speed set to: $_globalSpeed');
  }

  Future<void> speakConversationalResponse(String text) async {
    final processedText = _addConversationalElements(text);
    
    await speakWithEmotion(
      processedText,
      voice: TTSVoice.nova,
      speed: 0.95,
      clearQueue: true,
    );
  }

  String _addConversationalElements(String text) {
    final random = DateTime.now().millisecondsSinceEpoch % 10;
    
    if (random < 3 && !text.startsWith('Well')) {
      text = 'Well, $text';
    } else if (random < 5 && !text.startsWith('So')) {
      text = 'So, $text';
    }
    
    text = text.replaceAll(' do not ', ' don\'t ');
    text = text.replaceAll(' cannot ', ' can\'t ');
    text = text.replaceAll(' will not ', ' won\'t ');
    text = text.replaceAll(' I am ', ' I\'m ');
    text = text.replaceAll(' you are ', ' you\'re ');
    
    return text;
  }

  Future<void> dispose() async {
    Logger.info('Disposing Natural TTS Service');
    
    await clearAudioQueue();
    await _audioPlayer.dispose();
    
    await _playbackStatusController.close();
    await _currentTextController.close();
    await _queueSizeController.close();
  }
}