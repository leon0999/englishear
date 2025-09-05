// Realtime API 오디오 테스트를 위한 독립 실행 스크립트
// 실행: dart test_realtime_audio.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:async';

void main() async {
  print('🎯 OpenAI Realtime API Audio Test');
  print('================================\n');
  
  // 1. 테스트용 PCM 데이터 생성 (440Hz 사인파)
  print('1. Generating test PCM data...');
  final pcmData = generateTestPCM();
  print('   PCM size: ${pcmData.length} bytes');
  
  // 2. Base64 인코딩 (Realtime API 형식)
  final base64Audio = base64Encode(pcmData);
  print('2. Base64 encoded: ${base64Audio.length} chars');
  
  // 3. Base64 디코딩 테스트
  final decodedPCM = base64Decode(base64Audio);
  print('3. Decoded back: ${decodedPCM.length} bytes');
  
  // 4. WAV 변환
  final wavData = pcmToWav(decodedPCM);
  print('4. WAV conversion: ${wavData.length} bytes');
  
  // 5. 파일 저장
  final file = File('realtime_test.wav');
  await file.writeAsBytes(wavData);
  print('5. Saved to: ${file.absolute.path}');
  
  // 6. 재생 테스트 (Mac)
  if (Platform.isMacOS) {
    print('\n6. Playing audio...');
    final result = await Process.run('afplay', [file.path]);
    if (result.exitCode == 0) {
      print('   ✅ Playback successful!');
    } else {
      print('   ❌ Playback failed: ${result.stderr}');
    }
  }
  
  print('\n✅ Test completed!');
  print('\n💡 Solution for Flutter:');
  print('1. Ensure PCM is 24kHz, 16-bit, mono');
  print('2. Convert PCM to WAV before playing');
  print('3. Use file-based playback, not streaming');
  print('4. Wait for playback completion before cleanup');
}

// PCM 생성 함수
Uint8List generateTestPCM() {
  const sampleRate = 24000;
  const frequency = 440.0;
  const duration = 0.5;
  const amplitude = 0.3;
  
  final numSamples = (sampleRate * duration).toInt();
  final pcmData = Uint8List(numSamples * 2);
  
  for (int i = 0; i < numSamples; i++) {
    final sample = (amplitude * 32767 * 
                   (2 * 3.14159 * frequency * i / sampleRate).sin()).toInt();
    pcmData[i * 2] = sample & 0xFF;
    pcmData[i * 2 + 1] = (sample >> 8) & 0xFF;
  }
  
  return pcmData;
}

// WAV 변환 함수
Uint8List pcmToWav(Uint8List pcmData) {
  const sampleRate = 24000;
  const channels = 1;
  const bitsPerSample = 16;
  
  final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
  final totalDataLen = pcmData.length + 36;
  
  final wavHeader = Uint8List(44);
  final bd = ByteData.view(wavHeader.buffer);
  
  // RIFF header
  wavHeader[0] = 0x52; // R
  wavHeader[1] = 0x49; // I
  wavHeader[2] = 0x46; // F
  wavHeader[3] = 0x46; // F
  
  bd.setUint32(4, totalDataLen, Endian.little);
  
  // WAVE header
  wavHeader[8] = 0x57;  // W
  wavHeader[9] = 0x41;  // A
  wavHeader[10] = 0x56; // V
  wavHeader[11] = 0x45; // E
  
  // fmt subchunk
  wavHeader[12] = 0x66; // f
  wavHeader[13] = 0x6d; // m
  wavHeader[14] = 0x74; // t
  wavHeader[15] = 0x20; // space
  
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little);
  bd.setUint16(22, channels, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, byteRate, Endian.little);
  bd.setUint16(32, channels * (bitsPerSample ~/ 8), Endian.little);
  bd.setUint16(34, bitsPerSample, Endian.little);
  
  // data subchunk
  wavHeader[36] = 0x64; // d
  wavHeader[37] = 0x61; // a
  wavHeader[38] = 0x74; // t
  wavHeader[39] = 0x61; // a
  
  bd.setUint32(40, pcmData.length, Endian.little);
  
  return Uint8List.fromList([...wavHeader, ...pcmData]);
}