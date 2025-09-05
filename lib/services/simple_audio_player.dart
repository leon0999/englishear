import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'package:path_provider/path_provider.dart';
import '../utils/audio_utils.dart';
import '../core/logger.dart';

/// 간단한 오디오 재생 서비스 (just_audio 없이 네이티브 플레이어 사용)
class SimpleAudioPlayer {
  final Queue<Uint8List> _audioQueue = Queue<Uint8List>();
  bool _isPlaying = false;
  
  /// 오디오 데이터 추가
  void addAudioData(Uint8List pcmData) {
    if (pcmData.isEmpty) return;
    
    AppLogger.info('📥 Adding audio to queue: ${pcmData.length} bytes');
    _audioQueue.add(pcmData);
    
    if (!_isPlaying) {
      _playNext();
    }
  }
  
  /// 다음 오디오 재생
  Future<void> _playNext() async {
    if (_audioQueue.isEmpty) {
      _isPlaying = false;
      return;
    }
    
    _isPlaying = true;
    final pcmData = _audioQueue.removeFirst();
    
    try {
      // PCM을 WAV로 변환
      final wavData = AudioUtils.pcmToWav(pcmData);
      
      // 임시 파일 생성
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.wav');
      await tempFile.writeAsBytes(wavData);
      
      AppLogger.info('🎵 Playing WAV file: ${tempFile.path}');
      
      // macOS/iOS에서 네이티브 플레이어로 재생
      if (Platform.isMacOS) {
        // macOS: afplay 사용
        final result = await Process.run('afplay', [tempFile.path]);
        if (result.exitCode != 0) {
          AppLogger.error('Failed to play audio: ${result.stderr}');
        }
      } else if (Platform.isIOS) {
        // iOS: AVAudioPlayer를 사용하는 것이 좋지만, 
        // Flutter Sound 대신 간단한 대안 필요
        AppLogger.info('📱 iOS playback needs native implementation');
        
        // 임시 해결책: 파일을 유지하고 다음 청크 재생
        await Future.delayed(const Duration(seconds: 1));
      }
      
      // 파일 정리
      await Future.delayed(const Duration(milliseconds: 100));
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      
      // 다음 청크 재생
      if (_audioQueue.isNotEmpty) {
        await _playNext();
      } else {
        _isPlaying = false;
      }
      
    } catch (e) {
      AppLogger.error('Error playing audio', e);
      _isPlaying = false;
    }
  }
  
  /// 큐 클리어
  void clearQueue() {
    _audioQueue.clear();
    _isPlaying = false;
  }
}