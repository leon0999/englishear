import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../core/logger.dart';
import 'enhanced_audio_streaming_service.dart';

/// Conversation Improver Service
/// Implements the Upgrade Replay feature
class ConversationImproverService {
  final String apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
  final _MockAudioPlayer _audioPlayer = _MockAudioPlayer();
  
  // Stream controllers
  final _playbackProgressController = StreamController<PlaybackProgress>.broadcast();
  Stream<PlaybackProgress> get playbackProgressStream => _playbackProgressController.stream;
  
  /// Improve conversation and replay
  Future<ImprovedConversation> upgradeReplay(
    List<ConversationSegment> conversationHistory,
  ) async {
    try {
      AppLogger.info('Starting Upgrade Replay process');
      
      // 1. Extract user utterances from conversation history
      final userSegments = conversationHistory
          .where((segment) => segment.role == 'user')
          .toList();
      
      if (userSegments.isEmpty) {
        throw Exception('No user audio found in conversation history');
      }
      
      // 2. Transcribe user audio (if not already transcribed)
      final userTranscripts = await _transcribeAudioSegments(userSegments);
      
      // 3. Improve user utterances with GPT-4
      final improvedTexts = await _improveUserUtterances(userTranscripts);
      
      // 4. Generate improved audio with TTS
      final improvedAudioSegments = await _generateImprovedAudio(improvedTexts);
      
      // 5. Create improved conversation structure
      final improvedConversation = ImprovedConversation(
        originalSegments: conversationHistory,
        improvedUserTexts: improvedTexts,
        improvedUserAudio: improvedAudioSegments,
        improvements: _generateImprovementSuggestions(userTranscripts, improvedTexts),
      );
      
      AppLogger.info('Upgrade Replay process completed');
      return improvedConversation;
      
    } catch (e) {
      AppLogger.error('Failed to upgrade replay', e);
      rethrow;
    }
  }
  
  /// Transcribe audio segments
  Future<List<String>> _transcribeAudioSegments(
    List<ConversationSegment> segments,
  ) async {
    final transcripts = <String>[];
    
    for (final segment in segments) {
      try {
        // Use OpenAI Whisper API for transcription
        final transcript = await _transcribeWithWhisper(segment.audioData);
        transcripts.add(transcript);
      } catch (e) {
        AppLogger.error('Failed to transcribe segment', e);
        transcripts.add(''); // Add empty string for failed transcriptions
      }
    }
    
    return transcripts;
  }
  
