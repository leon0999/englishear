import 'dart:async';

/// Detects sentence boundaries in streaming text for natural TTS processing
class SentenceBoundaryDetector {
  final List<String> _buffer = [];
  final RegExp _sentenceEnd = RegExp(r'[.!?。！？]+\s*');
  final RegExp _abbreviations = RegExp(
    r'\b(Mr|Mrs|Ms|Dr|Prof|Sr|Jr|Inc|Ltd|Co|Corp|vs|etc|i\.e|e\.g)\.$',
    caseSensitive: false,
  );
  
  // Minimum sentence length to avoid splitting too aggressively
  static const int minSentenceLength = 10;
  
  // Maximum buffer size before forced flush (prevents memory issues)
  static const int maxBufferSize = 500;
  
  /// Process a stream of text chunks and emit complete sentences
  Stream<String> processTextStream(Stream<String> input) async* {
    await for (final chunk in input) {
      _buffer.add(chunk);
      final text = _buffer.join();
      
      // Check if buffer is getting too large
      if (text.length > maxBufferSize) {
        yield* _flushBuffer();
        continue;
      }
      
      // Find sentence boundaries
      final matches = _sentenceEnd.allMatches(text);
      
      for (final match in matches) {
        // Check if this might be an abbreviation
        final beforeMatch = text.substring(0, match.start);
        if (_abbreviations.hasMatch(beforeMatch)) {
          continue; // Skip abbreviations
        }
        
        // Check minimum length
        final sentence = text.substring(0, match.end).trim();
        if (sentence.length < minSentenceLength) {
          continue;
        }
        
        // Emit the complete sentence
        yield sentence;
        
        // Update buffer with remaining text
        _buffer.clear();
        if (match.end < text.length) {
          _buffer.add(text.substring(match.end));
        }
      }
    }
    
    // Flush any remaining text
    yield* _flushBuffer();
  }
  
  /// Process a single text block and return sentences
  List<String> processSingleText(String text) {
    final sentences = <String>[];
    final matches = _sentenceEnd.allMatches(text);
    
    int lastEnd = 0;
    for (final match in matches) {
      // Check if this might be an abbreviation
      final beforeMatch = text.substring(0, match.start);
      if (_abbreviations.hasMatch(beforeMatch)) {
        continue;
      }
      
      final sentence = text.substring(lastEnd, match.end).trim();
      if (sentence.length >= minSentenceLength) {
        sentences.add(sentence);
        lastEnd = match.end;
      }
    }
    
    // Add remaining text if any
    if (lastEnd < text.length) {
      final remaining = text.substring(lastEnd).trim();
      if (remaining.isNotEmpty) {
        sentences.add(remaining);
      }
    }
    
    return sentences;
  }
  
  /// Flush the current buffer
  Stream<String> _flushBuffer() async* {
    if (_buffer.isNotEmpty) {
      final remaining = _buffer.join().trim();
      if (remaining.isNotEmpty) {
        yield remaining;
      }
      _buffer.clear();
    }
  }
  
  /// Clear the buffer
  void clear() {
    _buffer.clear();
  }
  
  /// Get current buffer content
  String get currentBuffer => _buffer.join();
  
  /// Check if buffer is empty
  bool get isEmpty => _buffer.isEmpty;
}