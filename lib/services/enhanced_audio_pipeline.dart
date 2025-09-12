import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import '../core/logger.dart';
import 'sentence_boundary_detector.dart';
import 'multi_engine_tts.dart';

/// Enhanced audio pipeline with RealtimeTTS-inspired features
class EnhancedAudioPipeline {
  final SentenceBoundaryDetector _sentenceDetector = SentenceBoundaryDetector();
  final MultiEngineTTS _tts;
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // Dynamic buffer configuration
  static const int minBufferSize = 2400;  // 50ms at 24kHz mono
  static const int maxBufferSize = 9600;  // 200ms at 24kHz mono
  static const int sampleRate = 24000;
  static const int bytesPerSample = 2; // 16-bit PCM
  
  // Audio processing parameters
  static const double targetRMS = 3276.8; // -20dB
  static const int fadeMs = 10;
  static const int fadeSamples = (sampleRate * fadeMs) ~/ 1000;
  
  final Queue<Uint8List> _audioQueue = Queue();
  final StreamController<double> _volumeController = StreamController.broadcast();
  
  bool _isPlaying = false;
  Timer? _playbackTimer;
  
  // Metrics
  int _totalChunksProcessed = 0;
  int _totalBytesProcessed = 0;
  DateTime? _lastPlaybackTime;
  
  EnhancedAudioPipeline({MultiEngineTTS? tts}) 
    : _tts = tts ?? MultiEngineTTS();
  
  Stream<double> get volumeStream => _volumeController.stream;
  
  /// Process text with sentence-level streaming
  Future<void> processText(String text) async {
    try {
      AppLogger.info('Processing text with enhanced pipeline: ${text.length} chars');
      
      // Split into sentences
      final sentences = _sentenceDetector.processSingleText(text);
      AppLogger.debug('Split into ${sentences.length} sentences');
      
      // Process each sentence
      for (final sentence in sentences) {
        if (sentence.trim().isEmpty) continue;
        
        try {
          await _processSentence(sentence);
        } catch (e) {
          AppLogger.error('Failed to process sentence: $sentence', data: {'error': e.toString()});
        }
      }
      
      // Flush any remaining audio
      await _flushAudioQueue();
      
      AppLogger.success('Text processing complete. Chunks: $_totalChunksProcessed, Bytes: $_totalBytesProcessed');
    } catch (e) {
      AppLogger.error('Pipeline processing failed', data: {'error': e.toString()});
      throw e;
    }
  }
  
  /// Process text stream with real-time sentence detection
  Stream<void> processTextStream(Stream<String> textStream) async* {
    final sentenceStream = _sentenceDetector.processTextStream(textStream);
    
    await for (final sentence in sentenceStream) {
      if (sentence.trim().isEmpty) continue;
      
      try {
        await _processSentence(sentence);
        yield null; // Signal progress
      } catch (e) {
        AppLogger.error('Failed to process streamed sentence', data: {'error': e.toString()});
      }
    }
    
    await _flushAudioQueue();
  }
  
  /// Process a single sentence
  Future<void> _processSentence(String sentence) async {
    AppLogger.debug('Processing sentence: "$sentence"');
    
    // Synthesize audio
    final audioStream = await _tts.synthesize(sentence, options: {
      'speed': '95%',  // Slightly slower for clarity
      'pitch': '0%',
      'volume': '100',
    });
    
    // Process audio chunks
    await for (final chunk in audioStream) {
      await _processAudioChunk(chunk);
    }
  }
  
