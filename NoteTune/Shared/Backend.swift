import Foundation

/// Where audition audio comes from and goes to. Standalone app: AVAudioEngine. Plugin: the AU's own output.
protocol AuditionBackend: AnyObject {
    var mono: [Float] { get }
    var sampleRate: Double { get }
    func load(url: URL) throws
    func play(start: Double, end: Double, cents: Double, maxLength: Double, completion: (() -> Void)?)
    func playBeforeAfter(start: Double, end: Double, cents: Double)
    func stop()
}

/// Offline pitch shifter: resample, then WSOLA time-stretch back to original length. Original code.
enum Shifter {
    static func shift(_ x: [Float], cents: Double) -> [Float] {
        if abs(cents) < 0.5 || x.count < 4096 { return x }
        let ratio = pow(2.0, cents / 1200.0)
        let m = Int(Double(x.count) / ratio)
        if m < 2048 { return x }
        var y = [Float](repeating: 0, count: m)
        for n in 0..<m {
            let p = Double(n) * ratio
            let i = min(Int(p), x.count - 1)
            let f = Float(p - Double(i))
            let a = x[i]
            let b = i + 1 < x.count ? x[i + 1] : a
            y[n] = a + (b - a) * f
        }
        return wsola(y, outLength: x.count)
    }

    static func wsola(_ y: [Float], outLength: Int) -> [Float] {
        let N = 1024, H = 512, S = 200
        var out = [Float](repeating: 0, count: outLength + 2 * N)
        let w: [Float] = (0..<N).map { 0.5 - 0.5 * cos(2 * Float.pi * Float($0) / Float(N)) }
        var w0 = w
        for j in 0..<(N / 2) { w0[j] = 1 }
        let ratio = Double(y.count) / Double(outLength)
        let maxStart = max(0, y.count - N - 1)
        var prevPos = 0
        var k = 0
        var outPos = 0
        while outPos < outLength {
            let target = min(maxStart, Int(Double(k) * Double(H) * ratio))
            var best = target
            if k > 0 {
                let ref = prevPos + H
                var bestC = -Float.greatestFiniteMagnitude
                let lo = max(0, target - S), hi = min(maxStart, target + S)
                if lo <= hi {
                    var cand = lo
                    while cand <= hi {
                        var c: Float = 0
                        var j = 0
                        while j < N / 2 {
                            let r = ref + j
                            if r < y.count { c += y[cand + j] * y[r] }
                            j += 2
                        }
                        if c > bestC { bestC = c; best = cand }
                        cand += 2
                    }
                }
            }
            let win = k == 0 ? w0 : w
            for j in 0..<N where best + j < y.count { out[outPos + j] += y[best + j] * win[j] }
            prevPos = best
            outPos += H
            k += 1
        }
        return Array(out[0..<outLength])
    }

    /// Shift one note segment out of a clip and return it with short edge fades.
    static func renderSegment(_ clip: [Float], sampleRate sr: Double, start: Double, end: Double, cents: Double) -> [Float] {
        let s = max(0, Int(start * sr)), e = min(clip.count, Int(end * sr))
        guard e > s else { return [] }
        return shift(Array(clip[s..<e]), cents: cents)
    }

    /// Whole clip with every edited note shifted, blended into the original at note edges.
    static func renderClip(_ clip: [Float], sampleRate sr: Double, notes: [Note]) -> [Float] {
        var out = clip
        let fade = max(1, Int(0.01 * sr))
        for n in notes where abs(n.editCents) >= 0.5 {
            let s = max(0, Int(n.start * sr)), e = min(clip.count, Int(n.end * sr))
            if e - s < 4096 { continue }
            let seg = shift(Array(clip[s..<e]), cents: n.editCents)
            for i in 0..<seg.count {
                var g: Float = 1
                if i < fade { g = Float(i) / Float(fade) }
                if i > seg.count - fade { g = Float(seg.count - i) / Float(fade) }
                out[s + i] = seg[i] * g + clip[s + i] * (1 - g)
            }
        }
        return out
    }
}
