import 'dart:typed_data';
import 'dart:collection';
import '../core/logger.dart';
import 'improved_audio_service.dart';

/// Service for buffering audio chunks at sentence boundaries
/// Provides more natural speech playback by playing complete sentences
class SentenceBufferService {
  final Map<int, List<Uint8List>> _sentenceBuffers = {};
  final Map<int, String> _sentenceTexts = {};
  int _currentSentenceId = 0;
  int _playbackSentenceId = 0;
  
  final ImprovedAudioService _audioService;
  
  // Sentence detection
  static final RegExp _sentenceEndPattern = RegExp(r'[.!?]\s*$');
  static final RegExp _midSentencePattern = RegExp(r'[,;:]\s*$');
  
  // Buffer management
  static const int MAX_BUFFER_SENTENCES = 3;
  static const int INTER_SENTENCE_PAUSE_MS = 200; // Natural pause between sentences
  static const int INTER_PHRASE_PAUSE_MS = 100; // Pause at commas/semicolons
  
  // Current accumulation
  final StringBuffer _currentTextBuffer = StringBuffer();
  bool _isProcessingSentence = false;
  
  SentenceBufferService(this._audioService);
  
  /// Process incoming audio chunk with its corresponding text
  Future<void> processAudioChunk(String text, Uint8List audioChunk) async {
    // Add text to current buffer
    _currentTextBuffer.write(text);
    final currentText = _currentTextBuffer.toString();
    
    // Store audio chunk for current sentence
    _sentenceBuffers[_currentSentenceId] ??= [];
    _sentenceBuffers[_currentSentenceId]!.add(audioChunk);
    
    // Check for sentence boundaries
    if (_sentenceEndPattern.hasMatch(currentText)) {
      // Complete sentence detected
      AppLogger.info('📝 Complete sentence detected: "$currentText"');
      _sentenceTexts[_currentSentenceId] = currentText;
      
      // Clear text buffer for next sentence
      _currentTextBuffer.clear();
      
      // Play the complete sentence
      await _playCompleteSentence(_currentSentenceId);
      
      // Move to next sentence
      _currentSentenceId++;
      
    } else if (_midSentencePattern.hasMatch(currentText) && 
               _sentenceBuffers[_currentSentenceId]!.length > 3) {
      // Natural pause point within sentence (comma, semicolon)
      AppLogger.debug('Pause point detected in sentence');
      
      // Play accumulated chunks with a small pause after
      await _playPartialSentence(_currentSentenceId, addPause: true);
    }
    
    // Clean up old buffers
    _cleanupOldBuffers();
  }
  
  /// Play a complete sentence with natural intonation
  Future<void> _playCompleteSentence(int sentenceId) async {
    if (_isProcessingSentence) {
      AppLogger.warning('Already processing a sentence, queuing...');
      return;
    }
    
    _isProcessingSentence = true;
    
    try {
      final chunks = _sentenceBuffers[sentenceId];
      if (chunks == null || chunks.isEmpty) {
        AppLogger.warning('No audio chunks for sentence $sentenceId');
        return;
      }
      
      final sentenceText = _sentenceTexts[sentenceId] ?? '';
      AppLogger.info('🔊 Playing complete sentence: "$sentenceText"');
      
      // Combine all chunks for the sentence
      final combined = _combineChunks(chunks);
      
      // Apply sentence-level audio processing
      final processed = _processSentenceAudio(combined, sentenceText);
      
      // Play the processed sentence
      _audioService.addAudioChunk(processed, chunkId: 'sentence_$sentenceId');
      
      // Add natural pause after sentence
      await Future.delayed(Duration(milliseconds: INTER_SENTENCE_PAUSE_MS));
      
      // Clean up played sentence
      _sentenceBuffers.remove(sentenceId);
      _sentenceTexts.remove(sentenceId);
      
    } catch (e) {
      AppLogger.error('Failed to play sentence $sentenceId', e);
    } finally {
      _isProcessingSentence = false;
    }
  }
  
  /// Play partial sentence (up to a pause point)
  Future<void> _playPartialSentence(int sentenceId, {bool addPause = false}) async {
    final chunks = _sentenceBuffers[sentenceId];
    if (chunks == null || chunks.isEmpty) return;
    
    // Play accumulated chunks
    final combined = _combineChunks(chunks);
    _audioService.addAudioChunk(combined, chunkId: 'partial_$sentenceId');
    
    if (addPause) {
      await Future.delayed(Duration(milliseconds: INTER_PHRASE_PAUSE_MS));
    }
    
    // Clear played chunks but keep the sentence ID active
    _sentenceBuffers[sentenceId]!.clear();
  }
  
