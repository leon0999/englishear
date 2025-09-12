import 'dart:typed_data';
import 'dart:math' as math;
import '../core/logger.dart';

/// Processor for adding natural speech characteristics to audio
class NaturalSpeechProcessor {
  // Pause durations for different punctuation marks (in milliseconds)
  static const Map<String, int> PAUSE_DURATIONS = {
    '.': 400,  // End of sentence
    '!': 350,  // Exclamation
    '?': 350,  // Question
    ',': 150,  // Comma
    ':': 200,  // Colon
    ';': 200,  // Semicolon
    '—': 250,  // Em dash
    '…': 300,  // Ellipsis
  };
  
  // Audio processing parameters
  static const int SAMPLE_RATE = 24000;
  static const int BYTES_PER_SAMPLE = 2;
  static const int FADE_DURATION_MS = 20;
  static const int FADE_SAMPLES = (SAMPLE_RATE * FADE_DURATION_MS) ~/ 1000;
  
  /// Process audio with natural pauses based on text
  Future<Uint8List> processWithNaturalPauses(
    Uint8List audioData,
    String? text,
  ) async {
    if (text == null || text.isEmpty) {
      return applyVolumeEnvelope(audioData);
    }
    
    // Get pause duration based on punctuation
    final pauseDuration = _getPauseDuration(text);
    
    if (pauseDuration > 0) {
      AppLogger.debug('Adding ${pauseDuration}ms pause for text ending: "${text.substring(math.max(0, text.length - 5))}"');
      
      // Create silence samples
      final silentSamples = (SAMPLE_RATE * pauseDuration / 1000).round();
      final silence = Uint8List(silentSamples * BYTES_PER_SAMPLE);
      
      // Apply envelope to main audio
      final processedAudio = applyVolumeEnvelope(audioData);
      
      // Combine audio with silence
      final result = Uint8List(processedAudio.length + silence.length);
      result.setRange(0, processedAudio.length, processedAudio);
      result.setRange(processedAudio.length, result.length, silence);
      
      return result;
    }
    
    // Just apply envelope if no pause needed
    return applyVolumeEnvelope(audioData);
  }
  
  /// Get pause duration based on text ending
  int _getPauseDuration(String text) {
    final trimmedText = text.trimRight();
    
    // Check for punctuation marks
    for (final entry in PAUSE_DURATIONS.entries) {
      if (trimmedText.endsWith(entry.key)) {
        return entry.value;
      }
    }
    
    // Check for ellipsis pattern
    if (trimmedText.endsWith('...')) {
      return PAUSE_DURATIONS['…']!;
    }
    
    return 0;
  }
  
  /// Apply smooth volume envelope with fade in/out
  Uint8List applyVolumeEnvelope(Uint8List audioData) {
    if (audioData.length < FADE_SAMPLES * BYTES_PER_SAMPLE * 2) {
      // Too short for fading
      return audioData;
    }
    
    final result = Uint8List.fromList(audioData);
    final numSamples = audioData.length ~/ BYTES_PER_SAMPLE;
    
    // Fade in
    for (int i = 0; i < FADE_SAMPLES && i < numSamples; i++) {
      final fadeGain = i / FADE_SAMPLES;
      _applySampleGain(result, i, fadeGain);
    }
    
    // Fade out
    for (int i = 0; i < FADE_SAMPLES && i < numSamples; i++) {
      final sampleIndex = numSamples - 1 - i;
      final fadeGain = i / FADE_SAMPLES;
      _applySampleGain(result, sampleIndex, fadeGain);
    }
    
    return result;
  }
  
  /// Apply gain to a single sample
  void _applySampleGain(Uint8List data, int sampleIndex, double gain) {
    final byteIndex = sampleIndex * BYTES_PER_SAMPLE;
    if (byteIndex + 1 >= data.length) return;
    
    final sample = (data[byteIndex] | (data[byteIndex + 1] << 8)).toSigned(16);
    final adjusted = (sample * gain).round().clamp(-32768, 32767);
    
    data[byteIndex] = adjusted & 0xFF;
    data[byteIndex + 1] = (adjusted >> 8) & 0xFF;
  }
  
  /// Add breathing sounds between sentences (subtle)
  Uint8List addBreathingSound(int durationMs) {
    final samples = (SAMPLE_RATE * durationMs / 1000).round();
    final breathData = Uint8List(samples * BYTES_PER_SAMPLE);
    
    // Generate very subtle white noise for breathing effect
    final random = math.Random();
    const double breathAmplitude = 500; // Very low amplitude
    
    for (int i = 0; i < samples; i++) {
      // Generate breath-like envelope (inhale-exhale pattern)
      final progress = i / samples;
      double envelope;
      
      if (progress < 0.4) {
        // Inhale (rising)
        envelope = progress / 0.4;
      } else if (progress < 0.6) {
        // Peak
        envelope = 1.0;
      } else {
        // Exhale (falling)
        envelope = (1.0 - progress) / 0.4;
      }
      
      // Apply randomness with envelope
      final sample = (random.nextDouble() - 0.5) * breathAmplitude * envelope;
      final intSample = sample.round().clamp(-32768, 32767);
      
      final byteIndex = i * BYTES_PER_SAMPLE;
      breathData[byteIndex] = intSample & 0xFF;
      breathData[byteIndex + 1] = (intSample >> 8) & 0xFF;
    }
    
    return breathData;
  }
  
