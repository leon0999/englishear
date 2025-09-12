import 'dart:typed_data';
import 'dart:math' as math;
import '../core/logger.dart';

/// Audio post-processing service to improve voice quality
/// Reduces robotic sound and adds warmth to Jupiter's voice
class AudioPostProcessor {
  // Processing parameters
  static const double WARMTH_FACTOR = 0.7; // Low-pass filter strength
  static const double COMPRESSION_THRESHOLD = 20000; // Dynamic range compression threshold
  static const double COMPRESSION_RATIO = 0.5; // Compression ratio above threshold
  static const int SAMPLE_RATE = 24000;
  
  // EQ bands for voice enhancement
  static const double LOW_FREQ_BOOST = 1.1; // Boost low frequencies for warmth
  static const double MID_FREQ_CUT = 0.95; // Slightly cut harsh mids
  static const double HIGH_FREQ_SMOOTH = 0.85; // Smooth high frequencies
  
  /// Apply full post-processing pipeline
  Uint8List processAudio(Uint8List input) {
    if (input.isEmpty || input.length < 4) return input;
    
    var processed = Uint8List.fromList(input);
    
    // Step 1: Apply warmth filter (low-pass)
    processed = applyWarmthFilter(processed);
    
    // Step 2: Apply dynamic range compression
    processed = applyCompression(processed);
    
    // Step 3: Apply EQ for voice enhancement
    processed = applyVoiceEQ(processed);
    
    // Step 4: Apply subtle reverb for naturalness
    processed = applySubtleReverb(processed);
    
    // Step 5: Final normalization
    processed = normalizeAudio(processed);
    
    return processed;
  }
  
  /// Apply warmth filter to reduce mechanical sound
  Uint8List applyWarmthFilter(Uint8List input) {
    final output = Uint8List.fromList(input);
    final samples = input.length ~/ 2;
    
    // Butterworth low-pass filter coefficients (cutoff ~8kHz at 24kHz sample rate)
    const double a0 = 0.2929;
    const double a1 = 0.5858;
    const double a2 = 0.2929;
    const double b1 = -0.0000;
    const double b2 = 0.1716;
    
    // Filter state
    double x1 = 0, x2 = 0;
    double y1 = 0, y2 = 0;
    
    for (int i = 0; i < samples; i++) {
      final sample = (input[i * 2] | (input[i * 2 + 1] << 8)).toSigned(16).toDouble();
      
      // Apply filter
      final filtered = a0 * sample + a1 * x1 + a2 * x2 - b1 * y1 - b2 * y2;
      
      // Update state
      x2 = x1;
      x1 = sample;
      y2 = y1;
      y1 = filtered;
      
      // Mix with original for subtlety
      final mixed = sample * (1 - WARMTH_FACTOR) + filtered * WARMTH_FACTOR;
      
      final result = mixed.round().clamp(-32768, 32767);
      output[i * 2] = result & 0xFF;
      output[i * 2 + 1] = (result >> 8) & 0xFF;
    }
    
    return output;
  }
  
  /// Apply dynamic range compression for consistent volume
  Uint8List applyCompression(Uint8List input) {
    final output = Uint8List.fromList(input);
    final samples = input.length ~/ 2;
    
    // Attack and release times
    const double attackTime = 0.005; // 5ms
    const double releaseTime = 0.050; // 50ms
    final attackCoeff = math.exp(-1.0 / (SAMPLE_RATE * attackTime));
    final releaseCoeff = math.exp(-1.0 / (SAMPLE_RATE * releaseTime));
    
    double envelope = 0;
    
    for (int i = 0; i < samples; i++) {
      final sample = (input[i * 2] | (input[i * 2 + 1] << 8)).toSigned(16).toDouble();
      final absSample = sample.abs();
      
      // Update envelope
      final targetEnv = absSample;
      final rate = targetEnv > envelope ? attackCoeff : releaseCoeff;
      envelope = targetEnv + (envelope - targetEnv) * rate;
      
      // Calculate gain reduction
      double gain = 1.0;
      if (envelope > COMPRESSION_THRESHOLD) {
        final excess = envelope - COMPRESSION_THRESHOLD;
        final compressedExcess = excess * COMPRESSION_RATIO;
        gain = (COMPRESSION_THRESHOLD + compressedExcess) / envelope;
      }
      
      // Apply gain
      final compressed = (sample * gain).round().clamp(-32768, 32767);
      
      output[i * 2] = compressed & 0xFF;
      output[i * 2 + 1] = (compressed >> 8) & 0xFF;
    }
    
    return output;
  }
  
