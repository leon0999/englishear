import 'dart:convert';
import '../core/logger.dart';

/// Conversation enhancer to make Jupiter AI more natural like ChatGPT Voice
class ConversationEnhancer {
  // Conversation history for context
  final List<Map<String, dynamic>> _conversationHistory = [];
  
  // User preferences
  String _userPreferredName = 'friend';
  String _userLanguageLevel = 'intermediate';
  List<String> _userInterests = [];
  
  /// Get enhanced instructions for natural conversation
  String getEnhancedInstructions() {
    return '''You are Jupiter, an advanced AI voice assistant similar to ChatGPT Voice.
Your goal is to have natural, engaging conversations that help users improve their English.

VOICE CHARACTERISTICS:
- Warm, friendly, and encouraging tone
- Clear articulation with natural speech rhythm
- Appropriate pauses between thoughts (use "..." for natural pauses)
- Express emotions through voice modulation
- Use emphasis on important words

CONVERSATION STYLE:
- Keep responses concise (2-3 sentences max unless asked for more)
- Use natural conversational phrases:
  * Starting: "Oh, interesting!", "I see what you mean", "That's a great question"
  * Thinking: "Hmm, let me think...", "Well...", "You know..."
  * Agreeing: "Exactly!", "That makes sense", "You're absolutely right"
  * Encouraging: "Great job!", "Your English is improving!", "Well said!"
- Ask follow-up questions to maintain engagement
- Remember previous topics in the conversation
- Acknowledge what the user said before responding

ENGLISH TEACHING APPROACH:
- Gently correct mistakes by using the correct form naturally in your response
- Don't explicitly point out errors unless asked
- Provide alternative expressions when appropriate
- Adjust vocabulary complexity based on user's level (currently: $_userLanguageLevel)
- Encourage the user when they use new vocabulary or complex sentences

PERSONALITY TRAITS:
- Curious and interested in the user's thoughts
- Patient and never rushed
- Supportive and encouraging
- Knowledgeable but not condescending
- Occasionally share relevant fun facts or cultural insights

SPEECH PATTERNS:
- Use contractions naturally (I'm, you're, it's, don't)
- Include mild fillers sparingly for naturalness ("um", "well", "you know")
- Vary sentence structure and length
- End some sentences with rising intonation for questions
- Use appropriate emotion in your voice (excitement, curiosity, empathy)

IMPORTANT RULES:
1. Never speak for more than 15 seconds at a time
2. Always wait for the user to finish speaking
3. If you don't understand, ask for clarification naturally
4. Show genuine interest in what the user is saying
5. Build on previous conversation topics when relevant

Current context:
- User's name/preference: $_userPreferredName
- Language level: $_userLanguageLevel
- Interests: ${_userInterests.isNotEmpty ? _userInterests.join(', ') : 'general topics'}
- Conversation topics so far: ${_getRecentTopics()}''';
  }
  
  /// Get optimized session configuration for natural conversation
  Map<String, dynamic> getOptimizedSessionConfig() {
    return {
      'type': 'session.update',
      'session': {
        'modalities': ['text', 'audio'],
        'instructions': getEnhancedInstructions(),
        'voice': 'alloy',  // Most natural voice for conversation
        'input_audio_format': 'pcm16',
        'output_audio_format': 'pcm16',
        'input_audio_transcription': {
          'model': 'whisper-1'
        },
        'turn_detection': {
          'type': 'server_vad',
          'threshold': 0.5,  // Balanced for natural conversation
          'prefix_padding_ms': 300,  // Natural pause before speaking
          'silence_duration_ms': 700,  // Wait for user to finish
        },
        'temperature': 0.8,  // Natural variation in responses
        'max_response_output_tokens': 200,  // Keep responses concise
      }
    };
  }
  
