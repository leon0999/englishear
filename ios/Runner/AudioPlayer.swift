import Foundation
import AVFoundation
import Flutter

/// Native iOS audio player using AVAudioEngine for optimal performance
/// Similar to ChatGPT Voice's approach for low-latency audio playback
@objc class AudioPlayer: NSObject {
    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private let mixer = AVAudioMixerNode()
    
    // Audio format (24kHz mono PCM16 from OpenAI)
    private let inputFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24000,
        channels: 1,
        interleaved: false
    )!
    
    // Output format (device native)
    private lazy var outputFormat: AVAudioFormat = {
        return audioEngine.outputNode.inputFormat(forBus: 0)
    }()
    
    // Processing format (float32 for audio engine)
    private let processingFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24000,
        channels: 1,
        interleaved: false
    )!
    
    // Buffer queue for smooth playback
    private var bufferQueue = [AVAudioPCMBuffer]()
    private let queueLock = NSLock()
    private var isPlaying = false
    
    // Performance metrics
    private var totalChunksPlayed = 0
    private var totalBytesPlayed = 0
    
    override init() {
        super.init()
        setupAudioEngine()
        configureAudioSession()
    }
    
    /// Configure audio session for low-latency playback
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // Configure for playback with low latency
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,  // Optimized for voice
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
            
            // Set preferred buffer duration for low latency (5ms)
            try session.setPreferredIOBufferDuration(0.005)
            
            // Activate session
            try session.setActive(true)
            
            print("✅ Audio session configured for low-latency playback")
        } catch {
            print("❌ Failed to configure audio session: \(error)")
        }
    }
    
    /// Setup audio engine with nodes and connections
    private func setupAudioEngine() {
        // Attach nodes
        audioEngine.attach(playerNode)
        audioEngine.attach(mixer)
        
        // Connect player -> mixer -> output
        audioEngine.connect(
            playerNode,
            to: mixer,
            format: processingFormat
        )
        
        audioEngine.connect(
            mixer,
            to: audioEngine.outputNode,
            format: outputFormat
        )
        
        // Set mixer volume
        mixer.volume = 1.0
        
        // Prepare and start engine
        audioEngine.prepare()
        
        do {
            try audioEngine.start()
            playerNode.play()
            isPlaying = true
            print("✅ Audio engine started successfully")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
        }
    }
    
    /// Play PCM16 audio data
    @objc func playPCMData(_ data: Data, sampleRate: Int, channels: Int, chunkId: String) -> Bool {
        guard audioEngine.isRunning else {
            print("⚠️ Audio engine not running")
            return false
        }
        
        // Convert PCM16 to Float32 buffer
        guard let buffer = createBuffer(from: data) else {
            print("❌ Failed to create audio buffer for chunk \(chunkId)")
            return false
        }
        
        // Schedule buffer for playback
        scheduleBuffer(buffer, chunkId: chunkId)
        
        return true
    }
    
    /// Create audio buffer from PCM16 data
    private func createBuffer(from data: Data) -> AVAudioPCMBuffer? {
        let frameCount = data.count / 2  // 16-bit samples
        
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: processingFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            return nil
        }
        
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        // Convert PCM16 to Float32
        let int16Pointer = data.withUnsafeBytes { bytes in
            bytes.bindMemory(to: Int16.self)
        }
        
        let floatPointer = buffer.floatChannelData![0]
        
        for i in 0..<frameCount {
            // Normalize to [-1.0, 1.0]
            floatPointer[i] = Float(int16Pointer[i]) / 32768.0
        }
        
        return buffer
    }
    
    /// Schedule buffer for playback with queue management
    private func scheduleBuffer(_ buffer: AVAudioPCMBuffer, chunkId: String) {
        queueLock.lock()
        defer { queueLock.unlock() }
        
        // Schedule immediately for low latency
        playerNode.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            self?.onBufferCompleted(chunkId: chunkId)
        }
        
        totalChunksPlayed += 1
        totalBytesPlayed += Int(buffer.frameLength) * 2
        
        // Log every 10th chunk for performance monitoring
        if totalChunksPlayed % 10 == 0 {
            print("📊 Audio stats: \(totalChunksPlayed) chunks, \(totalBytesPlayed) bytes played")
        }
    }
    
    /// Called when buffer playback completes
    private func onBufferCompleted(chunkId: String) {
        print("✅ Completed playback of chunk \(chunkId)")
    }
    
    /// Start streaming mode for continuous playback
    @objc func startStreaming(sampleRate: Int, channels: Int, bitsPerSample: Int) {
        if !audioEngine.isRunning {
            setupAudioEngine()
        }
        
        if !playerNode.isPlaying {
            playerNode.play()
        }
        
        print("🎵 Started streaming mode")
    }
    
    /// Stream a chunk of audio data
    @objc func streamChunk(_ data: Data) -> Bool {
        return playPCMData(data, sampleRate: 24000, channels: 1, chunkId: "stream_\(Date().timeIntervalSince1970)")
    }
    
    /// End streaming mode
    @objc func endStreaming() {
        // Flush any remaining buffers
        print("🏁 Ended streaming mode")
    }
    
    /// Stop all playback
    @objc func stopPlayback() {
        playerNode.stop()
        isPlaying = false
        print("⏹ Playback stopped")
    }
    
    /// Pause playback
    @objc func pausePlayback() {
        playerNode.pause()
        print("⏸ Playback paused")
    }
    
    /// Resume playback
    @objc func resumePlayback() {
        playerNode.play()
        print("▶️ Playback resumed")
    }
    
    /// Check if playing
    @objc func isPlayingAudio() -> Bool {
        return playerNode.isPlaying
    }
    
    /// Set volume (0.0 to 1.0)
    @objc func setVolume(_ volume: Float) {
        mixer.volume = max(0.0, min(1.0, volume))
        print("🔊 Volume set to \(Int(mixer.volume * 100))%")
    }
    
    /// Clean up resources
    @objc func dispose() {
        stopPlayback()
        audioEngine.stop()
        print("🗑 Audio player disposed")
    }
    
    deinit {
        dispose()
    }
}