  /// Process an audio chunk with dynamic buffering
  Future<void> _processAudioChunk(Uint8List chunk) async {
    if (chunk.isEmpty) return;
    
    _totalChunksProcessed++;
    _totalBytesProcessed += chunk.length;
    
    // Apply audio processing
    final processed = _processAudio(chunk);
    
    // Dynamic buffering decision
    if (processed.length < minBufferSize) {
      // Small chunks go to buffer
      _audioQueue.add(processed);
      
      // Check if buffer is ready to play
      final totalSize = _audioQueue.fold<int>(0, (sum, c) => sum + c.length);
      if (totalSize >= minBufferSize) {
        await _playBufferedAudio();
      }
    } else if (processed.length > maxBufferSize) {
      // Large chunks are split
      int offset = 0;
      while (offset < processed.length) {
        final end = min(offset + maxBufferSize, processed.length);
        final subChunk = processed.sublist(offset, end);
        await _playDirectly(subChunk);
        offset = end;
      }
    } else {
      // Medium chunks play directly
      await _playDirectly(processed);
    }
  }
  
  /// Process audio with noise removal and normalization
  Uint8List _processAudio(Uint8List data) {
    if (data.length < 4) return data; // Too small to process
    
    // Step 1: Remove click noise with fade in/out
    final faded = _applyFade(data);
    
    // Step 2: Normalize volume
    final normalized = _normalizeVolume(faded);
    
    // Step 3: Apply noise gate
    final gated = _applyNoiseGate(normalized);
    
    return gated;
  }
  
  /// Apply fade in/out to prevent clicks
  Uint8List _applyFade(Uint8List data) {
    final result = Uint8List.fromList(data);
    final numSamples = data.length ~/ bytesPerSample;
    final fadeLength = min(fadeSamples, numSamples ~/ 4);
    
    // Fade in
    for (int i = 0; i < fadeLength; i++) {
      final idx = i * bytesPerSample;
      if (idx + 1 >= data.length) break;
      
      final sample = _bytesToInt16(data, idx);
      final fadeFactor = i / fadeLength;
      final faded = (sample * fadeFactor).round();
      _int16ToBytes(result, idx, faded);
    }
    
    // Fade out
    for (int i = 0; i < fadeLength; i++) {
      final idx = (numSamples - 1 - i) * bytesPerSample;
      if (idx + 1 >= data.length) break;
      
      final sample = _bytesToInt16(data, idx);
      final fadeFactor = i / fadeLength;
      final faded = (sample * fadeFactor).round();
      _int16ToBytes(result, idx, faded);
    }
    
    return result;
  }
  
  /// Normalize audio volume using RMS
  Uint8List _normalizeVolume(Uint8List data) {
    final result = Uint8List.fromList(data);
    final numSamples = data.length ~/ bytesPerSample;
    
    // Calculate RMS
    double rms = 0;
    double peak = 0;
    for (int i = 0; i < numSamples; i++) {
      final sample = _bytesToInt16(data, i * bytesPerSample);
      rms += sample * sample;
      peak = max(peak, sample.abs().toDouble());
    }
    rms = sqrt(rms / numSamples);
    
    // Skip if silence
    if (rms < 100) return result;
    
    // Calculate gain (with peak limiting)
    double gain = targetRMS / max(rms, 1.0);
    
    // Limit gain to prevent clipping
    if (peak * gain > 32000) {
      gain = 32000 / peak;
    }
    
    // Apply gain
    for (int i = 0; i < numSamples; i++) {
      final idx = i * bytesPerSample;
      final sample = _bytesToInt16(data, idx);
      final adjusted = (sample * gain).round().clamp(-32768, 32767);
      _int16ToBytes(result, idx, adjusted);
    }
    
    // Report volume level
    _volumeController.add(rms / 32768.0);
    
    return result;
  }
  
  /// Apply noise gate to remove low-level noise
  Uint8List _applyNoiseGate(Uint8List data) {
    const double threshold = 0.01; // -40dB
    final result = Uint8List.fromList(data);
    final numSamples = data.length ~/ bytesPerSample;
    
    for (int i = 0; i < numSamples; i++) {
      final idx = i * bytesPerSample;
      final sample = _bytesToInt16(data, idx);
      final normalized = sample / 32768.0;
      
      if (normalized.abs() < threshold) {
        _int16ToBytes(result, idx, 0); // Gate closed
      }
    }
    
    return result;
  }
  
