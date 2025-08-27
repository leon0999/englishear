// lib/services/audio_playback_service.dart

import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AudioPlaybackService {
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Dio _dio;
  final String _apiKey;
  
  // 음성 옵션
  static const List<String> VOICES = ['nova', 'alloy', 'echo', 'fable', 'onyx', 'shimmer'];
  static const Map<String, double> SPEED_OPTIONS = {
    'slow': 0.75,
    'normal': 0.95,
    'fast': 1.15,
  };
  
  // 캐시 (메모리)
  final Map<String, Uint8List> _audioCache = {};
  static const int MAX_CACHE_SIZE = 20; // 최대 20개 캐시
  
  AudioPlaybackService() : 
    _apiKey = dotenv.env['OPENAI_API_KEY'] ?? '',
    _dio = Dio(BaseOptions(
      baseUrl: 'https://api.openai.com/v1',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Authorization': 'Bearer ${dotenv.env['OPENAI_API_KEY'] ?? ''}',
      },
    ));
  
  // 1. TTS 생성 및 재생 (고품질)
  Future<void> speakHighQuality({
    required String text,
    String voice = 'nova',
    double speed = 0.95,
    Function()? onComplete,
    Function(String)? onError,
  }) async {
    try {
      // 캐시 확인
      final cacheKey = _getCacheKey(text, voice, speed);
      
      Uint8List audioData;
      if (_audioCache.containsKey(cacheKey)) {
        audioData = _audioCache[cacheKey]!;
        print('🎵 Using cached audio');
      } else {
        // OpenAI TTS-HD API 호출
        audioData = await _generateTTS(text, voice, speed);
        _addToCache(cacheKey, audioData);
      }
      
      // 플랫폼별 재생
      if (kIsWeb) {
        await _playOnWeb(audioData);
      } else {
        await _playOnMobile(audioData);
      }
      
      onComplete?.call();
      
    } catch (e) {
      print('❌ Audio playback error: $e');
      onError?.call(e.toString());
    }
  }
  
  // 2. TTS 생성
  Future<Uint8List> _generateTTS(String text, String voice, double speed) async {
    try {
      final response = await _dio.post(
        '/audio/speech',
        options: Options(responseType: ResponseType.bytes),
        data: {
          'model': 'tts-1-hd',
          'voice': voice,
          'input': text,
          'speed': speed,
        },
      );
      
      return Uint8List.fromList(response.data);
      
    } catch (e) {
      print('❌ TTS generation error: $e');
      throw Exception('Failed to generate audio: $e');
    }
  }
  
  // 3. 웹에서 재생
  Future<void> _playOnWeb(Uint8List audioData) async {
    try {
      // Blob 생성
      final blob = html.Blob([audioData], 'audio/mp3');
      final url = html.Url.createObjectUrlFromBlob(blob);
      
      // Audio 엘리먼트 생성 및 재생
      final audio = html.AudioElement()
        ..src = url
        ..autoplay = false
        ..volume = 0.9;
      
      // 재생
      await audio.play();
      
      // 재생 완료 대기
      await audio.onEnded.first;
      
      // 메모리 정리
      html.Url.revokeObjectUrl(url);
      
    } catch (e) {
      print('❌ Web audio playback error: $e');
      throw e;
    }
  }
  
  // 4. 모바일에서 재생
  Future<void> _playOnMobile(Uint8List audioData) async {
    try {
      // Just Audio 플레이어 사용
      final audioSource = AudioSource.uri(
        Uri.dataFromBytes(audioData, mimeType: 'audio/mp3'),
      );
      
      await _audioPlayer.setAudioSource(audioSource);
      await _audioPlayer.play();
      await _audioPlayer.playerStateStream.firstWhere(
        (state) => state.processingState == ProcessingState.completed,
      );
      
    } catch (e) {
      print('❌ Mobile audio playback error: $e');
      throw e;
    }
  }
  
  // 5. 대화 전체 재생 (Upgrade Replay용)
  Future<void> playConversationSequence(
    List<Map<String, String>> conversation, {
    Map<String, String>? improvedUserResponses,
    Function(int)? onProgressUpdate,
    Function()? onComplete,
  }) async {
    try {
      for (int i = 0; i < conversation.length; i++) {
        final turn = conversation[i];
        
        onProgressUpdate?.call(i);
        
        if (turn['speaker'] == 'AI') {
          // AI 음성은 원본 그대로
          await speakHighQuality(
            text: turn['text']!,
            voice: 'nova',
            speed: 0.95,
          );
        } else {
          // User 음성은 개선된 버전 사용 (있으면)
          final textToSpeak = improvedUserResponses?[turn['text']!] ?? turn['text']!;
          await speakHighQuality(
            text: textToSpeak,
            voice: 'echo', // 사용자는 다른 음성
            speed: 0.9,
          );
        }
        
        // 턴 사이 자연스러운 간격
        await Future.delayed(const Duration(milliseconds: 800));
      }
      
      onComplete?.call();
      
    } catch (e) {
      print('❌ Conversation playback error: $e');
      throw e;
    }
  }
  
  // 6. 정지
  Future<void> stop() async {
    if (!kIsWeb) {
      await _audioPlayer.stop();
    }
  }
  
  // 7. 일시정지
  Future<void> pause() async {
    if (!kIsWeb) {
      await _audioPlayer.pause();
    }
  }
  
  // 8. 재개
  Future<void> resume() async {
    if (!kIsWeb) {
      await _audioPlayer.play();
    }
  }
  
  // 9. 볼륨 조절
  Future<void> setVolume(double volume) async {
    if (!kIsWeb) {
      await _audioPlayer.setVolume(volume.clamp(0.0, 1.0));
    }
  }
  
  // 10. 캐시 관리
  String _getCacheKey(String text, String voice, double speed) {
    return '${text.hashCode}_${voice}_$speed';
  }
  
  void _addToCache(String key, Uint8List data) {
    // 캐시 크기 제한
    if (_audioCache.length >= MAX_CACHE_SIZE) {
      // 가장 오래된 항목 제거 (FIFO)
      _audioCache.remove(_audioCache.keys.first);
    }
    _audioCache[key] = data;
  }
  
  void clearCache() {
    _audioCache.clear();
  }
  
  // 11. 리소스 해제
  void dispose() {
    _audioPlayer.dispose();
    clearCache();
  }
}