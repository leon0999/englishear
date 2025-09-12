import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../core/logger.dart';

/// Abstract TTS engine interface
abstract class TTSEngine {
  Future<Stream<Uint8List>> synthesize(String text, {Map<String, dynamic>? options});
  bool get isAvailable;
  String get name;
  int get priority; // Lower number = higher priority
}

/// OpenAI Realtime API TTS Engine
class OpenAITTSEngine implements TTSEngine {
  final String? apiKey;
  
  OpenAITTSEngine({this.apiKey});
  
  @override
  String get name => 'OpenAI Realtime';
  
  @override
  int get priority => 1;
  
  @override
  bool get isAvailable => apiKey != null && apiKey!.isNotEmpty;
  
  @override
  Future<Stream<Uint8List>> synthesize(String text, {Map<String, dynamic>? options}) async {
    if (!isAvailable) {
      throw Exception('OpenAI API key not available');
    }
    
    // This will be handled by the existing OpenAI WebSocket connection
    // For now, return an empty stream as a placeholder
    // The actual implementation will use the WebSocket to send text and receive audio
    final controller = StreamController<Uint8List>();
    
    // Simulate API call (replace with actual WebSocket implementation)
    Future.delayed(Duration(milliseconds: 100), () {
      controller.add(Uint8List(0)); // Placeholder
      controller.close();
    });
    
    return controller.stream;
  }
}

/// Microsoft Edge TTS Engine (Free, high-quality)
class EdgeTTSEngine implements TTSEngine {
  static const String _baseUrl = 'https://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1';
  
  // High-quality voices
  static const Map<String, String> voices = {
    'male': 'en-US-ChristopherNeural',
    'female': 'en-US-JennyNeural',
    'british_male': 'en-GB-RyanNeural',
    'british_female': 'en-GB-SoniaNeural',
  };
  
  final String selectedVoice;
  
  EdgeTTSEngine({this.selectedVoice = 'female'});
  
  @override
  String get name => 'Microsoft Edge TTS';
  
  @override
  int get priority => 2;
  
  @override
  bool get isAvailable => true; // Always available as fallback
  
  @override
  Future<Stream<Uint8List>> synthesize(String text, {Map<String, dynamic>? options}) async {
    try {
      final voice = voices[selectedVoice] ?? voices['female']!;
      final ssml = _buildSSML(text, voice: voice, options: options);
      
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/ssml+xml',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
        body: ssml,
      );
      
      if (response.statusCode == 200) {
        return Stream.value(response.bodyBytes);
      } else {
        throw Exception('Edge TTS failed: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.error('Edge TTS error: $e');
      throw e;
    }
  }
  
  String _buildSSML(String text, {required String voice, Map<String, dynamic>? options}) {
    final rate = options?['speed'] ?? '0%';
    final pitch = options?['pitch'] ?? '0%';
    final volume = options?['volume'] ?? '100';
    
    // Escape XML special characters
    final escapedText = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
    
    return '''<?xml version="1.0" encoding="UTF-8"?>
<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" xml:lang="en-US">
  <voice name="$voice">
    <prosody rate="$rate" pitch="$pitch" volume="$volume">
      $escapedText
    </prosody>
  </voice>
</speak>''';
  }
}

/// Browser's built-in Web Speech API (fallback)
class WebSpeechTTSEngine implements TTSEngine {
  @override
  String get name => 'Web Speech API';
  
  @override
  int get priority => 3;
  
  @override
  bool get isAvailable => true; // Always available in browser
  
  @override
  Future<Stream<Uint8List>> synthesize(String text, {Map<String, dynamic>? options}) async {
    // This would use the browser's speechSynthesis API
    // For Flutter, we'd use a platform channel or flutter_tts package
    // For now, return empty stream as this is a last-resort fallback
    return Stream.empty();
  }
}

/// Multi-engine TTS with automatic fallback
class MultiEngineTTS {
  final List<TTSEngine> engines;
  TTSEngine? _lastSuccessfulEngine;
  
  MultiEngineTTS({List<TTSEngine>? customEngines}) 
    : engines = customEngines ?? _defaultEngines() {
    // Sort engines by priority
    engines.sort((a, b) => a.priority.compareTo(b.priority));
  }
  
  static List<TTSEngine> _defaultEngines() {
    return [
      OpenAITTSEngine(apiKey: const String.fromEnvironment('OPENAI_API_KEY')),
      EdgeTTSEngine(),
      WebSpeechTTSEngine(),
    ];
  }
  
  /// Synthesize text with automatic fallback
  Future<Stream<Uint8List>> synthesize(String text, {Map<String, dynamic>? options}) async {
    // Try last successful engine first for consistency
    if (_lastSuccessfulEngine != null && _lastSuccessfulEngine!.isAvailable) {
      try {
        final result = await _lastSuccessfulEngine!.synthesize(text, options: options);
        AppLogger.info('TTS using cached engine: ${_lastSuccessfulEngine!.name}');
        return result;
      } catch (e) {
        AppLogger.warning('Cached engine failed, trying others...');
      }
    }
    
    // Try each engine in priority order
    for (final engine in engines) {
      if (!engine.isAvailable) {
        AppLogger.debug('Skipping unavailable engine: ${engine.name}');
        continue;
      }
      
      try {
        AppLogger.info('Trying TTS engine: ${engine.name}');
        final result = await engine.synthesize(text, options: options);
        _lastSuccessfulEngine = engine;
        AppLogger.success('TTS successful with: ${engine.name}');
        return result;
      } catch (e) {
        AppLogger.warning('Engine ${engine.name} failed: $e');
        continue;
      }
    }
    
    throw Exception('All TTS engines failed');
  }
  
  /// Get list of available engines
  List<String> getAvailableEngines() {
    return engines
        .where((e) => e.isAvailable)
        .map((e) => e.name)
        .toList();
  }
  
  /// Reset engine preference
  void resetEnginePreference() {
    _lastSuccessfulEngine = null;
  }
}