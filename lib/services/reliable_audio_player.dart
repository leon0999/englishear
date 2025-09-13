import 'dart:typed_data';
import 'dart:collection';
import 'dart:convert';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import '../core/logger.dart';

/// Reliable audio player using just_audio with memory-based playback
/// Fixes the -11828 error by using proper WAV format and just_audio package
class ReliableAudioPlayer {
  static final ReliableAudioPlayer _instance = ReliableAudioPlayer._internal();
  factory ReliableAudioPlayer() => _instance;
  ReliableAudioPlayer._internal();
  
  late final AudioPlayer _player;
  bool _isPlaying = false;
  bool _isInitialized = false;
  final Queue<AudioChunk> _queue = Queue();
  
  /// Initialize reliable audio player with proper audio session
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      AppLogger.info('==================== RELIABLE AUDIO PLAYER INIT START ====================');
      
      // Configure audio session for iOS
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.defaultToSpeaker,
        avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      
      AppLogger.success('✅ Audio session configured successfully');
      
      // Initialize just_audio player
      _player = AudioPlayer();
      
      // Set up completion listener
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _onPlaybackCompleted();
        }
      });
      
      // Set volume to maximum
      await _player.setVolume(1.0);
      
      _isInitialized = true;
      AppLogger.success('✅ ReliableAudioPlayer initialized successfully');
      AppLogger.info('==================== RELIABLE AUDIO PLAYER INIT COMPLETE ====================');
      
    } catch (e) {
      AppLogger.error('Failed to initialize ReliableAudioPlayer: $e');
      throw Exception('Audio player initialization failed: $e');
    }
  }
  
  /// Play PCM audio data using memory-based WAV playback
  Future<void> playPCM(String chunkId, Uint8List pcmData) async {
    if (!_isInitialized) {
      AppLogger.warning('Player not initialized, initializing now...');
      await initialize();
    }
    
    // Queue if already playing
    if (_isPlaying) {
      _queue.add(AudioChunk(chunkId, pcmData));
      AppLogger.debug('🔄 Queuing chunk $chunkId (${_queue.length} in queue)');
      return;
    }
    
    await _playChunk(chunkId, pcmData);
  }
  
  /// Internal method to play a single chunk
  Future<void> _playChunk(String chunkId, Uint8List pcmData) async {
    _isPlaying = true;
    
    try {
      AppLogger.audio('🎵 Playing chunk $chunkId');
      
      // Validate PCM data
      if (pcmData.isEmpty || pcmData.length < 100) {
        throw Exception('Invalid PCM data: ${pcmData.length} bytes');
      }
      
      // Convert PCM to proper WAV format
      final wavData = _createWavFromPCM(pcmData);
      AppLogger.debug('📦 Created WAV data: ${wavData.length} bytes from ${pcmData.length} PCM bytes');
      
      // Create memory-based audio source
      final audioSource = _MemoryAudioSource(wavData);
      
      // Ensure audio session is active before playback
      final session = await AudioSession.instance;
      await session.setActive(true);
      AppLogger.debug('🔊 Activated audio session for playback');
      
      // Play using just_audio
      await _player.setAudioSource(audioSource);
      await _player.play();
      
      AppLogger.success('✅ Started playback for chunk $chunkId');
      
      // Note: Completion is handled by stream listener
      
    } catch (e) {
      AppLogger.error('Failed to play chunk $chunkId: $e');
      _isPlaying = false;
      _processNextInQueue();
    }
  }
  
  /// Called when playback completes
  void _onPlaybackCompleted() {
    AppLogger.success('✅ Playback completed');
    _isPlaying = false;
    
    // Process next in queue
    _processNextInQueue();
  }
  
  /// Process next audio chunk in queue
  void _processNextInQueue() {
    if (_queue.isEmpty) return;
    
    final next = _queue.removeFirst();
    AppLogger.debug('📤 Processing queued chunk ${next.id} (${_queue.length} remaining)');
    _playChunk(next.id, next.data);
  }
  
  /// Create proper WAV file from PCM data with correct headers
  /// This is the key fix for the -11828 error
  Uint8List _createWavFromPCM(Uint8List pcmData) {
    // OpenAI Realtime API audio format
    const int sampleRate = 24000;  // 24kHz
    const int channels = 1;        // Mono
    const int bitsPerSample = 16;  // PCM16
    const int byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    const int blockAlign = channels * bitsPerSample ~/ 8;
    
    final dataSize = pcmData.length;
    final chunkSize = dataSize + 36;  // Total size - 8 bytes
    
    final wav = BytesBuilder();
    
    // RIFF Header (12 bytes)
    wav.add(utf8.encode('RIFF'));           // ChunkID
    wav.add(_intToLittleEndian(chunkSize, 4));  // ChunkSize
    wav.add(utf8.encode('WAVE'));           // Format
    
    // fmt Subchunk (24 bytes)
    wav.add(utf8.encode('fmt '));           // Subchunk1ID
    wav.add(_intToLittleEndian(16, 4));         // Subchunk1Size (16 for PCM)
    wav.add(_intToLittleEndian(1, 2));          // AudioFormat (1 = PCM)
    wav.add(_intToLittleEndian(channels, 2));   // NumChannels
    wav.add(_intToLittleEndian(sampleRate, 4)); // SampleRate
    wav.add(_intToLittleEndian(byteRate, 4));   // ByteRate
    wav.add(_intToLittleEndian(blockAlign, 2)); // BlockAlign
    wav.add(_intToLittleEndian(bitsPerSample, 2)); // BitsPerSample
    
    // data Subchunk (8 bytes + data)
    wav.add(utf8.encode('data'));           // Subchunk2ID
    wav.add(_intToLittleEndian(dataSize, 4));   // Subchunk2Size
    wav.add(pcmData);                       // Actual audio data
    
    final result = wav.toBytes();
    
    AppLogger.debug('📊 WAV Format Details: sampleRate=$sampleRate, dataSize=$dataSize, totalWavSize=${result.length}');
    
    return result;
  }
  
  /// Convert integer to little-endian bytes
  Uint8List _intToLittleEndian(int value, int bytes) {
    final result = Uint8List(bytes);
    for (int i = 0; i < bytes; i++) {
      result[i] = (value >> (8 * i)) & 0xFF;
    }
    return result;
  }
  
  /// Stop playback and clear queue
  Future<void> stop() async {
    try {
      await _player.stop();
      _isPlaying = false;
      _queue.clear();
      AppLogger.info('🛑 Playback stopped and queue cleared');
    } catch (e) {
      AppLogger.error('Error stopping playback: $e');
    }
  }
  
  /// Pause playback
  Future<void> pause() async {
    try {
      await _player.pause();
      AppLogger.info('⏸️ Playback paused');
    } catch (e) {
      AppLogger.error('Error pausing playback: $e');
    }
  }
  
  /// Resume playback
  Future<void> resume() async {
    try {
      await _player.play();
      AppLogger.info('▶️ Playback resumed');
    } catch (e) {
      AppLogger.error('Error resuming playback: $e');
    }
  }
  
  /// Get playback state
  bool get isPlaying => _isPlaying;
  
  /// Get queue size
  int get queueSize => _queue.length;
  
  /// Dispose resources
  Future<void> dispose() async {
    try {
      await _player.dispose();
      _queue.clear();
      _isPlaying = false;
      _isInitialized = false;
      AppLogger.info('ReliableAudioPlayer disposed');
    } catch (e) {
      AppLogger.error('Error disposing audio player: $e');
    }
  }
}

/// Memory-based audio source for just_audio
class _MemoryAudioSource extends StreamAudioSource {
  final Uint8List _audioData;
  
  _MemoryAudioSource(this._audioData);
  
  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _audioData.length;
    
    return StreamAudioResponse(
      sourceLength: _audioData.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_audioData.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}

/// Audio chunk data
class AudioChunk {
  final String id;
  final Uint8List data;
  
  AudioChunk(this.id, this.data);
}