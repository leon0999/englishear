import 'dart:convert';
import 'dart:typed_data';
import '../core/logger.dart';
import 'audio_queue_manager.dart';

/// Service that processes audio at sentence boundaries for natural speech
class SentenceAwareAudioService {
  final AudioQueueManager _queueManager = AudioQueueManager();
  final Map<int, SentenceBuffer> _sentences = {};
  int _currentSentenceId = 0;
  
  // Sentence detection patterns
  static final RegExp _sentenceEndPattern = RegExp(r'[.!?]\s*$');
  static final RegExp _phraseEndPattern = RegExp(r'[,:;]\s*$');
  
  // Buffer limits
  static const int MAX_SENTENCE_CHUNKS = 20;
  static const int MAX_BUFFER_SIZE = 192000; // ~4 seconds at 24kHz
  
  /// Process incoming audio delta with text
  void processAudioDelta(Map<String, dynamic> data) {
    try {
      // Extract audio and text
      final audioBase64 = data['delta'];
      final text = data['transcript'] ?? data['text'] ?? '';
      
      if (audioBase64 == null || audioBase64.toString().isEmpty) {
        AppLogger.warning('No audio data in delta');
        return;
      }
      
      final audioData = base64Decode(audioBase64);
      AppLogger.debug('Processing audio delta: ${audioData.length} bytes, text: "$text"');
      
      // Get or create current sentence buffer
      _sentences[_currentSentenceId] ??= SentenceBuffer(id: _currentSentenceId);
      final sentence = _sentences[_currentSentenceId]!;
      
      // Add chunk to sentence
      sentence.chunks.add(audioData);
      sentence.text.write(text);
      
      // Check if this is a sentence boundary
      if (_isSentenceComplete(text)) {
        AppLogger.info('📝 Sentence complete: "${sentence.text}"');
        _processSentence(_currentSentenceId);
        _currentSentenceId++;
      } else if (_isPhraseEnd(text) && sentence.chunks.length > 2) {
        // Process partial sentence at phrase boundaries for smoother flow
        AppLogger.debug('Phrase boundary detected, processing partial sentence');
        _processPartialSentence(_currentSentenceId);
      }
      
      // Clean up old buffers
      _cleanupOldBuffers();
      
    } catch (e) {
      AppLogger.error('Error processing audio delta', e);
    }
  }
  
  /// Check if text marks end of sentence
  bool _isSentenceComplete(String text) {
    return text.isNotEmpty && _sentenceEndPattern.hasMatch(text);
  }
  
  /// Check if text marks end of phrase
  bool _isPhraseEnd(String text) {
    return text.isNotEmpty && _phraseEndPattern.hasMatch(text);
  }
  
  /// Process a complete sentence
  void _processSentence(int sentenceId) {
    final sentence = _sentences[sentenceId];
    if (sentence == null || sentence.chunks.isEmpty) {
      AppLogger.warning('No data for sentence $sentenceId');
      return;
    }
    
    try {
      // Combine all chunks for the sentence
      final combined = _combineChunks(sentence.chunks);
      final sentenceText = sentence.text.toString();
      
      AppLogger.info('🔊 Processing complete sentence $sentenceId: "$sentenceText" (${combined.length} bytes)');
      
      // Add to playback queue with sentence text for proper pausing
      _queueManager.addChunk(
        'sentence_$sentenceId',
        combined,
        text: sentenceText,
      );
      
      // Clear the processed sentence
      _sentences.remove(sentenceId);
      
    } catch (e) {
      AppLogger.error('Failed to process sentence $sentenceId', e);
    }
  }
  
  /// Process partial sentence at phrase boundaries
  void _processPartialSentence(int sentenceId) {
    final sentence = _sentences[sentenceId];
    if (sentence == null || sentence.chunks.isEmpty) return;
    
    try {
      // Only process if we have enough chunks
      if (sentence.chunks.length < 2) return;
      
      // Take current chunks but don't clear the sentence
      final chunksToProcess = List<Uint8List>.from(sentence.chunks);
      final partialText = sentence.text.toString();
      
      // Combine chunks
      final combined = _combineChunks(chunksToProcess);
      
      AppLogger.debug('Processing partial sentence: "$partialText"');
      
      // Add to queue as partial
      _queueManager.addChunk(
        'partial_${sentenceId}_${sentence.partialCount}',
        combined,
        text: partialText,
      );
      
      // Clear processed chunks but keep the sentence active
      sentence.chunks.clear();
      sentence.text.clear();
      sentence.partialCount++;
      
    } catch (e) {
      AppLogger.error('Failed to process partial sentence', e);
    }
  }
  
  /// Combine multiple audio chunks into one
  Uint8List _combineChunks(List<Uint8List> chunks) {
    if (chunks.isEmpty) return Uint8List(0);
    
    final totalLength = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final combined = Uint8List(totalLength);
    
    int offset = 0;
    for (final chunk in chunks) {
      combined.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    
    return combined;
  }
  
  /// Clean up old sentence buffers to prevent memory issues
  void _cleanupOldBuffers() {
    // Remove sentences that are too old (5+ sentences behind)
    final oldestToKeep = _currentSentenceId - 5;
    
    _sentences.removeWhere((id, sentence) {
      if (id < oldestToKeep) {
        AppLogger.debug('Removing old sentence buffer $id');
        return true;
      }
      
      // Also remove if buffer is too large
      final totalSize = sentence.chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
      if (totalSize > MAX_BUFFER_SIZE) {
        AppLogger.warning('Removing oversized sentence buffer $id (${totalSize} bytes)');
        return true;
      }
      
      // Remove if too many chunks
      if (sentence.chunks.length > MAX_SENTENCE_CHUNKS) {
        AppLogger.warning('Removing sentence with too many chunks: ${sentence.chunks.length}');
        return true;
      }
      
      return false;
    });
  }
  
  /// Flush any remaining audio
  Future<void> flush() async {
    AppLogger.info('Flushing remaining sentence buffers');
    
    // Process any incomplete sentences
    for (final id in _sentences.keys.toList()..sort()) {
      if (_sentences[id]!.chunks.isNotEmpty) {
        _processSentence(id);
      }
    }
    
    // Wait for queue to finish
    await Future.delayed(Duration(milliseconds: 500));
  }
  
  /// Clear all buffers
  void clear() {
    _sentences.clear();
    _queueManager.clear();
    _currentSentenceId = 0;
    AppLogger.info('🗑️ Sentence-aware service cleared');
  }
  
  /// Get service status
  Map<String, dynamic> getStatus() {
    return {
      'currentSentenceId': _currentSentenceId,
      'bufferedSentences': _sentences.length,
      'queueStatus': _queueManager.getStatus(),
    };
  }
  
  /// Dispose resources
  Future<void> dispose() async {
    await flush();
    clear();
    await _queueManager.dispose();
  }
}

/// Buffer for accumulating sentence chunks
class SentenceBuffer {
  final int id;
  final List<Uint8List> chunks = [];
  final StringBuffer text = StringBuffer();
  int partialCount = 0;
  bool isComplete = false;
  
  SentenceBuffer({required this.id});
}