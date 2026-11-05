import AVFoundation

// Decode once, keep the output graph running silently, and replace scheduled PCM
// buffers on click. Stopping a clip never tears down the hardware audio device.
final class BufferedAudio {
    let engine = AVAudioEngine()
    let node = AVAudioPlayerNode()
    weak var active: BufferedClip?
    var generation = 0
    var onFinish: ((BufferedClip) -> Void)?
    init(format: AVAudioFormat) throws {
        engine.attach(node); engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare(); try engine.start()
    }
    func play(_ clip: BufferedClip) -> Bool {
        stop()
        do { if !engine.isRunning { try engine.start() } } catch { return false }
        active = clip; clip.isPlaying = true; node.volume = clip.volume
        let token = generation
        node.scheduleBuffer(clip.buffer, at: nil, options: clip.numberOfLoops == -1 ? [.loops] : [], completionCallbackType: .dataPlayedBack) { [weak self, weak clip] _ in
            DispatchQueue.main.async {
                guard let self, let clip, self.generation == token, self.active === clip else { return }
                clip.isPlaying = false; self.active = nil; self.onFinish?(clip)
            }
        }
        node.play(); return true
    }
    func stop() { generation += 1; active?.isPlaying = false; active = nil; node.stop() }
    func shutdown() { stop(); engine.stop() }
}

final class BufferedClip {
    let buffer: AVAudioPCMBuffer
    unowned let output: BufferedAudio
    var isPlaying = false
    var numberOfLoops = 0
    var volume: Float = 0.5 { didSet { if output.active === self { output.node.volume = volume } } }
    var duration: Double { Double(buffer.frameLength) / buffer.format.sampleRate }
    var currentTime: Double = 0 // Every play is scheduled from the start of its decoded buffer.
    init(buffer: AVAudioPCMBuffer, output: BufferedAudio) { self.buffer = buffer; self.output = output }
    func prepareToPlay() -> Bool { true }
    func play() -> Bool { output.play(self) }
    func stop() { if output.active === self { output.stop() }; isPlaying = false }
}
