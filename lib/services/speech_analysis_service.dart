class SpeechAnalysisService {
  // 발음 정확도 계산
  static double calculatePronunciationScore(String expected, String actual) {
    if (expected.isEmpty || actual.isEmpty) return 0.0;
    
    final expectedWords = expected.toLowerCase().split(' ');
    final actualWords = actual.toLowerCase().split(' ');
    
    int correctWords = 0;
    for (String word in actualWords) {
      if (expectedWords.contains(word)) {
        correctWords++;
      }
    }
    
    return (correctWords / expectedWords.length) * 100;
  }
  
  // 문법 정확도 계산
  static double calculateGrammarScore(String expected, String actual) {
    if (expected.isEmpty || actual.isEmpty) return 0.0;
    
    // 간단한 문법 체크 (실제로는 더 복잡한 NLP 알고리즘 필요)
    final expectedStructure = _extractSentenceStructure(expected);
    final actualStructure = _extractSentenceStructure(actual);
    
    double score = 0.0;
    
    // 주어-동사 일치 체크
    if (expectedStructure['hasSubject'] == actualStructure['hasSubject']) {
      score += 25.0;
    }
    
    // 동사 존재 체크
    if (expectedStructure['hasVerb'] == actualStructure['hasVerb']) {
      score += 25.0;
    }
    
    // 문장 길이 유사성
    final lengthDiff = (expectedStructure['wordCount'] - actualStructure['wordCount']).abs();
    if (lengthDiff <= 2) {
      score += 25.0;
    }
    
    // 시제 일치 (간단한 체크)
    if (_checkTenseMatch(expected, actual)) {
      score += 25.0;
    }
    
    return score;
  }
  
  // 유창성 점수 계산
  static double calculateFluencyScore(String actual, Duration speakingTime) {
    if (actual.isEmpty) return 0.0;
    
    final wordCount = actual.split(' ').length;
    final wordsPerMinute = (wordCount / speakingTime.inSeconds) * 60;
    
    // 이상적인 속도: 120-150 단어/분
    if (wordsPerMinute >= 120 && wordsPerMinute <= 150) {
      return 100.0;
    } else if (wordsPerMinute >= 90 && wordsPerMinute <= 180) {
      return 75.0;
    } else if (wordsPerMinute >= 60 && wordsPerMinute <= 210) {
      return 50.0;
    } else {
      return 25.0;
    }
  }
  
  // 어휘 사용 점수 계산
  static double calculateVocabularyScore(List<String> keywords, String actual) {
    if (keywords.isEmpty || actual.isEmpty) return 0.0;
    
    final actualWords = actual.toLowerCase().split(' ');
    int matchedKeywords = 0;
    
    for (String keyword in keywords) {
      if (actualWords.contains(keyword.toLowerCase())) {
        matchedKeywords++;
      }
    }
    
    return (matchedKeywords / keywords.length) * 100;
  }
  
  // 종합 점수 계산
  static Map<String, double> calculateOverallScore({
    required String expected,
    required String actual,
    required List<String> keywords,
    required Duration speakingTime,
  }) {
    final pronunciation = calculatePronunciationScore(expected, actual);
    final grammar = calculateGrammarScore(expected, actual);
    final fluency = calculateFluencyScore(actual, speakingTime);
    final vocabulary = calculateVocabularyScore(keywords, actual);
    
    final overall = (pronunciation * 0.3 + 
                     grammar * 0.25 + 
                     fluency * 0.2 + 
                     vocabulary * 0.25);
    
    return {
      'pronunciation': pronunciation,
      'grammar': grammar,
      'fluency': fluency,
      'vocabulary': vocabulary,
      'overall': overall,
    };
  }
  
  // 문장 구조 추출 (헬퍼 함수)
  static Map<String, dynamic> _extractSentenceStructure(String sentence) {
    final words = sentence.toLowerCase().split(' ');
    
    // 주어 체크 (I, you, he, she, it, we, they, 명사)
    final subjects = ['i', 'you', 'he', 'she', 'it', 'we', 'they', 'the', 'a', 'an'];
    final hasSubject = words.any((word) => subjects.contains(word));
    
    // 동사 체크 (is, are, am, was, were, have, has, do, does, -ing, -ed)
    final verbs = ['is', 'are', 'am', 'was', 'were', 'have', 'has', 'do', 'does'];
    final hasVerb = words.any((word) => 
      verbs.contains(word) || 
      word.endsWith('ing') || 
      word.endsWith('ed')
    );
    
    return {
      'hasSubject': hasSubject,
      'hasVerb': hasVerb,
      'wordCount': words.length,
    };
  }
  
  // 시제 일치 체크 (헬퍼 함수)
  static bool _checkTenseMatch(String expected, String actual) {
    final expectedWords = expected.toLowerCase().split(' ');
    final actualWords = actual.toLowerCase().split(' ');
    
    // 현재 시제 마커
    final presentMarkers = ['is', 'are', 'am', 'do', 'does', 'have', 'has'];
    // 과거 시제 마커
    final pastMarkers = ['was', 'were', 'did', 'had'];
    // 미래 시제 마커
    final futureMarkers = ['will', 'going to', 'shall'];
    
    bool expectedPresent = expectedWords.any((w) => presentMarkers.contains(w));
    bool expectedPast = expectedWords.any((w) => pastMarkers.contains(w));
    bool expectedFuture = expectedWords.any((w) => futureMarkers.contains(w));
    
    bool actualPresent = actualWords.any((w) => presentMarkers.contains(w));
    bool actualPast = actualWords.any((w) => pastMarkers.contains(w));
    bool actualFuture = actualWords.any((w) => futureMarkers.contains(w));
    
    return (expectedPresent == actualPresent) || 
           (expectedPast == actualPast) || 
           (expectedFuture == actualFuture);
  }
  
  // 피드백 메시지 생성
  static String generateFeedback(Map<String, double> scores) {
    final overall = scores['overall'] ?? 0;
    
    if (overall >= 90) {
      return 'Excellent! Your pronunciation and grammar are nearly perfect!';
    } else if (overall >= 75) {
      return 'Great job! You\'re doing really well. Keep practicing!';
    } else if (overall >= 60) {
      return 'Good effort! Focus on pronunciation and using key vocabulary.';
    } else if (overall >= 40) {
      return 'Nice try! Practice speaking more slowly and clearly.';
    } else {
      return 'Keep practicing! Try to speak one word at a time first.';
    }
  }
}