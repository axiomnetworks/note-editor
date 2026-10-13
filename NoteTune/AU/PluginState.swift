import Foundation
import AudioToolbox
import AVFoundation
import os

/// Audio-thread state shared between the render block and the main thread. Guarded by an unfair lock;
/// the render block only try-locks and skips processing (passes audio through) if the lock is busy.
final class PluginState {
    var mode = 0                    // 0 bypass, 1 capture, 2 edited playback
    var sampleRate = 44100.0
    var transport: AUHostTransportStateBlock?

    private let capacity = 240 * 48000
    private let cap: UnsafeMutablePointer<Float>
    private var capCount = 0
    private var capStart = 0
    private var capStarted = false
    private var seqPos = 0

    private var edited: UnsafeMutablePointer<Float>?
    private var editedCount = 0
    private var aud: UnsafeMutablePointer<Float>?
    private var audCount = 0
    private var audPos = 0

    private let lock: UnsafeMutablePointer<os_unfair_lock>

    init() {
        cap = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
        cap.initialize(repeating: 0, count: capacity)
        lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }
    deinit {
        cap.deallocate(); edited?.deallocate(); aud?.deallocate(); lock.deallocate()
    }

    // MARK: main-thread API
    func resetCapture() {
        os_unfair_lock_lock(lock); defer { os_unfair_lock_unlock(lock) }
        capCount = 0; capStarted = false; seqPos = 0
        edited?.deallocate(); edited = nil; editedCount = 0
    }
    var capturedSeconds: Double {
        os_unfair_lock_lock(lock); defer { os_unfair_lock_unlock(lock) }
        return Double(capCount) / sampleRate
    }
    func copyCaptured() -> [Float] {
        os_unfair_lock_lock(lock); defer { os_unfair_lock_unlock(lock) }
        return Array(UnsafeBufferPointer(start: cap, count: capCount))
    }
    func setEdited(_ samples: [Float]) {
        os_unfair_lock_lock(lock); defer { os_unfair_lock_unlock(lock) }
        edited?.deallocate(); edited = nil; editedCount = 0
        guard !samples.isEmpty else { return }
        let p = UnsafeMutablePointer<Float>.allocate(capacity: samples.count)
        p.initialize(from: samples, count: samples.count)
        edited = p; editedCount = samples.count
    }
    func setAudition(_ samples: [Float]) {
        os_unfair_lock_lock(lock); defer { os_unfair_lock_unlock(lock) }
        aud?.deallocate(); aud = nil; audCount = 0; audPos = 0
        guard !samples.isEmpty else { return }
        let p = UnsafeMutablePointer<Float>.allocate(capacity: samples.count)
        p.initialize(from: samples, count: samples.count)
        aud = p; audCount = samples.count
    }

    // MARK: audio thread
    func process(_ abl: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard os_unfair_lock_trylock(lock) else { return }
        defer { os_unfair_lock_unlock(lock) }
        let list = UnsafeMutableAudioBufferListPointer(abl)
        let nch = list.count
        guard nch > 0 else { return }

        var pos = -1
        if let t = transport {
            var fl = AUHostTransportStateFlags()
            var p = 0.0
            if t(&fl, &p, nil, nil), fl.contains(.moving) { pos = Int(p) }
        }

        if mode == 1 {
            var idx = seqPos
            if pos >= 0 {
                if !capStarted { capStart = pos; capStarted = true; capCount = 0 }
                idx = pos - capStart
            }
            if idx >= 0 && idx + frames <= capacity {
                for i in 0..<frames {
                    var s: Float = 0
                    for b in 0..<nch {
                        if let d = list[b].mData { s += d.assumingMemoryBound(to: Float.self)[i] }
                    }
                    cap[idx + i] = s / Float(nch)
                }
                if idx + frames > capCount { capCount = idx + frames }
            }
            seqPos = idx + frames
        } else if mode == 2, let clip = edited, pos >= 0 {
            let idx = pos - capStart
            for i in 0..<frames {
                let j = idx + i
                if j >= 0 && j < editedCount {
                    for b in 0..<nch {
                        if let d = list[b].mData { d.assumingMemoryBound(to: Float.self)[i] = clip[j] }
                    }
                }
            }
        }

        if let a = aud, audPos < audCount {
            for i in 0..<frames {
                let j = audPos + i
                let v: Float = j < audCount ? a[j] : 0
                for b in 0..<nch {
                    if let d = list[b].mData { d.assumingMemoryBound(to: Float.self)[i] = v }
                }
            }
            audPos += frames
        }
    }
}
