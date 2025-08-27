// lib/services/audio_service.dart

import 'dart:async';
import 'dart:convert';
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
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.95); // 자연스러운 속도
    await flutterTts.setVolume(ttsVolume);
    await flutterTts.setPitch(1.0);
    
    // iOS 설정
    await flutterTts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.playback,
      [
        IosTextToSpeechAudioCategoryOptions.allowBluetooth,
        IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
        IosTextToSpeechAudioCategoryOptions.mixWithOthers,
      ],
    );
  }
  
  // 배경음악 페이드인 재생
  Future<void> playBackgroundMusic(String url) async {
    try {
      if (url.isEmpty) {
        print('No background music URL provided');
        return;
      }
      
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
      print('Error playing background music: $e');
      // 폴백: 로컬 배경음 또는 무음 처리
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
  
  // TTS 재생 (플랫폼 TTS 사용)
  Future<void> playTTS(String text) async {
    try {
      // 배경음악 볼륨 줄이기
      await bgmPlayer.setVolume(bgmVolume * 0.3);
      
      // TTS 재생
      await flutterTts.speak(text);
      
      // TTS 완료 대기
      await _waitForTTSCompletion();
      
      // 배경음악 볼륨 복원
      await bgmPlayer.setVolume(bgmVolume);
      
    } catch (e) {
      print('Error playing TTS: $e');
    }
  }
  
  Future<void> _waitForTTSCompletion() async {
    final completer = Completer<void>();
    
    flutterTts.setCompletionHandler(() {
      completer.complete();
    });
    
    // 타임아웃 설정 (최대 10초)
    await completer.future.timeout(
      Duration(seconds: 10),
      onTimeout: () => print('TTS timeout'),
    );
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