  /// Apply voice-optimized EQ
  Uint8List applyVoiceEQ(Uint8List input) {
    final output = Uint8List.fromList(input);
    final samples = input.length ~/ 2;
    
    // Simple 3-band EQ using biquad filters
    // Low shelf for warmth (200Hz)
    // Mid peak/dip for presence (2kHz)
    // High shelf for air (8kHz)
    
    for (int i = 1; i < samples - 1; i++) {
      final prev = (input[(i - 1) * 2] | (input[(i - 1) * 2 + 1] << 8)).toSigned(16).toDouble();
      final curr = (input[i * 2] | (input[i * 2 + 1] << 8)).toSigned(16).toDouble();
      final next = (input[(i + 1) * 2] | (input[(i + 1) * 2 + 1] << 8)).toSigned(16).toDouble();
      
      // Simplified frequency separation
      final low = (prev + curr * 2 + next) / 4; // Low-pass component
      final high = curr - low; // High-pass component
      final mid = curr - (low * 0.3 + high * 0.3); // Mid component
      
      // Apply EQ gains
      final eqResult = low * LOW_FREQ_BOOST + 
                      mid * MID_FREQ_CUT + 
                      high * HIGH_FREQ_SMOOTH;
      
      final result = eqResult.round().clamp(-32768, 32767);
      output[i * 2] = result & 0xFF;
      output[i * 2 + 1] = (result >> 8) & 0xFF;
    }
    
    return output;
  }
  
  /// Apply subtle reverb for naturalness
  Uint8List applySubtleReverb(Uint8List input) {
    final output = Uint8List.fromList(input);
    final samples = input.length ~/ 2;
    
    // Simple comb filter reverb
    const int delayMs = 30; // 30ms delay
    final delaySamples = (SAMPLE_RATE * delayMs / 1000).round();
    const double decay = 0.15; // Very subtle reverb
    const double mix = 0.1; // 10% wet signal
    
    // Create delay buffer
    final delayBuffer = List<double>.filled(delaySamples, 0);
    int delayIndex = 0;
    
    for (int i = 0; i < samples; i++) {
      final sample = (input[i * 2] | (input[i * 2 + 1] << 8)).toSigned(16).toDouble();
      
      // Get delayed sample
      final delayed = delayBuffer[delayIndex];
      
      // Update delay buffer
      delayBuffer[delayIndex] = sample + delayed * decay;
      delayIndex = (delayIndex + 1) % delaySamples;
      
      // Mix dry and wet signals
      final mixed = sample * (1 - mix) + delayed * mix;
      
      final result = mixed.round().clamp(-32768, 32767);
      output[i * 2] = result & 0xFF;
      output[i * 2 + 1] = (result >> 8) & 0xFF;
    }
    
    return output;
  }
  
  /// Normalize audio to optimal level
  Uint8List normalizeAudio(Uint8List input) {
    final output = Uint8List.fromList(input);
    final samples = input.length ~/ 2;
    
    // Find peak level
    double peak = 0;
    for (int i = 0; i < samples; i++) {
      final sample = (input[i * 2] | (input[i * 2 + 1] << 8)).toSigned(16).abs().toDouble();
      peak = math.max(peak, sample);
    }
    
    if (peak < 1000) return output; // Too quiet, skip normalization
    
    // Calculate normalization gain (target: 75% of max)
    const double targetPeak = 32768 * 0.75;
    final gain = targetPeak / peak;
    
    // Limit gain to prevent over-amplification
    final limitedGain = math.min(gain, 2.0);
    
    // Apply normalization
    for (int i = 0; i < samples; i++) {
      final sample = (input[i * 2] | (input[i * 2 + 1] << 8)).toSigned(16);
      final normalized = (sample * limitedGain).round().clamp(-32768, 32767);
      
      output[i * 2] = normalized & 0xFF;
      output[i * 2 + 1] = (normalized >> 8) & 0xFF;
    }
    
    return output;
  }
  
  /// Analyze audio characteristics for diagnostics
  Map<String, dynamic> analyzeAudio(Uint8List audio) {
    final samples = audio.length ~/ 2;
    if (samples == 0) return {'error': 'Empty audio'};
    
    double sum = 0;
    double peak = 0;
    double rms = 0;
    
    for (int i = 0; i < samples; i++) {
      final sample = (audio[i * 2] | (audio[i * 2 + 1] << 8)).toSigned(16).toDouble();
      sum += sample.abs();
      peak = math.max(peak, sample.abs());
      rms += sample * sample;
    }
    
    rms = math.sqrt(rms / samples);
    final avgLevel = sum / samples;
    
    return {
      'peakLevel': peak,
      'rmsLevel': rms,
      'avgLevel': avgLevel,
      'peakDb': 20 * math.log(peak / 32768) / math.ln10,
      'rmsDb': 20 * math.log(rms / 32768) / math.ln10,
      'duration': samples / SAMPLE_RATE,
      'samples': samples,
    };
  }
}