/// Flutter method channel handler
@objc class AudioChannelHandler: NSObject, FlutterPlugin {
    private var audioPlayer: AudioPlayer?
    
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.englishear/audio",
            binaryMessenger: registrar.messenger()
        )
        let instance = AudioChannelHandler()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initializeAudioEngine":
            initializeAudioEngine(result: result)
            
        case "playPCM":
            playPCM(call: call, result: result)
            
        case "startStreaming":
            startStreaming(call: call, result: result)
            
        case "streamChunk":
            streamChunk(call: call, result: result)
            
        case "endStreaming":
            endStreaming(result: result)
            
        case "stopPlayback":
            stopPlayback(result: result)
            
        case "pausePlayback":
            pausePlayback(result: result)
            
        case "resumePlayback":
            resumePlayback(result: result)
            
        case "isPlaying":
            isPlaying(result: result)
            
        case "setVolume":
            setVolume(call: call, result: result)
            
        case "dispose":
            dispose(result: result)
            
        case "configureAudioSession":
            configureAudioSession(call: call, result: result)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func initializeAudioEngine(result: FlutterResult) {
        audioPlayer = AudioPlayer()
        result(true)
    }
    
    private func playPCM(call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let data = args["data"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            return
        }
        
        let sampleRate = args["sampleRate"] as? Int ?? 24000
        let channels = args["channels"] as? Int ?? 1
        let chunkId = args["chunkId"] as? String ?? "unknown"
        
        if audioPlayer == nil {
            audioPlayer = AudioPlayer()
        }
        
        let success = audioPlayer?.playPCMData(
            data.data,
            sampleRate: sampleRate,
            channels: channels,
            chunkId: chunkId
        ) ?? false
        
        result(success)
    }
    
    private func startStreaming(call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            return
        }
        
        let sampleRate = args["sampleRate"] as? Int ?? 24000
        let channels = args["channels"] as? Int ?? 1
        let bitsPerSample = args["bitsPerSample"] as? Int ?? 16
        
        if audioPlayer == nil {
            audioPlayer = AudioPlayer()
        }
        
        audioPlayer?.startStreaming(
            sampleRate: sampleRate,
            channels: channels,
            bitsPerSample: bitsPerSample
        )
        
        result(true)
    }
    
    private func streamChunk(call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let data = args["data"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            return
        }
        
        let success = audioPlayer?.streamChunk(data.data) ?? false
        result(success)
    }
    
    private func endStreaming(result: FlutterResult) {
        audioPlayer?.endStreaming()
        result(true)
    }
    
    private func stopPlayback(result: FlutterResult) {
        audioPlayer?.stopPlayback()
        result(nil)
    }
    
    private func pausePlayback(result: FlutterResult) {
        audioPlayer?.pausePlayback()
        result(nil)
    }
    
    private func resumePlayback(result: FlutterResult) {
        audioPlayer?.resumePlayback()
        result(nil)
    }
    
    private func isPlaying(result: FlutterResult) {
        result(audioPlayer?.isPlayingAudio() ?? false)
    }
    
    private func setVolume(call: FlutterMethodCall, result: FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let volume = args["volume"] as? Double else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            return
        }
        
        audioPlayer?.setVolume(Float(volume))
        result(nil)
    }
    
    private func dispose(result: FlutterResult) {
        audioPlayer?.dispose()
        audioPlayer = nil
        result(nil)
    }
    
    private func configureAudioSession(call: FlutterMethodCall, result: FlutterResult) {
        // Audio session is configured in AudioPlayer init
        result(true)
    }
}