  /// Play buffered audio
  Future<void> _playBufferedAudio() async {
    if (_audioQueue.isEmpty) return;
    
    // Combine all buffered chunks
    final chunks = _audioQueue.toList();
    _audioQueue.clear();
    
    final totalLength = chunks.fold<int>(0, (sum, c) => sum + c.length);
    final combined = Uint8List(totalLength);
    
    int offset = 0;
    for (final chunk in chunks) {
      combined.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    
    await _playDirectly(combined);
  }
  
  /// Play audio directly
  Future<void> _playDirectly(Uint8List audioData) async {
    if (audioData.isEmpty) return;
    
    try {
      _isPlaying = true;
      _lastPlaybackTime = DateTime.now();
      
      // Convert to WAV format for audioplayers
      final wavData = _createWavFile(audioData);
      
      // Play the audio
      await _audioPlayer.play(BytesSource(wavData));
      
      // Calculate playback duration
      final durationMs = (audioData.length / bytesPerSample / sampleRate * 1000).round();
      
      // Wait for playback to complete
      await Future.delayed(Duration(milliseconds: durationMs));
      
      _isPlaying = false;
    } catch (e) {
      AppLogger.error('Audio playback failed', data: {'error': e.toString()});
      _isPlaying = false;
    }
  }
  
  /// Flush any remaining audio in the queue
  Future<void> _flushAudioQueue() async {
    if (_audioQueue.isNotEmpty) {
      await _playBufferedAudio();
    }
  }
  
  /// Create a WAV file from PCM data
  Uint8List _createWavFile(Uint8List pcmData) {
    final dataSize = pcmData.length;
    final fileSize = dataSize + 44; // WAV header is 44 bytes
    
    final wav = Uint8List(fileSize);
    final view = ByteData.view(wav.buffer);
    
    // RIFF header
    wav.setRange(0, 4, utf8.encode('RIFF'));
    view.setUint32(4, fileSize - 8, Endian.little);
    wav.setRange(8, 12, utf8.encode('WAVE'));
    
    // fmt chunk
    wav.setRange(12, 16, utf8.encode('fmt '));
    view.setUint32(16, 16, Endian.little); // fmt chunk size
    view.setUint16(20, 1, Endian.little); // PCM format
    view.setUint16(22, 1, Endian.little); // Mono
    view.setUint32(24, sampleRate, Endian.little);
    view.setUint32(28, sampleRate * bytesPerSample, Endian.little); // Byte rate
    view.setUint16(32, bytesPerSample, Endian.little); // Block align
    view.setUint16(34, 16, Endian.little); // Bits per sample
    
    // data chunk
    wav.setRange(36, 40, utf8.encode('data'));
    view.setUint32(40, dataSize, Endian.little);
    wav.setRange(44, fileSize, pcmData);
    
    return wav;
  }
  
  /// Convert bytes to int16
  int _bytesToInt16(Uint8List data, int offset) {
    if (offset + 1 >= data.length) return 0;
    return (data[offset] | (data[offset + 1] << 8)).toSigned(16);
  }
  
  /// Convert int16 to bytes
  void _int16ToBytes(Uint8List data, int offset, int value) {
    if (offset + 1 >= data.length) return;
    data[offset] = value & 0xFF;
    data[offset + 1] = (value >> 8) & 0xFF;
  }
  
  /// Stop playback
  Future<void> stop() async {
    _isPlaying = false;
    _playbackTimer?.cancel();
    await _audioPlayer.stop();
    _audioQueue.clear();
    _sentenceDetector.clear();
  }
  
  /// Dispose resources
  void dispose() {
    stop();
    _audioPlayer.dispose();
    _volumeController.close();
  }
  
  /// Get pipeline metrics
  Map<String, dynamic> getMetrics() {
    return {
      'totalChunksProcessed': _totalChunksProcessed,
      'totalBytesProcessed': _totalBytesProcessed,
      'queueSize': _audioQueue.length,
      'isPlaying': _isPlaying,
      'lastPlaybackTime': _lastPlaybackTime?.toIso8601String(),
      'availableEngines': _tts.getAvailableEngines(),
    };
  }
}