import 'dart:typed_data';

/// Helper class for converting audio formats
class AudioFormatHelper {
  /// Convert PCM16 raw audio data to WAV format with proper headers
  static Uint8List pcmToWav(Uint8List pcmData) {
    // Audio parameters for OpenAI Realtime API
    const int sampleRate = 24000;
    const int channels = 1;
    const int bitsPerSample = 16;
    
    // Calculate WAV format parameters
    final int byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final int blockAlign = channels * bitsPerSample ~/ 8;
    final int dataSize = pcmData.length;
    final int fileSize = dataSize + 36; // Total size minus 8 bytes for RIFF header
    
    // Create WAV header (44 bytes)
    final wavHeader = ByteData(44);
    
    // RIFF header (12 bytes)
    wavHeader.setUint8(0, 0x52); // 'R'
    wavHeader.setUint8(1, 0x49); // 'I'
    wavHeader.setUint8(2, 0x46); // 'F'
    wavHeader.setUint8(3, 0x46); // 'F'
    wavHeader.setUint32(4, fileSize, Endian.little);
    wavHeader.setUint8(8, 0x57);  // 'W'
    wavHeader.setUint8(9, 0x41);  // 'A'
    wavHeader.setUint8(10, 0x56); // 'V'
    wavHeader.setUint8(11, 0x45); // 'E'
    
    // fmt chunk (24 bytes)
    wavHeader.setUint8(12, 0x66); // 'f'
    wavHeader.setUint8(13, 0x6D); // 'm'
    wavHeader.setUint8(14, 0x74); // 't'
    wavHeader.setUint8(15, 0x20); // ' ' (space)
    wavHeader.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    wavHeader.setUint16(20, 1, Endian.little);  // AudioFormat (1 = PCM)
    wavHeader.setUint16(22, channels, Endian.little);
    wavHeader.setUint32(24, sampleRate, Endian.little);
    wavHeader.setUint32(28, byteRate, Endian.little);
    wavHeader.setUint16(32, blockAlign, Endian.little);
    wavHeader.setUint16(34, bitsPerSample, Endian.little);
    
    // data chunk header (8 bytes)
    wavHeader.setUint8(36, 0x64); // 'd'
    wavHeader.setUint8(37, 0x61); // 'a'
    wavHeader.setUint8(38, 0x74); // 't'
    wavHeader.setUint8(39, 0x61); // 'a'
    wavHeader.setUint32(40, dataSize, Endian.little);
    
    // Combine header and PCM data
    final wavData = Uint8List(44 + pcmData.length);
    wavData.setRange(0, 44, wavHeader.buffer.asUint8List());
    wavData.setRange(44, wavData.length, pcmData);
    
    return wavData;
  }
  
  /// Check if audio data already has WAV header
  static bool hasWavHeader(Uint8List data) {
    if (data.length < 4) return false;
    
    // Check for RIFF signature
    return data[0] == 0x52 && // 'R'
           data[1] == 0x49 && // 'I'
           data[2] == 0x46 && // 'F'
           data[3] == 0x46;   // 'F'
  }
  
  /// Validate PCM data
  static bool isValidPCMData(Uint8List data) {
    // PCM data should have even number of bytes (16-bit samples)
    if (data.isEmpty || data.length % 2 != 0) return false;
    
    // Minimum size check (at least 100 samples)
    if (data.length < 200) return false;
    
    return true;
  }
  
  /// Extract PCM data from WAV format
  static Uint8List? extractPCMFromWav(Uint8List wavData) {
    if (!hasWavHeader(wavData)) return null;
    if (wavData.length < 44) return null;
    
    // Skip header and return PCM data
    return wavData.sublist(44);
  }
}