import Foundation
import AVFoundation

final class AudioEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let pitch = AVAudioUnitTimePitch()
    private(set) var buffer: AVAudioPCMBuffer?
    private(set) var mono: [Float] = []
    private(set) var sampleRate: Double = 44100
    private var generation = 0

    init() {
        engine.attach(player); engine.attach(pitch)
    }

    func load(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        let fmt = file.processingFormat
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw NSError(domain: "NoteTune", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not allocate audio buffer"])
        }
        try file.read(into: buf)
        buffer = buf
        sampleRate = fmt.sampleRate
        let n = Int(buf.frameLength), ch = Int(fmt.channelCount)
        var m = [Float](repeating: 0, count: n)
        if let data = buf.floatChannelData {
            for c in 0..<ch { for i in 0..<n { m[i] += data[c][i] / Float(ch) } }
        }
        mono = m
        engine.stop()
        engine.disconnectNodeOutput(player); engine.disconnectNodeOutput(pitch)
        engine.connect(player, to: pitch, format: fmt)
        engine.connect(pitch, to: engine.mainMixerNode, format: fmt)
        engine.prepare()
        try engine.start()
    }

    func stop() { generation += 1; player.stop() }

    /// Plays a note segment at a pitch offset in cents. Cuts any current playback.
    func play(start: Double, end: Double, cents: Double, maxLength: Double = 1.5, completion: (() -> Void)? = nil) {
        guard let buf = buffer else { return }
        generation += 1
        let myGen = generation
        player.stop()
        pitch.pitch = Float(max(-2400, min(2400, cents)))
        let sr = sampleRate
        let s = max(0, Int(start * sr))
        let e = min(Int(buf.frameLength), Int(min(end, start + maxLength) * sr))
        guard e > s, let seg = AVAudioPCMBuffer(pcmFormat: buf.format, frameCapacity: AVAudioFrameCount(e - s)),
              let src = buf.floatChannelData, let dst = seg.floatChannelData else { return }
        let fade = min(Int(0.01 * sr), (e - s) / 4)
        for c in 0..<Int(buf.format.channelCount) {
            for i in 0..<(e - s) {
                var g: Float = 1
                if i < fade { g = Float(i) / Float(max(1, fade)) }
                if i > (e - s) - fade { g = Float((e - s) - i) / Float(max(1, fade)) }
                dst[c][i] = src[c][s + i] * g
            }
        }
        seg.frameLength = AVAudioFrameCount(e - s)
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(seg, at: nil, options: [], completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                if self?.generation == myGen { completion?() }
            }
        }
        player.play()
    }

    /// Original, short gap, then edited.
    func playBeforeAfter(start: Double, end: Double, cents: Double) {
        play(start: start, end: end, cents: 0, maxLength: 1.2) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.play(start: start, end: end, cents: cents, maxLength: 1.2)
            }
        }
    }
}
