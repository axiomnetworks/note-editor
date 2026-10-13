import Foundation

/// Audition through the plugin's own output. Rendering happens off the audio thread; the render block just plays the buffer.
final class PluginBackend: AuditionBackend {
    let state: PluginState
    var mono: [Float] = []
    var sampleRate: Double = 44100
    private var gen = 0
    init(state: PluginState) { self.state = state }

    func load(url: URL) throws {
        throw NSError(domain: "NoteTune", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Plugin captures audio from the track. Switch mode to Capture and play the region."])
    }

    func play(start: Double, end: Double, cents: Double, maxLength: Double, completion: (() -> Void)?) {
        guard !mono.isEmpty else { return }
        let seg = Shifter.renderSegment(mono, sampleRate: sampleRate, start: start,
                                        end: min(end, start + maxLength), cents: cents)
        state.setAudition(withFades(seg))
        gen += 1
        let g = gen
        let dur = Double(seg.count) / sampleRate
        if let c = completion {
            DispatchQueue.main.asyncAfter(deadline: .now() + dur) { if self.gen == g { c() } }
        }
    }

    func playBeforeAfter(start: Double, end: Double, cents: Double) {
        guard !mono.isEmpty else { return }
        let e = min(end, start + 1.2)
        let a = withFades(Shifter.renderSegment(mono, sampleRate: sampleRate, start: start, end: e, cents: 0))
        let b = withFades(Shifter.renderSegment(mono, sampleRate: sampleRate, start: start, end: e, cents: cents))
        let gap = [Float](repeating: 0, count: Int(0.3 * sampleRate))
        state.setAudition(a + gap + b)
        gen += 1
    }

    func stop() { gen += 1; state.setAudition([]) }

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
