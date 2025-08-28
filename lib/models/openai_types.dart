// Simple type definitions for OpenAI API without code generation

// Difficulty levels enum
enum DifficultyLevel {
  beginner,
  intermediate,
  advanced;

  String get description {
    switch (this) {
      case DifficultyLevel.beginner:
        return 'Simple present tense, common vocabulary (top 1000 words), 5-8 words per sentence';
      case DifficultyLevel.intermediate:
        return 'Various tenses, everyday vocabulary (top 3000 words), 8-12 words per sentence';
      case DifficultyLevel.advanced:
        return 'Complex grammar, sophisticated vocabulary, idiomatic expressions, 12-20 words';
    }
  }

  int get maxWords {
    switch (this) {
      case DifficultyLevel.beginner:
        return 8;
      case DifficultyLevel.intermediate:
        return 12;
      case DifficultyLevel.advanced:
        return 20;
    }
  }
}

// Scenario types enum
enum ScenarioType {
  street,
  restaurant,
  park,
  office,
  home,
  airport,
  shopping,
  school,
  hospital,
  beach;

  String get displayName {
    return name[0].toUpperCase() + name.substring(1);
  }
}

// Learning content model
class LearningContent {
  final String sentence;
  final List<String> keywords;
  final int difficulty;
  final String grammarPoint;
  final List<String> pronunciationTips;

  LearningContent({
    required this.sentence,
    required this.keywords,
    required this.difficulty,
    required this.grammarPoint,
    required this.pronunciationTips,
  });

  factory LearningContent.fromJson(Map<String, dynamic> json) {
    return LearningContent(
      sentence: json['sentence'] ?? '',
      keywords: List<String>.from(json['keywords'] ?? []),
      difficulty: json['difficulty'] ?? 1,
      grammarPoint: json['grammarPoint'] ?? json['grammar_point'] ?? '',
      pronunciationTips: List<String>.from(json['pronunciationTips'] ?? json['pronunciation_tips'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sentence': sentence,
      'keywords': keywords,
      'difficulty': difficulty,
      'grammarPoint': grammarPoint,
      'pronunciationTips': pronunciationTips,
    };
  }
}

// Pronunciation evaluation model
class PronunciationEvaluation {
  final double overallScore;
  final double pronunciationScore;
  final double fluencyScore;
  final double grammarScore;
  final List<String> matchedKeywords;
  final List<String> missedKeywords;
  final List<PronunciationError> errors;
  final String feedback;
  final List<String> improvementTips;

  PronunciationEvaluation({
    required this.overallScore,
    required this.pronunciationScore,
    required this.fluencyScore,
    required this.grammarScore,
    required this.matchedKeywords,
    required this.missedKeywords,
    required this.errors,
    required this.feedback,
    required this.improvementTips,
  });

  factory PronunciationEvaluation.fromJson(Map<String, dynamic> json) {
    return PronunciationEvaluation(
      overallScore: (json['overallScore'] ?? json['overall_score'] ?? 0).toDouble(),
      pronunciationScore: (json['pronunciationScore'] ?? json['pronunciation_score'] ?? 0).toDouble(),
      fluencyScore: (json['fluencyScore'] ?? json['fluency_score'] ?? 0).toDouble(),
      grammarScore: (json['grammarScore'] ?? json['grammar_score'] ?? 0).toDouble(),
      matchedKeywords: List<String>.from(json['matchedKeywords'] ?? json['matched_keywords'] ?? []),
      missedKeywords: List<String>.from(json['missedKeywords'] ?? json['missed_keywords'] ?? []),
      errors: (json['errors'] as List<dynamic>?)?.map((e) => 
        PronunciationError.fromJson(e as Map<String, dynamic>)
      ).toList() ?? [],
      feedback: json['feedback'] ?? '',
      improvementTips: List<String>.from(json['improvementTips'] ?? json['improvement_tips'] ?? []),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'overallScore': overallScore,
      'pronunciationScore': pronunciationScore,
      'fluencyScore': fluencyScore,
      'grammarScore': grammarScore,
      'matchedKeywords': matchedKeywords,
      'missedKeywords': missedKeywords,
      'errors': errors.map((e) => e.toJson()).toList(),
      'feedback': feedback,
      'improvementTips': improvementTips,
    };
  }
}

// Pronunciation error model
class PronunciationError {
  final String type;
  final String word;
  final String suggestion;

  PronunciationError({
    required this.type,
    required this.word,
    required this.suggestion,
  });

  factory PronunciationError.fromJson(Map<String, dynamic> json) {
    return PronunciationError(
      type: json['type'] ?? '',
      word: json['word'] ?? '',
      suggestion: json['suggestion'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'word': word,
      'suggestion': suggestion,
    };
  }
}