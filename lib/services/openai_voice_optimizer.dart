import 'dart:convert';
import '../core/logger.dart';

/// Optimizes OpenAI Realtime API voice settings for natural speech
class OpenAIVoiceOptimizer {
  
  /// Voice profiles for different conversation styles
  static const Map<String, Map<String, dynamic>> voiceProfiles = {
    'natural': {
      'voice': 'alloy',
      'speed': 0.95,
      'pitch': 1.0,
      'stability': 0.65,
      'similarity_boost': 0.8,
      'style': 0.5,
    },
    'friendly': {
      'voice': 'nova',
      'speed': 1.0,
      'pitch': 1.05,
      'stability': 0.7,
      'similarity_boost': 0.85,
      'style': 0.6,
    },
    'professional': {
      'voice': 'onyx',
      'speed': 0.9,
      'pitch': 0.95,
      'stability': 0.8,
      'similarity_boost': 0.9,
      'style': 0.3,
    },
    'energetic': {
      'voice': 'shimmer',
      'speed': 1.1,
      'pitch': 1.1,
      'stability': 0.6,
      'similarity_boost': 0.75,
      'style': 0.7,
    },
  };
  
  /// Get optimal configuration for natural conversation
  static Map<String, dynamic> getOptimalConfig({
    String profile = 'natural',
    String? customVoice,
    Map<String, dynamic>? customSettings,
  }) {
    final voiceSettings = Map<String, dynamic>.from(voiceProfiles[profile] ?? voiceProfiles['natural']!);
    
    // Apply custom overrides
    if (customVoice != null) {
      voiceSettings['voice'] = customVoice;
    }
    if (customSettings != null) {
      voiceSettings.addAll(customSettings);
    }
    
    AppLogger.info('Applying voice profile: $profile', data: voiceSettings);
    
    return {
      'type': 'session.update',
      'session': {
        // Voice selection
        'voice': voiceSettings['voice'],
        
        // Natural conversation instructions
        'instructions': _getNaturalInstructions(),
        
        // Modalities
        'modalities': ['text', 'audio'],
        
        // Temperature for variety
        'temperature': 0.9,
        
        // Advanced voice settings
        'voice_settings': {
          'speed': voiceSettings['speed'],
          'pitch': voiceSettings['pitch'],
          'stability': voiceSettings['stability'],
          'similarity_boost': voiceSettings['similarity_boost'],
          'style': voiceSettings['style'],
          'use_speaker_boost': true,
        },
        
        // Audio configuration
        'audio_settings': {
          'sample_rate': 24000,
          'format': 'pcm16',
          'channels': 1,
          'voice_activity_detection': true,
          'noise_suppression': true,
          'echo_cancellation': true,
          'automatic_gain_control': true,
        },
        
        // Response configuration
        'response_format': {
          'type': 'audio',
          'audio_format': 'pcm16',
          'sample_rate': 24000,
          'channels': 1,
        },
        
        // Turn detection
        'turn_detection': {
          'type': 'server_vad',
          'threshold': 0.7,
          'prefix_padding_ms': 300,
          'silence_duration_ms': 700,
        },
        
        // Tools (empty for now)
        'tools': [],
        
        // Tool choice
        'tool_choice': 'auto',
      }
    };
  }
  
  /// Get natural conversation instructions
  static String _getNaturalInstructions() {
    return '''You are Jupiter, a friendly and natural English conversation partner.

SPEAKING STYLE:
- Speak naturally with appropriate pauses between phrases
- Use natural intonation and emotion in your voice
- Include conversational fillers occasionally like "um", "well", "you know"
- Vary your speech rhythm and tone to sound more human
- Express emotions through your voice when appropriate

CONVERSATION GUIDELINES:
- Be warm, encouraging, and supportive
- Keep responses concise but natural (2-3 sentences usually)
- Ask follow-up questions to keep conversation flowing
- React naturally to what the user says
- Provide gentle corrections when needed

VOICE CHARACTERISTICS:
- Speak at a comfortable, slightly relaxed pace
- Use natural emphasis on important words
- Include brief pauses for thought
- Sound genuinely interested in the conversation
- Laugh or express surprise when appropriate

Remember: You're having a real conversation, not reading a script.''';
  }
  