  /// Apply prosody adjustments for more natural speech
  Uint8List applyProsody(Uint8List audioData, String? text) {
    if (text == null || text.isEmpty) return audioData;
    
    final result = Uint8List.fromList(audioData);
    final numSamples = audioData.length ~/ BYTES_PER_SAMPLE;
    
    // Detect sentence type and apply appropriate prosody
    if (text.trimRight().endsWith('?')) {
      // Rising intonation for questions
      _applyRisingIntonation(result, numSamples);
    } else if (text.trimRight().endsWith('!')) {
      // Emphatic intonation for exclamations
      _applyEmphaticIntonation(result, numSamples);
    } else {
      // Falling intonation for statements
      _applyFallingIntonation(result, numSamples);
    }
    
    return result;
  }
  
  /// Apply rising intonation (for questions)
  void _applyRisingIntonation(Uint8List data, int numSamples) {
    final startPoint = (numSamples * 0.7).round();
    
    for (int i = startPoint; i < numSamples; i++) {
      final progress = (i - startPoint) / (numSamples - startPoint);
      final pitchShift = 1.0 + (progress * 0.12); // Up to 12% pitch increase
      
      _shiftPitch(data, i, pitchShift);
    }
  }
  
  /// Apply falling intonation (for statements)
  void _applyFallingIntonation(Uint8List data, int numSamples) {
    final startPoint = (numSamples * 0.8).round();
    
    for (int i = startPoint; i < numSamples; i++) {
      final progress = (i - startPoint) / (numSamples - startPoint);
      final pitchShift = 1.0 - (progress * 0.08); // Up to 8% pitch decrease
      
      _shiftPitch(data, i, pitchShift);
    }
  }
  
  /// Apply emphatic intonation (for exclamations)
  void _applyEmphaticIntonation(Uint8List data, int numSamples) {
    // Boost overall energy
    for (int i = 0; i < numSamples; i++) {
      final byteIndex = i * BYTES_PER_SAMPLE;
      if (byteIndex + 1 >= data.length) continue;
      
      final sample = (data[byteIndex] | (data[byteIndex + 1] << 8)).toSigned(16);
      final boosted = (sample * 1.15).round().clamp(-32768, 32767);
      
      data[byteIndex] = boosted & 0xFF;
      data[byteIndex + 1] = (boosted >> 8) & 0xFF;
    }
  }
  
  /// Shift pitch of a sample
  void _shiftPitch(Uint8List data, int sampleIndex, double pitchShift) {
    final byteIndex = sampleIndex * BYTES_PER_SAMPLE;
    if (byteIndex + 1 >= data.length) return;
    
    final sample = (data[byteIndex] | (data[byteIndex + 1] << 8)).toSigned(16);
    final shifted = (sample * pitchShift).round().clamp(-32768, 32767);
    
    data[byteIndex] = shifted & 0xFF;
    data[byteIndex + 1] = (shifted >> 8) & 0xFF;
  }
  
  /// Combine audio chunks with natural transitions
  Uint8List combineWithTransitions(List<Uint8List> chunks) {
    if (chunks.isEmpty) return Uint8List(0);
    if (chunks.length == 1) return chunks[0];
    
    // Calculate total size with small overlaps
    final overlapSamples = math.min(240, chunks[0].length ~/ 20); // 10ms or 5% overlap
    final overlapBytes = overlapSamples * BYTES_PER_SAMPLE;
    
    int totalSize = 0;
    for (int i = 0; i < chunks.length; i++) {
      totalSize += chunks[i].length;
      if (i > 0) {
        totalSize -= overlapBytes; // Subtract overlap
      }
    }
    
    final result = Uint8List(totalSize);
    int offset = 0;
    
    for (int i = 0; i < chunks.length; i++) {
      if (i == 0) {
        // First chunk - copy as is
        result.setRange(0, chunks[i].length, chunks[i]);
        offset = chunks[i].length;
      } else {
        // Crossfade with previous chunk
        final prevEnd = offset - overlapBytes;
        final currStart = 0;
        
        // Crossfade overlap region
        for (int j = 0; j < overlapSamples; j++) {
          final fadeOut = 1.0 - (j / overlapSamples);
          final fadeIn = j / overlapSamples;
          
          final prevIdx = prevEnd + j * BYTES_PER_SAMPLE;
          final currIdx = j * BYTES_PER_SAMPLE;
          
          if (prevIdx + 1 < offset && currIdx + 1 < chunks[i].length) {
            final prevSample = (result[prevIdx] | (result[prevIdx + 1] << 8)).toSigned(16);
            final currSample = (chunks[i][currIdx] | (chunks[i][currIdx + 1] << 8)).toSigned(16);
            
            final mixed = (prevSample * fadeOut + currSample * fadeIn).round();
            final clamped = mixed.clamp(-32768, 32767);
            
            result[prevIdx] = clamped & 0xFF;
            result[prevIdx + 1] = (clamped >> 8) & 0xFF;
          }
        }
        
        // Copy rest of current chunk
        final remainingStart = overlapBytes;
        final remainingLength = chunks[i].length - overlapBytes;
        result.setRange(offset, offset + remainingLength, 
                       chunks[i].sublist(remainingStart));
        offset += remainingLength;
      }
    }
    
    return result;
  }
}