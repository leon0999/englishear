import 'dart:async';

class MockAudioPlayer {
  final _stateController = StreamController<PlayerState>.broadcast();
  
  Stream<PlayerState> get processingStateStream => _stateController.stream;
  Stream<dynamic> get playerStateStream => _stateController.stream;
  bool get isPlaying => false;
  
  Future<void> setFilePath(String path) async {
    // Mock implementation
    await Future.delayed(Duration(milliseconds: 100));
  }
  
  Future<void> setAudioSource(dynamic source) async {
    // Mock implementation
    await Future.delayed(Duration(milliseconds: 100));
  }
  
  Future<void> play() async {
    _stateController.add(PlayerState.playing);
    await Future.delayed(Duration(milliseconds: 100));
  }
  
  Future<void> stop() async {
    _stateController.add(PlayerState.stopped);
    await Future.delayed(Duration(milliseconds: 100));
  }
  
  Future<void> setVolume(double volume) async {
    // Mock implementation
  }
  
  Future<void> dispose() async {
    await _stateController.close();
  }
}

enum PlayerState {
  playing,
  stopped,
  completed
}

class ProcessingState {
  static const completed = 'completed';
}