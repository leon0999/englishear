import 'dart:typed_data';

class AudioUtils {
  /// PCM to WAV conversion for audio playback
  /// Converts 24kHz 16-bit mono PCM data to WAV format
  static Uint8List pcmToWav(
    Uint8List pcmData, {
    int sampleRate = 24000,
    int channels = 1,
    int bitsPerSample = 16,
  }) {
    final int byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    final int totalDataLen = pcmData.length + 36;
    
    final Uint8List wavHeader = Uint8List(44);
    final ByteData bd = ByteData.view(wavHeader.buffer);
    
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
}