  /// Combine multiple audio chunks into one
  Uint8List _combineChunks(List<Uint8List> chunks) {
    final totalLength = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final combined = Uint8List(totalLength);
    
    int offset = 0;
    for (final chunk in chunks) {
      combined.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    
    return combined;
  }
  
  /// Process sentence-level audio for natural intonation
  Uint8List _processSentenceAudio(Uint8List audio, String text) {
    final processed = Uint8List.fromList(audio);
    
    // Apply intonation patterns based on sentence type
    if (text.endsWith('?')) {
      // Rising intonation for questions
      _applyRisingIntonation(processed);
    } else if (text.endsWith('!')) {
      // Emphatic intonation for exclamations
      _applyEmphaticIntonation(processed);
    } else {
      // Falling intonation for statements
      _applyFallingIntonation(processed);
    }
    
    // Apply warmth filter to reduce robotic sound
    _applyWarmthFilter(processed);
    
    return processed;
  }
  
  /// Apply rising intonation pattern (for questions)
  void _applyRisingIntonation(Uint8List audio) {
    final samples = audio.length ~/ 2;
    final riseStart = (samples * 0.7).round(); // Start rise at 70%
    
    for (int i = riseStart; i < samples; i++) {
      final progress = (i - riseStart) / (samples - riseStart);
      final pitchShift = 1.0 + (progress * 0.15); // Up to 15% pitch increase
      
      final sample = (audio[i * 2] | (audio[i * 2 + 1] << 8)).toSigned(16);
      final shifted = (sample * pitchShift).round().clamp(-32768, 32767);
      
      audio[i * 2] = shifted & 0xFF;
      audio[i * 2 + 1] = (shifted >> 8) & 0xFF;
    }
  }
  
  /// Apply falling intonation pattern (for statements)
  void _applyFallingIntonation(Uint8List audio) {
    final samples = audio.length ~/ 2;
    final fallStart = (samples * 0.8).round(); // Start fall at 80%
    
    for (int i = fallStart; i < samples; i++) {
      final progress = (i - fallStart) / (samples - fallStart);
      final pitchShift = 1.0 - (progress * 0.1); // Up to 10% pitch decrease
      
      final sample = (audio[i * 2] | (audio[i * 2 + 1] << 8)).toSigned(16);
      final shifted = (sample * pitchShift).round().clamp(-32768, 32767);
      
      audio[i * 2] = shifted & 0xFF;
      audio[i * 2 + 1] = (shifted >> 8) & 0xFF;
    }
  }
  
  /// Apply emphatic intonation (for exclamations)
  void _applyEmphaticIntonation(Uint8List audio) {
    final samples = audio.length ~/ 2;
    
    // Boost overall volume slightly
    for (int i = 0; i < samples; i++) {
      final sample = (audio[i * 2] | (audio[i * 2 + 1] << 8)).toSigned(16);
      final boosted = (sample * 1.1).round().clamp(-32768, 32767);
      
      audio[i * 2] = boosted & 0xFF;
      audio[i * 2 + 1] = (boosted >> 8) & 0xFF;
    }
  }
  
  /// Apply warmth filter to reduce mechanical sound
  void _applyWarmthFilter(Uint8List audio) {
    final samples = audio.length ~/ 2;
    
    // Simple low-pass filter for warmth
    for (int i = 1; i < samples - 1; i++) {
      final prev = (audio[(i - 1) * 2] | (audio[(i - 1) * 2 + 1] << 8)).toSigned(16);
      final curr = (audio[i * 2] | (audio[i * 2 + 1] << 8)).toSigned(16);
      final next = (audio[(i + 1) * 2] | (audio[(i + 1) * 2 + 1] << 8)).toSigned(16);
      
      // Weighted average (smoothing)
      final smoothed = (prev * 0.25 + curr * 0.5 + next * 0.25).round();
      
      audio[i * 2] = smoothed & 0xFF;
      audio[i * 2 + 1] = (smoothed >> 8) & 0xFF;
    }
  }
  
  /// Clean up old sentence buffers
  void _cleanupOldBuffers() {
    // Remove sentences that are too far behind
    final oldestToKeep = _currentSentenceId - MAX_BUFFER_SENTENCES;
    
    _sentenceBuffers.removeWhere((id, _) => id < oldestToKeep);
    _sentenceTexts.removeWhere((id, _) => id < oldestToKeep);
  }
  
  /// Flush any remaining audio
  Future<void> flush() async {
    if (_currentTextBuffer.isNotEmpty) {
      // Treat remaining text as a complete sentence
      _sentenceTexts[_currentSentenceId] = _currentTextBuffer.toString();
      await _playCompleteSentence(_currentSentenceId);
      _currentTextBuffer.clear();
    }
    
    // Play any remaining buffered sentences
    for (int id = _playbackSentenceId; id <= _currentSentenceId; id++) {
      if (_sentenceBuffers.containsKey(id)) {
        await _playCompleteSentence(id);
      }
    }
  }
  
  /// Clear all buffers
  void clear() {
    _sentenceBuffers.clear();
    _sentenceTexts.clear();
    _currentTextBuffer.clear();
    _currentSentenceId = 0;
    _playbackSentenceId = 0;
    _isProcessingSentence = false;
    
    AppLogger.info('🗑️ Sentence buffers cleared');
  }
}