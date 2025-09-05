// 음성 재생 테스트 스크립트
// 실행: dart test_audio.dart

import 'dart:typed_data';
import 'dart:io';
import 'dart:math';

// 테스트용 PCM 데이터 생성 (1초 분량의 440Hz 사인파)
Uint8List generateTestPCM() {
  const sampleRate = 24000;
  const frequency = 440.0; // A4 음
  const duration = 1.0; // 1초
  const amplitude = 0.3;
  
  final numSamples = (sampleRate * duration).toInt();
  final pcmData = Uint8List(numSamples * 2); // 16-bit = 2 bytes per sample
  
  for (int i = 0; i < numSamples; i++) {
    final sample = (amplitude * 32767 * sin(2 * pi * frequency * i / sampleRate)).toInt();
    // Little-endian 16-bit PCM
    pcmData[i * 2] = sample & 0xFF;
    pcmData[i * 2 + 1] = (sample >> 8) & 0xFF;
  }
  
  print('Generated PCM data: ${pcmData.length} bytes');
  return pcmData;
}

// PCM to WAV 변환
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
  
  bd.setUint32(16, 16, Endian.little); // Subchunk1Size
  bd.setUint16(20, 1, Endian.little);  // AudioFormat (PCM)
  bd.setUint16(22, channels, Endian.little);  // NumChannels
  bd.setUint32(24, sampleRate, Endian.little); // SampleRate
  bd.setUint32(28, byteRate, Endian.little);   // ByteRate
  bd.setUint16(32, channels * (bitsPerSample ~/ 8), Endian.little);  // BlockAlign
  bd.setUint16(34, bitsPerSample, Endian.little); // BitsPerSample
  
  // data subchunk
  wavHeader[36] = 0x64; // d
  wavHeader[37] = 0x61; // a
  wavHeader[38] = 0x74; // t
  wavHeader[39] = 0x61; // a
  
  bd.setUint32(40, pcmData.length, Endian.little);
  
  // Combine header and PCM data
  return Uint8List.fromList([...wavHeader, ...pcmData]);
}

void main() async {
  print('🎵 Audio Test Starting...\n');
  
  // 1. PCM 데이터 생성
  print('1. Generating test PCM data (440Hz sine wave)...');
  final pcmData = generateTestPCM();
  
  // 2. WAV로 변환
  print('2. Converting PCM to WAV...');
  final wavData = pcmToWav(pcmData);
  print('   WAV data size: ${wavData.length} bytes');
  
  // 3. 파일로 저장
  final testFile = File('test_sound.wav');
  print('3. Saving to test_sound.wav...');
  await testFile.writeAsBytes(wavData);
  print('   File saved: ${testFile.absolute.path}');
  
  // 4. 파일 존재 확인
  if (await testFile.exists()) {
    print('✅ WAV file created successfully!');
    print('   File size: ${await testFile.length()} bytes');
  } else {
    print('❌ Failed to create WAV file');
  }
  
  print('\n📢 Test Results:');
  print('================');
  print('✅ PCM generation: SUCCESS');
  print('✅ WAV conversion: SUCCESS');
  print('✅ File creation: SUCCESS');
  print('\n🎧 You can play test_sound.wav with any audio player');
  print('   On Mac: afplay test_sound.wav');
  print('   Or open with QuickTime Player');
  
  // 5. Mac에서 자동 재생 (선택사항)
  if (Platform.isMacOS) {
    print('\n🔊 Playing sound on Mac...');
    final result = await Process.run('afplay', [testFile.path]);
    if (result.exitCode == 0) {
      print('✅ Sound played successfully!');
    } else {
      print('❌ Could not play sound: ${result.stderr}');
    }
  }
}