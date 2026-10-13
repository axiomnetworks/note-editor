import Foundation

struct Note: Identifiable, Equatable {
    let id: Int
    var start: Double        // seconds
    var end: Double
    let detectedMidi: Double // median detected pitch, fractional MIDI
    let spread: Double       // semitone std dev (vibrato/drift)
    var editCents: Double = 0

    var length: Double { end - start }
    var detectedNearest: Int { Int(detectedMidi.rounded()) }
    var detectedCents: Double { (detectedMidi - Double(detectedNearest)) * 100 }
    var currentMidi: Double { detectedMidi + editCents / 100 }
    var currentNearest: Int { Int(currentMidi.rounded()) }
    var currentCentsOff: Double { (currentMidi - Double(currentNearest)) * 100 }
}

enum NoteNames {
    static let names = ["C", "C sharp", "D", "E flat", "E", "F", "F sharp", "G", "A flat", "A", "B flat", "B"]
    static func name(_ midi: Int) -> String {
        let n = ((midi % 12) + 12) % 12
        return "\(names[n]) \(midi / 12 - 1)"
    }
}

enum Detector {
    static let hop = 256
    static let win = 1024

    /// YIN pitch tracker + note segmenter. Original implementation, no third-party code.
    static func analyze(samples x: [Float], sampleRate sr: Double) -> [Note] {
        let fmin = 70.0, fmax = 900.0, th: Float = 0.15
        let tmax = Int(sr / fmin), tmin = Int(sr / fmax)
        guard x.count > win + tmax + hop else { return [] }
        var midi: [Double?] = []
        var centers: [Double] = []
        var d = [Float](repeating: 0, count: tmax + 1)
        var cm = [Float](repeating: 1, count: tmax + 1)
        var s = 0
        while s + win + tmax < x.count {
            centers.append((Double(s) + Double(win) / 2) / sr)
            var e: Float = 0
            for j in 0..<win { e += x[s + j] * x[s + j] }
            let rms = (e / Float(win)).squareRoot()
            if rms < 0.01 { midi.append(nil); s += hop; continue }
            x.withUnsafeBufferPointer { p in
                for tau in 1...tmax {
                    var sum: Float = 0
                    for j in 0..<win {
                        let diff = p[s + j] - p[s + j + tau]
                        sum += diff * diff
                    }
                    d[tau] = sum
                }
            }
            var running: Float = 0
            cm[0] = 1
            for tau in 1...tmax {
                running += d[tau]
                cm[tau] = running > 1e-12 ? d[tau] * Float(tau) / running : 1
            }
            var found = -1
            var k = tmin
            while k < tmax - 1 {
                if cm[k] < th {
                    while k + 1 < tmax && cm[k + 1] < cm[k] { k += 1 }
                    found = k; break
                }
                k += 1
            }
            if found < 1 { midi.append(nil); s += hop; continue }
            let a = cm[found - 1], b = cm[found], c = cm[found + 1]
            let den = a - 2 * b + c
            let t = Double(found) + (den != 0 ? Double(0.5 * (a - c) / den) : 0)
            let f0 = sr / t
            midi.append(69 + 12 * log2(f0 / 440))
            s += hop
        }
        return segment(midi: midi, centers: centers, sampleRate: sr)
    }

    static func median(_ v: [Double]) -> Double {
        let s = v.sorted(); return s.isEmpty ? 0 : s[s.count / 2]
    }

    static func segment(midi: [Double?], centers: [Double], sampleRate sr: Double) -> [Note] {
        var notes: [Note] = []
        var cur: [(Int, Double)] = []
        let frameDur = Double(hop) / sr
        func flush() {
            if cur.isEmpty { return }
            let first = cur.first!.0, last = cur.last!.0
            let v = cur.map { $0.1 }
            let start = centers[first] - frameDur / 2
            let end = centers[last] + frameDur / 2
            if end - start >= 0.08 {
                let med = median(v)
                let mean = v.reduce(0, +) / Double(v.count)
                let sd = (v.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(v.count)).squareRoot()
                notes.append(Note(id: notes.count, start: max(0, start), end: end, detectedMidi: med, spread: sd))
            }
            cur.removeAll()
        }
        for i in 0..<midi.count {
            guard let m = midi[i] else { flush(); continue }
            if !cur.isEmpty {
                let ref = median(cur.suffix(8).map { $0.1 })
                if abs(m - ref) > 0.7 {
                    let nxt = midi[i..<min(i + 4, midi.count)].compactMap { $0 }
                    if nxt.count >= 3 && abs(median(nxt) - ref) > 0.7 { flush() }
                }
            }
            cur.append((i, m))
        }
        flush()
        return notes
    }
}
