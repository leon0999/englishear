// lib/utils/audio_utils.dart

import 'dart:convert' as convert;
import 'dart:typed_data';

/// PCM 오디오 데이터를 WAV 형식으로 변환하는 유틸리티
class AudioUtils {
  /// PCM 데이터를 WAV 파일 형식으로 변환
  /// 
  /// OpenAI Realtime API는 16비트 PCM, 24kHz, 모노 형식을 사용
  static Uint8List pcmToWav(
    Uint8List pcmData, {
    int sampleRate = 24000,
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final int dataSize = pcmData.length;
    final int fileSize = dataSize + 36; // WAV 헤더는 44바이트, 파일 크기는 총 크기 - 8

    // WAV 헤더 생성
    final header = ByteData(44);
    
    // RIFF 헤더
    header.setUint32(0, 0x46464952, Endian.big); // "RIFF"
    header.setUint32(4, fileSize, Endian.little); // 파일 크기
    header.setUint32(8, 0x45564157, Endian.big); // "WAVE"
    
    // fmt 서브청크
    header.setUint32(12, 0x20746d66, Endian.big); // "fmt "
    header.setUint32(16, 16, Endian.little); // fmt 청크 크기
    header.setUint16(20, 1, Endian.little); // PCM 포맷
    header.setUint16(22, channels, Endian.little); // 채널 수
    header.setUint32(24, sampleRate, Endian.little); // 샘플 레이트
    header.setUint32(28, sampleRate * channels * bitsPerSample ~/ 8, Endian.little); // 바이트 레이트
    header.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little); // 블록 정렬
    header.setUint16(34, bitsPerSample, Endian.little); // 샘플당 비트
    
    // data 서브청크
    header.setUint32(36, 0x61746164, Endian.big); // "data"
    header.setUint32(40, dataSize, Endian.little); // 데이터 크기
    
    // 헤더와 PCM 데이터 결합
    return Uint8List.fromList([
      ...header.buffer.asUint8List(),
      ...pcmData,
    ]);
  }

  /// base64 인코딩된 PCM 데이터를 WAV로 변환
  static Uint8List base64PcmToWav(String base64Audio) {
    final pcmData = convert.base64Decode(base64Audio);
    return pcmToWav(pcmData);
  }

  /// WAV 데이터를 Data URI로 변환
  static String wavToDataUri(Uint8List wavData) {
    final base64Wav = convert.base64Encode(wavData);
    return 'data:audio/wav;base64,$base64Wav';
  }

  /// base64 PCM을 바로 재생 가능한 Data URI로 변환
  static String pcmToPlayableDataUri(String base64Pcm) {
    final wavData = base64PcmToWav(base64Pcm);
    return wavToDataUri(wavData);
  }
}