  /// Get configuration for specific scenarios
  static Map<String, dynamic> getScenarioConfig(String scenario) {
    switch (scenario) {
      case 'greeting':
        return getOptimalConfig(
          profile: 'friendly',
          customSettings: {
            'speed': 1.0,
            'style': 0.7, // More expressive for greetings
          },
        );
        
      case 'teaching':
        return getOptimalConfig(
          profile: 'professional',
          customSettings: {
            'speed': 0.85, // Slower for clarity
            'stability': 0.85, // More consistent
          },
        );
        
      case 'casual_chat':
        return getOptimalConfig(
          profile: 'natural',
          customSettings: {
            'style': 0.6, // More personality
            'stability': 0.6, // More variation
          },
        );
        
      case 'pronunciation':
        return getOptimalConfig(
          profile: 'professional',
          customSettings: {
            'speed': 0.8, // Very slow for clarity
            'stability': 0.9, // Very consistent
            'similarity_boost': 0.95, // Clear articulation
          },
        );
        
      default:
        return getOptimalConfig(profile: 'natural');
    }
  }
  
  /// Create response.create event with optimized settings
  static Map<String, dynamic> createOptimizedResponse({
    required String text,
    String scenario = 'casual_chat',
  }) {
    return {
      'type': 'response.create',
      'response': {
        'modalities': ['text', 'audio'],
        'instructions': text,
        'voice': voiceProfiles[scenario]?['voice'] ?? 'alloy',
        'output_audio_format': 'pcm16',
        'temperature': 0.9,
        'max_output_tokens': 4096,
      }
    };
  }
  
  /// Adjust voice settings dynamically based on content
  static Map<String, dynamic> adjustForContent(String content) {
    final adjustments = <String, dynamic>{};
    
    // Check for questions - slightly higher pitch
    if (content.contains('?')) {
      adjustments['pitch'] = 1.05;
    }
    
    // Check for excitement - more energy
    if (content.contains('!')) {
      adjustments['speed'] = 1.05;
      adjustments['style'] = 0.7;
    }
    
    // Check for lists or instructions - clearer speech
    if (content.contains('First') || content.contains('Step') || content.contains('1.')) {
      adjustments['speed'] = 0.9;
      adjustments['stability'] = 0.8;
    }
    
    // Check for emphasis markers
    if (content.contains('*') || content.contains('_')) {
      adjustments['style'] = 0.6;
    }
    
    return adjustments;
  }
  
  /// Get diagnostics for current voice settings
  static Map<String, dynamic> getDiagnostics(Map<String, dynamic> currentSettings) {
    final voice = currentSettings['voice'] ?? 'unknown';
    final speed = currentSettings['voice_settings']?['speed'] ?? 1.0;
    final stability = currentSettings['voice_settings']?['stability'] ?? 0.75;
    final style = currentSettings['voice_settings']?['style'] ?? 0.5;
    
    return {
      'voice': voice,
      'naturalness_score': _calculateNaturalnessScore(speed, stability, style),
      'clarity_score': _calculateClarityScore(speed, stability),
      'expressiveness_score': style,
      'recommendations': _getRecommendations(speed, stability, style),
    };
  }
  
  static double _calculateNaturalnessScore(double speed, double stability, double style) {
    // Optimal values for naturalness
    const optimalSpeed = 0.95;
    const optimalStability = 0.65;
    const optimalStyle = 0.5;
    
    final speedScore = 1.0 - (speed - optimalSpeed).abs();
    final stabilityScore = 1.0 - (stability - optimalStability).abs();
    final styleScore = 1.0 - (style - optimalStyle).abs();
    
    return (speedScore + stabilityScore + styleScore) / 3.0;
  }
  
  static double _calculateClarityScore(double speed, double stability) {
    // Slower speed and higher stability = better clarity
    final speedScore = 1.0 - (speed - 0.8).abs();
    final stabilityScore = stability;
    
    return (speedScore + stabilityScore) / 2.0;
  }
  
  static List<String> _getRecommendations(double speed, double stability, double style) {
    final recommendations = <String>[];
    
    if (speed > 1.1) {
      recommendations.add('Reduce speed for better clarity');
    } else if (speed < 0.8) {
      recommendations.add('Increase speed for more natural flow');
    }
    
    if (stability > 0.85) {
      recommendations.add('Reduce stability for more natural variation');
    } else if (stability < 0.5) {
      recommendations.add('Increase stability for consistency');
    }
    
    if (style > 0.8) {
      recommendations.add('Reduce style for less exaggerated expression');
    } else if (style < 0.3) {
      recommendations.add('Increase style for more personality');
    }
    
    if (recommendations.isEmpty) {
      recommendations.add('Voice settings are well optimized');
    }
    
    return recommendations;
  }
}