  /// Transcribe audio using Whisper API
  Future<String> _transcribeWithWhisper(Uint8List audioData) async {
    try {
      // Convert PCM to WAV for Whisper API
      final wavData = _pcmToWav(audioData);
      
      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.openai.com/v1/audio/transcriptions'),
      );
      
      request.headers['Authorization'] = 'Bearer $apiKey';
      
      // Add audio file
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          wavData,
          filename: 'audio.wav',
        ),
      );
      
      // Add model parameter
      request.fields['model'] = 'whisper-1';
      request.fields['language'] = 'en';
      
      // Send request
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        final json = jsonDecode(responseBody);
        return json['text'] ?? '';
      } else {
        throw Exception('Whisper API error: $responseBody');
      }
      
    } catch (e) {
      AppLogger.error('Whisper transcription failed', e);
      rethrow;
    }
  }
  
  /// Improve user utterances using GPT-4
  Future<List<String>> _improveUserUtterances(List<String> originals) async {
    try {
      final prompt = '''
You are an English language coach. Improve these English sentences to be more natural, fluent, and grammatically correct while keeping the same meaning.

Original sentences:
${originals.asMap().entries.map((e) => '${e.key + 1}. "${e.value}"').join('\n')}

Provide improved versions that:
- Use natural, conversational English
- Fix any grammar or pronunciation issues
- Keep the same intent and meaning
- Sound like a native speaker would say it

Format your response as a numbered list matching the original sentences.
''';
      
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4-turbo-preview',
          'messages': [
            {
              'role': 'system',
              'content': 'You are a helpful English language coach who improves sentences to sound more natural.',
            },
            {
              'role': 'user',
              'content': prompt,
            },
          ],
          'temperature': 0.7,
          'max_tokens': 1000,
        }),
      );
      
      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final content = json['choices'][0]['message']['content'];
        
        // Parse numbered list response
        final improvedTexts = <String>[];
        final lines = content.split('\n');
        
        for (final line in lines) {
          // Extract text from numbered format (e.g., "1. Improved text")
          final match = RegExp(r'^\d+\.\s*"?(.+?)"?$').firstMatch(line.trim());
          if (match != null) {
            improvedTexts.add(match.group(1)!.replaceAll('"', ''));
          }
        }
        
        // Ensure we have the same number of improved texts
        while (improvedTexts.length < originals.length) {
          improvedTexts.add(originals[improvedTexts.length]);
        }
        
        return improvedTexts;
        
      } else {
        throw Exception('GPT-4 API error: ${response.body}');
      }
      
    } catch (e) {
      AppLogger.error('Failed to improve utterances', e);
      // Return original texts if improvement fails
      return originals;
    }
  }
  
  /// Generate improved audio using TTS
  Future<List<Uint8List>> _generateImprovedAudio(List<String> texts) async {
    final audioSegments = <Uint8List>[];
    
    for (final text in texts) {
      try {
        final audio = await _textToSpeech(text);
        audioSegments.add(audio);
      } catch (e) {
        AppLogger.error('Failed to generate audio for: $text', e);
        audioSegments.add(Uint8List(0)); // Add empty audio for failed TTS
      }
    }
    
    return audioSegments;
  }
  
  /// Convert text to speech using OpenAI TTS
  Future<Uint8List> _textToSpeech(String text, {String voice = 'nova'}) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/audio/speech'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': 'tts-1',
          'input': text,
          'voice': voice,
          'response_format': 'mp3',
        }),
      );
      
      if (response.statusCode == 200) {
        return response.bodyBytes;
      } else {
        throw Exception('TTS API error: ${response.body}');
      }
      
    } catch (e) {
      AppLogger.error('Text-to-speech failed', e);
      rethrow;
    }
  }
  
  /// Generate improvement suggestions
  List<ImprovementSuggestion> _generateImprovementSuggestions(
    List<String> original,
    List<String> improved,
  ) {
    final suggestions = <ImprovementSuggestion>[];
    
    for (int i = 0; i < original.length && i < improved.length; i++) {
      if (original[i] != improved[i]) {
        suggestions.add(ImprovementSuggestion(
          original: original[i],
          improved: improved[i],
          explanation: _generateExplanation(original[i], improved[i]),
        ));
      }
    }
    
    return suggestions;
  }
  
  /// Generate explanation for improvement
  String _generateExplanation(String original, String improved) {
    // Simple heuristic-based explanation
    // In production, could use GPT-4 for better explanations
    
    if (original.toLowerCase() != improved.toLowerCase()) {
      if (improved.contains("'") && !original.contains("'")) {
        return "Used contraction for more natural speech";
      }
      if (improved.length < original.length) {
        return "Simplified for clarity";
      }
      if (improved.contains(',') && !original.contains(',')) {
        return "Added pause for better flow";
      }
    }
    
    return "Improved grammar and naturalness";
  }
  
  /// Play improved conversation
  Future<void> playImprovedConversation(
    ImprovedConversation conversation,
  ) async {
    try {
      AppLogger.info('Starting improved conversation playback');
      
      int totalSegments = conversation.improvedUserAudio.length;
      
      for (int i = 0; i < totalSegments; i++) {
        // Update progress
        _playbackProgressController.add(PlaybackProgress(
          currentSegment: i + 1,
          totalSegments: totalSegments,
          isPlaying: true,
        ));
        
        // Play improved user audio
        await _playAudioData(conversation.improvedUserAudio[i]);
        
        // Brief pause between segments
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Play corresponding AI response if available
        final aiSegments = conversation.originalSegments
            .where((s) => s.role == 'assistant')
            .toList();
        
        if (i < aiSegments.length) {
          await _playAudioData(aiSegments[i].audioData);
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
      
      // Playback completed
      _playbackProgressController.add(PlaybackProgress(
        currentSegment: totalSegments,
        totalSegments: totalSegments,
        isPlaying: false,
      ));
      
      AppLogger.info('Improved conversation playback completed');
      
    } catch (e) {
      AppLogger.error('Failed to play improved conversation', e);
      _playbackProgressController.add(PlaybackProgress(
        currentSegment: 0,
        totalSegments: 0,
        isPlaying: false,
      ));
    }
  }
  
  /// Play audio data
  Future<void> _playAudioData(Uint8List audioData) async {
    if (audioData.isEmpty) return;
    
    try {
      // Save to temporary file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/improved_${DateTime.now().millisecondsSinceEpoch}.mp3');
      await tempFile.writeAsBytes(audioData);
      
      // Play with just_audio
      await _audioPlayer.setFilePath(tempFile.path);
      await _audioPlayer.play();
      
      // Wait for playback to complete
      await _audioPlayer.processingStateStream.firstWhere(
        (state) => state == true,
      );
      
      // Clean up
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
      }
      
    } catch (e) {
      AppLogger.error('Failed to play audio data', e);
    }
  }
  
  /// Convert PCM to WAV format
  Uint8List _pcmToWav(Uint8List pcmData, {
    int sampleRate = 24000,
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    final dataSize = pcmData.length;
    
    final wav = BytesBuilder();
    
    // RIFF header
    wav.add(utf8.encode('RIFF'));
    wav.add(_int32ToBytes(36 + dataSize));
    wav.add(utf8.encode('WAVE'));
    
    // fmt subchunk
    wav.add(utf8.encode('fmt '));
    wav.add(_int32ToBytes(16));
    wav.add(_int16ToBytes(1)); // PCM format
    wav.add(_int16ToBytes(channels));
    wav.add(_int32ToBytes(sampleRate));
    wav.add(_int32ToBytes(byteRate));
    wav.add(_int16ToBytes(blockAlign));
    wav.add(_int16ToBytes(bitsPerSample));
    
    // data subchunk
    wav.add(utf8.encode('data'));
    wav.add(_int32ToBytes(dataSize));
    wav.add(pcmData);
    
    return wav.toBytes();
  }
  
  Uint8List _int16ToBytes(int value) {
    return Uint8List(2)..buffer.asByteData().setInt16(0, value, Endian.little);
  }
  
  Uint8List _int32ToBytes(int value) {
    return Uint8List(4)..buffer.asByteData().setInt32(0, value, Endian.little);
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    await _audioPlayer.dispose();
    await _playbackProgressController.close();
  }
}

/// Improved conversation data structure
class ImprovedConversation {
  final List<ConversationSegment> originalSegments;
  final List<String> improvedUserTexts;
  final List<Uint8List> improvedUserAudio;
  final List<ImprovementSuggestion> improvements;
  
  ImprovedConversation({
    required this.originalSegments,
    required this.improvedUserTexts,
    required this.improvedUserAudio,
    required this.improvements,
  });
}

/// Improvement suggestion
class ImprovementSuggestion {
  final String original;
  final String improved;
  final String explanation;
  
  ImprovementSuggestion({
    required this.original,
    required this.improved,
    required this.explanation,
  });
}

/// Playback progress
class PlaybackProgress {
  final int currentSegment;
  final int totalSegments;
  final bool isPlaying;
  
  PlaybackProgress({
    required this.currentSegment,
    required this.totalSegments,
    required this.isPlaying,
  });
  
  double get progress => totalSegments > 0 ? currentSegment / totalSegments : 0.0;
}
// 임시 모의 클래스 (나중에 flutter_sound로 교체)
class _MockAudioPlayer {
  void dispose() {}
  Future<void> play() async {}
  Future<void> stop() async {}
  Future<void> setVolume(double volume) async {}
  Stream<dynamic> get playerStateStream => Stream.value(null);
  bool get isPlaying => false;
}
