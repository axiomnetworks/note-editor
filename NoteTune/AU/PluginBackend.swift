import Foundation
import AVFoundation

/// Audition plays through the plugin process's own audio engine, so it works whether or not Logic is
/// rendering the insert (Logic stopped, track idle). Edited playback on the track still uses the AU output.
final class PluginBackend: AuditionBackend {
    let state: PluginState
    var mono: [Float] = []
    var sampleRate: Double = 44100
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var configuredRate = 0.0
    private var gen = 0
    var lastError = ""
    /// 0 = Logic output only, 1 = plugin engine only, 2 = both
    var route = 2
    private var plays = 0
    var info: String {
        "Audition route \(["Logic output", "Plugin engine", "Both"][route]). Plays requested \(plays). Engine \(engine.isRunning ? "running" : "not running"). \(lastError)"
    }

    init(state: PluginState) { self.state = state; engine.attach(player) }

    func load(url: URL) throws {
        throw NSError(domain: "NoteTune", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Plugin captures audio from the track. Switch mode to Capture and play the region."])
    }

    private func ensureEngine() -> Bool {
        if configuredRate != sampleRate || !engine.isRunning {
            engine.stop()
            engine.disconnectNodeOutput(player)
            guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else { return false }
            engine.connect(player, to: engine.mainMixerNode, format: fmt)
            engine.prepare()
            do { try engine.start(); configuredRate = sampleRate; lastError = "" }
            catch { lastError = "Audio engine failed: \(error.localizedDescription)"; return false }
        }
        return true
    }

    private func playSamples(_ x: [Float]) {
        plays += 1
        if route != 1 { state.setAudition(x) }
        if route == 0 { return }
        guard !x.isEmpty, ensureEngine(),
              let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(x.count)),
              let d = buf.floatChannelData else { return }
        for i in 0..<x.count { d[0][i] = x[i] }
        buf.frameLength = AVAudioFrameCount(x.count)
        player.stop()
        player.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        player.play()
    }

    func play(start: Double, end: Double, cents: Double, maxLength: Double, completion: (() -> Void)?) {
        guard !mono.isEmpty else { return }
        gen += 1
        let seg = Shifter.renderSegment(mono, sampleRate: sampleRate, start: start,
                                        end: min(end, start + maxLength), cents: cents)
        playSamples(withFades(seg))
        if let c = completion {
            let g = gen
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(seg.count) / sampleRate) { if self.gen == g { c() } }
        }
    }

    func playBeforeAfter(start: Double, end: Double, cents: Double) {
        guard !mono.isEmpty else { return }
        gen += 1
        let e = min(end, start + 1.2)
        let a = withFades(Shifter.renderSegment(mono, sampleRate: sampleRate, start: start, end: e, cents: 0))
        let b = withFades(Shifter.renderSegment(mono, sampleRate: sampleRate, start: start, end: e, cents: cents))
        playSamples(a + [Float](repeating: 0, count: Int(0.3 * sampleRate)) + b)
    }

    func stop() { gen += 1; player.stop(); state.setAudition([]) }

    private func withFades(_ x: [Float]) -> [Float] {
        var y = x
        let f = min(Int(0.01 * sampleRate), y.count / 4)
        for i in 0..<f {
            let g = Float(i) / Float(max(1, f))
            y[i] *= g; y[y.count - 1 - i] *= g
        }
        return y
    }
}
