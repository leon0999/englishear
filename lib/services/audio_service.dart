// lib/services/audio_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_tts/flutter_tts.dart';

class AudioService {
  final AudioPlayer bgmPlayer = AudioPlayer();
  final AudioPlayer ttsPlayer = AudioPlayer();
  final FlutterTts flutterTts = FlutterTts();
  
  late final Dio _dio;
  late final String _apiKey;
  
  // 볼륨 설정
  double bgmVolume = 0.3;
  double ttsVolume = 1.0;
  
  Timer? _fadeTimer;
  
  AudioService() {
    _apiKey = dotenv.env['OPENAI_API_KEY'] ?? '';
    _dio = Dio(BaseOptions(
      baseUrl: 'https://api.openai.com/v1',
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
    ));
    
    _initializeTTS();
  }
  
  Future<void> _initializeTTS() async {
    try {
      // 공통 설정
      await flutterTts.setLanguage("en-US");
      await flutterTts.setSpeechRate(0.95); // 자연스러운 속도
      await flutterTts.setVolume(ttsVolume);
      await flutterTts.setPitch(1.0);
      
      // iOS 전용 설정 (웹이 아니고 iOS 플랫폼인 경우만)
      if (!kIsWeb && Platform.isIOS) {
        await flutterTts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [
            IosTextToSpeechAudioCategoryOptions.allowBluetooth,
            IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          ],
        );
      }
    } catch (e) {
      print('TTS initialization warning: $e');
      // TTS 초기화 실패는 치명적이지 않으므로 계속 진행
    }
  }
  
  // 배경음악 페이드인 재생 (CORS 안전한 소스 사용)
  Future<void> playBackgroundMusic(String scenario) async {
    try {
      // CORS가 허용된 오디오 소스 사용 (FreeSounds)
      final audioUrls = {
        'street': 'https://cdn.freesound.org/previews/316/316909_5123451-lq.mp3',
        'restaurant': 'https://cdn.freesound.org/previews/564/564991_9497060-lq.mp3',
        'park': 'https://cdn.freesound.org/previews/534/534481_11368968-lq.mp3',
        'office': 'https://cdn.freesound.org/previews/371/371518_6891730-lq.mp3',
        'home': 'https://cdn.freesound.org/previews/397/397846_5121236-lq.mp3',
        'default': 'https://cdn.freesound.org/previews/316/316909_5123451-lq.mp3',
      };
      
      final url = audioUrls[scenario] ?? audioUrls['default'];
      
      if (url == null || url.isEmpty) {
        print('No background music URL for scenario: $scenario');
        return;
      }
      
      print('🎵 Playing background music for: $scenario');
      
      // 이전 음악 정지
      await bgmPlayer.stop();
      
      // 새 음악 설정
      await bgmPlayer.setSource(UrlSource(url));
      await bgmPlayer.setVolume(0.0);
      await bgmPlayer.setReleaseMode(ReleaseMode.loop); // 반복 재생
      await bgmPlayer.resume();
      
      // 페이드인 효과 (3초)
      _startFadeIn();
      
    } catch (e) {
      print('⚠️ Background music skipped: $e');
      // 오디오 실패시 무시하고 계속 진행
    }
  }
  
  void _startFadeIn() {
    _fadeTimer?.cancel();
    
    double currentVolume = 0.0;
    const fadeSteps = 30;
    const stepDuration = Duration(milliseconds: 100);
    final volumeStep = bgmVolume / fadeSteps;
    
    _fadeTimer = Timer.periodic(stepDuration, (timer) {
      currentVolume += volumeStep;
      
      if (currentVolume >= bgmVolume) {
        currentVolume = bgmVolume;
        timer.cancel();
      }
      
      bgmPlayer.setVolume(currentVolume);
    });
  }
  
  // 배경음악 페이드아웃 후 정지
  Future<void> stopBackgroundMusic() async {
    _fadeTimer?.cancel();
    
    double currentVolume = bgmVolume;
    const fadeSteps = 20;
    const stepDuration = Duration(milliseconds: 50);
    final volumeStep = bgmVolume / fadeSteps;
    
    _fadeTimer = Timer.periodic(stepDuration, (timer) async {
      currentVolume -= volumeStep;
      
      if (currentVolume <= 0) {
        currentVolume = 0;
        timer.cancel();
        await bgmPlayer.stop();
      } else {
        await bgmPlayer.setVolume(currentVolume);
      }
    });
  }
  
  // 스몰톡 재생
  Future<void> playSmallTalk(List<String> sentences) async {
    for (String sentence in sentences) {
      await playTTS(sentence);
      
      // 문장 간 자연스러운 간격 (0.8초)
      await Future.delayed(Duration(milliseconds: 800));
    }
  }
  
  // TTS 재생 (플랫폼 TTS 사용) - 타임아웃 개선
  Future<void> playTTS(String text) async {
    try {
      // 배경음악 볼륨 줄이기
      await bgmPlayer.setVolume(bgmVolume * 0.3);
      
      // 타임아웃과 함께 TTS 재생
      await Future.any([
        flutterTts.speak(text),
        Future.delayed(Duration(seconds: 3)), // 3초 타임아웃
      ]).catchError((e) {
        print('TTS speak error: $e');
      });
      
      // TTS 완료 대기 (개선된 버전)
      await _waitForTTSCompletion(text);
      
      // 배경음악 볼륨 복원
      await bgmPlayer.setVolume(bgmVolume);
      
    } catch (e) {
      print('TTS skipped: $e');
      // TTS 실패시 자막으로 대체
      _showSubtitle(text);
    }
  }
  
  Future<void> _waitForTTSCompletion(String text) async {
    final completer = Completer<void>();
    bool isCompleted = false;
    
    flutterTts.setCompletionHandler(() {
      if (!isCompleted) {
        isCompleted = true;
        completer.complete();
      }
    });
    
    // 텍스트 길이 기반 동적 타임아웃 (단어당 0.5초, 최소 3초, 최대 10초)
    final wordCount = text.split(' ').length;
    final timeoutSeconds = (wordCount * 0.5).clamp(3.0, 10.0);
    
    await completer.future.timeout(
      Duration(seconds: timeoutSeconds.round()),
      onTimeout: () {
        print('TTS timeout after ${timeoutSeconds}s');
        isCompleted = true;
      },
    );
  }
  
  // 자막 표시 (TTS 대체)
  void _showSubtitle(String text) {
    print('📝 Subtitle: $text');
    // 실제 구현은 UI 컨트롤러를 통해 처리
  }
  
  // OpenAI TTS API를 사용한 고품질 음성 생성
  Future<String> generateTTS(String text, {String voice = 'nova'}) async {
    try {
      final response = await _dio.post(
        '/audio/speech',
        data: {
          'model': 'tts-1-hd',
          'input': text,
          'voice': voice, // alloy, echo, fable, onyx, nova, shimmer
          'response_format': 'mp3',
          'speed': 0.95,
        },
        options: Options(
          responseType: ResponseType.bytes,
        ),
      );
      
      if (response.statusCode == 200) {
        // 바이트 데이터를 base64로 인코딩
        final base64Audio = base64Encode(response.data);
        return 'data:audio/mp3;base64,$base64Audio';
      }
      
      throw Exception('Failed to generate TTS');
      
    } catch (e) {
      print('Error generating OpenAI TTS: $e');
      // 폴백: 플랫폼 TTS 사용
      return '';
    }
  }
  
  // 오디오 URL 재생
  Future<void> playAudioUrl(String url) async {
    try {
      if (url.isEmpty) return;
      
      // base64 데이터 URL인 경우
      if (url.startsWith('data:audio')) {
        // base64 디코딩 후 재생
        final base64Data = url.split(',').last;
        final bytes = base64Decode(base64Data);
        await ttsPlayer.setSource(BytesSource(bytes));
      } else {
        // 일반 URL
        await ttsPlayer.setSource(UrlSource(url));
      }
      
      await ttsPlayer.setVolume(ttsVolume);
      await ttsPlayer.resume();
      
    } catch (e) {
      print('Error playing audio URL: $e');
    }
  }
  
  // 음향 효과 재생
  Future<void> playSound(SoundEffect effect) async {
    final effectPlayer = AudioPlayer();
    
    try {
      String soundUrl = '';
      
      switch (effect) {
        case SoundEffect.success:
          soundUrl = 'https://www.soundjay.com/misc/sounds/bell-ringing-05.mp3';
          break;
        case SoundEffect.error:
          soundUrl = 'https://www.soundjay.com/misc/sounds/fail-buzzer-02.mp3';
          break;
        case SoundEffect.click:
          soundUrl = 'https://www.soundjay.com/misc/sounds/button-09.mp3';
          break;
        case SoundEffect.notification:
          soundUrl = 'https://www.soundjay.com/misc/sounds/bell-ringing-04.mp3';
          break;
      }
      
      if (soundUrl.isNotEmpty) {
        await effectPlayer.setSource(UrlSource(soundUrl));
        await effectPlayer.setVolume(0.5);
        await effectPlayer.resume();
      }
      
      // 재생 완료 후 리소스 해제
      effectPlayer.onPlayerComplete.listen((_) {
        effectPlayer.dispose();
      });
      
    } catch (e) {
      print('Error playing sound effect: $e');
      effectPlayer.dispose();
    }
  }
  
  // 볼륨 조절
  Future<void> setBGMVolume(double volume) async {
    bgmVolume = volume.clamp(0.0, 1.0);
    await bgmPlayer.setVolume(bgmVolume);
  }
  
  Future<void> setTTSVolume(double volume) async {
    ttsVolume = volume.clamp(0.0, 1.0);
    await ttsPlayer.setVolume(ttsVolume);
    await flutterTts.setVolume(ttsVolume);
  }
  
  // 리소스 정리
  void dispose() {
    _fadeTimer?.cancel();
    bgmPlayer.dispose();
    ttsPlayer.dispose();
    flutterTts.stop();
  }
}

// 음향 효과 타입
enum SoundEffect {
  success,
  error,
  click,
  notification,
}