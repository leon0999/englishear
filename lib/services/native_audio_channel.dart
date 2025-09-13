import 'package:flutter/services.dart';
import 'dart:typed_data';
import '../core/logger.dart';

/// Native audio channel for iOS platform-specific audio handling
/// Provides direct access to iOS AVAudioEngine for optimal performance
class NativeAudioChannel {
  static const MethodChannel _channel = MethodChannel('com.englishear/audio');
  static bool _isInitialized = false;
  static bool _useNativeChannel = false; // Disabled until properly configured
  
  /// Initialize native audio engine
  static Future<bool> initialize() async {
    if (_isInitialized) return true;
    
    // Native channel is disabled for now - return false to use fallback
    if (!_useNativeChannel) {
      AppLogger.info('Native audio channel disabled, using fallback');
      return false;
    }
    
    try {
      final result = await _channel.invokeMethod<bool>('initializeAudioEngine');
      _isInitialized = result ?? false;
      
      if (_isInitialized) {
        AppLogger.success('✅ Native iOS audio engine initialized');
      } else {
        AppLogger.error('Failed to initialize native audio engine');
      }
      
      return _isInitialized;
    } on PlatformException catch (e) {
      AppLogger.error('Platform exception initializing audio: ${e.message}');
      return false;
    } catch (e) {
      AppLogger.error('Error initializing native audio: $e');
      return false;
    }
  }
  
  /// Play PCM audio data using native iOS audio engine
  static Future<bool> playPCMData(Uint8List pcmData, {String? chunkId}) async {
    // Native channel is disabled for now - return false to use fallback
    if (!_useNativeChannel) {
      return false;
    }
    
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        AppLogger.error('Cannot play audio - native engine not initialized');
        return false;
      }
    }
    
    try {
      final result = await _channel.invokeMethod<bool>('playPCM', {
        'data': pcmData,
        'sampleRate': 24000,  // OpenAI Realtime API sample rate
        'channels': 1,        // Mono
        'bitsPerSample': 16,  // PCM16
        'chunkId': chunkId ?? 'chunk_${DateTime.now().millisecondsSinceEpoch}',
      });
      
      if (result == true) {
        AppLogger.debug('🔊 Native playback successful for chunk: $chunkId');
        return true;
      } else {
        AppLogger.warning('Native playback returned false for chunk: $chunkId');
        return false;
      }
    } on PlatformException catch (e) {
      AppLogger.error('Platform exception playing audio: ${e.message}');
      return false;
    } catch (e) {
      AppLogger.error('Error playing native audio: $e');
      return false;
    }
  }
  
  /// Stream PCM audio data for continuous playback
  static Future<bool> streamPCMData(Stream<Uint8List> audioStream) async {
    if (!_isInitialized) {
      final initialized = await initialize();
      if (!initialized) {
        AppLogger.error('Cannot stream audio - native engine not initialized');
        return false;
      }
    }
    
    try {
      // Start streaming mode
      await _channel.invokeMethod('startStreaming', {
        'sampleRate': 24000,
        'channels': 1,
        'bitsPerSample': 16,
      });
      
      // Send audio chunks as they arrive
      await for (final chunk in audioStream) {
        await _channel.invokeMethod('streamChunk', {
          'data': chunk,
        });
      }
      
      // End streaming
      await _channel.invokeMethod('endStreaming');
      
      return true;
    } on PlatformException catch (e) {
      AppLogger.error('Platform exception streaming audio: ${e.message}');
      return false;
    } catch (e) {
      AppLogger.error('Error streaming native audio: $e');
      return false;
    }
  }
  
  /// Configure audio session for optimal performance
  static Future<bool> configureAudioSession({
    bool allowBluetooth = true,
    bool defaultToSpeaker = true,
    bool mixWithOthers = false,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('configureAudioSession', {
        'allowBluetooth': allowBluetooth,
        'defaultToSpeaker': defaultToSpeaker,
        'mixWithOthers': mixWithOthers,
      });
      
      if (result == true) {
        AppLogger.info('Audio session configured successfully');
        return true;
      }
      return false;
    } on PlatformException catch (e) {
      AppLogger.error('Failed to configure audio session: ${e.message}');
      return false;
    }
  }
  
  /// Stop all audio playback
  static Future<void> stopPlayback() async {
    try {
      await _channel.invokeMethod('stopPlayback');
      AppLogger.info('Native audio playback stopped');
    } on PlatformException catch (e) {
      AppLogger.error('Error stopping playback: ${e.message}');
    }
  }
  
  /// Pause audio playback
  static Future<void> pausePlayback() async {
    try {
      await _channel.invokeMethod('pausePlayback');
      AppLogger.info('Native audio playback paused');
    } on PlatformException catch (e) {
      AppLogger.error('Error pausing playback: ${e.message}');
    }
  }
  
  /// Resume audio playback
  static Future<void> resumePlayback() async {
    try {
      await _channel.invokeMethod('resumePlayback');
      AppLogger.info('Native audio playback resumed');
    } on PlatformException catch (e) {
      AppLogger.error('Error resuming playback: ${e.message}');
    }
  }
  
  /// Get current playback state
  static Future<bool> isPlaying() async {
    try {
      final result = await _channel.invokeMethod<bool>('isPlaying');
      return result ?? false;
    } on PlatformException catch (e) {
      AppLogger.error('Error getting playback state: ${e.message}');
      return false;
    }
  }
  
  /// Set volume (0.0 to 1.0)
  static Future<void> setVolume(double volume) async {
    if (volume < 0.0 || volume > 1.0) {
      AppLogger.warning('Volume must be between 0.0 and 1.0');
      return;
    }
    
    try {
      await _channel.invokeMethod('setVolume', {'volume': volume});
      AppLogger.info('Volume set to ${(volume * 100).toStringAsFixed(0)}%');
    } on PlatformException catch (e) {
      AppLogger.error('Error setting volume: ${e.message}');
    }
  }
  
  /// Clean up resources
  static Future<void> dispose() async {
    try {
      await _channel.invokeMethod('dispose');
      _isInitialized = false;
      AppLogger.info('Native audio channel disposed');
    } on PlatformException catch (e) {
      AppLogger.error('Error disposing native audio: ${e.message}');
    }
  }
}