  /// Add message to conversation history
  void addToHistory({
    required String role,
    required String content,
    DateTime? timestamp,
  }) {
    _conversationHistory.add({
      'role': role,
      'content': content,
      'timestamp': timestamp ?? DateTime.now(),
    });
    
    // Keep only last 20 messages for context
    if (_conversationHistory.length > 20) {
      _conversationHistory.removeAt(0);
    }
    
    AppLogger.debug('Added to history: [$role] ${content.substring(0, content.length > 50 ? 50 : content.length)}...');
  }
  
  /// Generate contextual response enhancer
  String generateContextualEnhancer(String userInput) {
    // Analyze user input for context
    final lowerInput = userInput.toLowerCase();
    
    // Check for specific scenarios
    if (_isGreeting(lowerInput)) {
      return "Respond warmly and ask how they're doing or what they'd like to talk about.";
    }
    
    if (_isQuestion(lowerInput)) {
      return "Answer concisely and ask a related follow-up question.";
    }
    
    if (_isOpinion(lowerInput)) {
      return "Show interest in their perspective and share a brief related thought.";
    }
    
    if (_isStoryTelling(lowerInput)) {
      return "React with appropriate emotion and ask for more details about one aspect.";
    }
    
    // Default enhancer
    return "Respond naturally and keep the conversation flowing with a follow-up question or comment.";
  }
  
  /// Check if input is a greeting
  bool _isGreeting(String input) {
    final greetings = ['hi', 'hello', 'hey', 'good morning', 'good afternoon', 
                       'good evening', 'how are you', "what's up", 'howdy'];
    return greetings.any((g) => input.contains(g));
  }
  
  /// Check if input is a question
  bool _isQuestion(String input) {
    final questionWords = ['what', 'where', 'when', 'why', 'how', 'who', 
                          'which', 'whose', 'whom'];
    return input.contains('?') || questionWords.any((q) => input.startsWith(q));
  }
  
  /// Check if input is expressing opinion
  bool _isOpinion(String input) {
    final opinionPhrases = ['i think', 'i believe', 'i feel', 'in my opinion',
                           'i like', 'i love', 'i hate', 'i prefer'];
    return opinionPhrases.any((p) => input.contains(p));
  }
  
  /// Check if input is story telling
  bool _isStoryTelling(String input) {
    final storyIndicators = ['yesterday', 'last week', 'once', 'i remember',
                            'there was', 'i was', 'we were'];
    return storyIndicators.any((s) => input.contains(s)) || input.length > 100;
  }
  
  /// Get recent conversation topics
  String _getRecentTopics() {
    if (_conversationHistory.isEmpty) return 'none yet';
    
    // Extract key topics from recent messages
    final recentMessages = _conversationHistory
        .where((m) => m['role'] == 'user')
        .map((m) => m['content'] as String)
        .toList()
        .reversed
        .take(3);
    
    if (recentMessages.isEmpty) return 'none yet';
    
    // Simple topic extraction (can be enhanced with NLP)
    return recentMessages.join(', ').substring(0, 50) + '...';
  }
  
  /// Update user preferences
  void updateUserPreferences({
    String? name,
    String? languageLevel,
    List<String>? interests,
  }) {
    if (name != null) _userPreferredName = name;
    if (languageLevel != null) _userLanguageLevel = languageLevel;
    if (interests != null) _userInterests = interests;
    
    AppLogger.info('Updated user preferences: name=$_userPreferredName, level=$_userLanguageLevel');
  }
  
  /// Get conversation statistics
  Map<String, dynamic> getConversationStats() {
    final userMessages = _conversationHistory.where((m) => m['role'] == 'user').length;
    final assistantMessages = _conversationHistory.where((m) => m['role'] == 'assistant').length;
    
    return {
      'totalMessages': _conversationHistory.length,
      'userMessages': userMessages,
      'assistantMessages': assistantMessages,
      'averageUserLength': userMessages > 0 
          ? _conversationHistory
              .where((m) => m['role'] == 'user')
              .map((m) => (m['content'] as String).length)
              .reduce((a, b) => a + b) ~/ userMessages
          : 0,
    };
  }
  
  /// Clear conversation history
  void clearHistory() {
    _conversationHistory.clear();
    AppLogger.info('Conversation history cleared');
  }
}