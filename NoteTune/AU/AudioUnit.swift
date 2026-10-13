import Foundation
import AudioToolbox
import AVFoundation
import CoreAudioKit

final class PluginControls: ObservableObject {
    @Published var mode: Int = 0
    @Published var status: String = "Mode: bypass. Choose Capture, then play the region you want to edit."
}

enum Addr: UInt64 {
    case mode = 0, selected, pitch, count, detected, current, cents
    case audition, beforeAfter, snap, reset, next, prev
}

final class NoteTuneAudioUnit: AUAudioUnit {
    let state = PluginState()
    let backend: PluginBackend
    let model: EditorModel
    let controls = PluginControls()

    private var inBus: AUAudioUnitBus!
    private var outBus: AUAudioUnitBus!
    private var inArray: AUAudioUnitBusArray!
    private var outArray: AUAudioUnitBusArray!
    private var _tree: AUParameterTree?
    private var syncing = false
    private var captured: [Float] = []
    private var renderWork: DispatchWorkItem?
    private var timer: Timer?

    private var pMode: AUParameter!, pSel: AUParameter!, pPitch: AUParameter!
    private var pCount: AUParameter!, pDet: AUParameter!, pCur: AUParameter!, pCents: AUParameter!
    private var pTrig: [Addr: AUParameter] = [:]
    // snapshot read by parameter provider (any thread)
    private let snapLock = NSLock()
    private var snap: [UInt64: Float] = [:]

    override init(componentDescription: AudioComponentDescription, options: AudioComponentInstantiationOptions = []) throws {
        backend = PluginBackend(state: state)
        model = EditorModel(backend: backend)
        try super.init(componentDescription: componentDescription, options: options)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        inBus = try AUAudioUnitBus(format: fmt)
        outBus = try AUAudioUnitBus(format: fmt)
        inArray = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inBus])
        outArray = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outBus])
        maximumFramesToRender = 4096
        buildParameters()
        model.onChange = { [weak self] in self?.modelChanged() }
        DispatchQueue.main.async { self.syncParams() }
    }

    override var inputBusses: AUAudioUnitBusArray { inArray }
    override var outputBusses: AUAudioUnitBusArray { outArray }
    override var parameterTree: AUParameterTree? {
        get { _tree }
        set { _tree = newValue }
    }
    override var latency: TimeInterval { 0 }
    override var canProcessInPlace: Bool { true }

    override func allocateRenderResources() throws {
        try super.allocateRenderResources()
        state.sampleRate = outBus.format.sampleRate
        state.transport = transportStateBlock
    }
    override func deallocateRenderResources() {
        super.deallocateRenderResources()
        state.transport = nil
    }

    override var internalRenderBlock: AUInternalRenderBlock {
        let st = state
        return { actionFlags, timestamp, frameCount, outputBusNumber, outputData, realtimeEventListHead, pullInputBlock in
            guard let pull = pullInputBlock else { return kAudioUnitErr_NoConnection }
            let err = pull(actionFlags, timestamp, frameCount, 0, outputData)
            if err != noErr { return err }
            st.process(outputData, frames: Int(frameCount))
            return noErr
        }
    }

    // MARK: parameters
    private func makeParam(_ id: String, _ name: String, _ a: Addr, _ lo: Float, _ hi: Float,
                           _ unit: AudioUnitParameterUnit, writable: Bool = true, meta: Bool = false, strings: [String]? = nil) -> AUParameter {
        var flags: AudioUnitParameterOptions = [.flag_IsReadable]
        if writable { flags.insert(.flag_IsWritable) }
        if meta { flags.insert(.flag_IsGlobalMeta) }
        return AUParameterTree.createParameter(withIdentifier: id, name: name, address: a.rawValue,
                                               min: lo, max: hi, unit: unit, unitName: nil,
                                               flags: flags, valueStrings: strings, dependentParameters: nil)
    }

    private func buildParameters() {
        pMode = makeParam("mode", "Mode", .mode, 0, 2, .indexed, meta: true, strings: ["Bypass", "Capture", "Edited playback"])
        pSel = makeParam("note", "Selected note", .selected, 0, 999, .generic, meta: true)
        pPitch = makeParam("pitchOffset", "Note pitch offset cents", .pitch, -1200, 1200, .cents, meta: true)
        pCount = makeParam("noteCount", "Note count", .count, 0, 999, .generic, writable: false)
        pDet = makeParam("detectedNote", "Detected note number", .detected, 0, 127, .midiNoteNumber, writable: false)
        pCur = makeParam("currentNote", "Current note number", .current, 0, 127, .midiNoteNumber, writable: false)
        pCents = makeParam("centsOff", "Cents off nearest note", .cents, -50, 50, .cents, writable: false)
        var all: [AUParameter] = [pMode, pSel, pPitch, pCount, pDet, pCur, pCents]
        let trig: [(Addr, String, String)] = [
            (.audition, "audition", "Play note"), (.beforeAfter, "beforeAfter", "Play before and after"),
            (.snap, "snap", "Snap note to nearest pitch"), (.reset, "reset", "Reset note"),
            (.next, "nextNote", "Next note"), (.prev, "prevNote", "Previous note")]
        for (a, id, name) in trig {
            let p = makeParam(id, name, a, 0, 1, .boolean, meta: true)
            pTrig[a] = p; all.append(p)
        }
        let tree = AUParameterTree.createTree(withChildren: all)
        tree.implementorValueObserver = { [weak self] param, value in
            self?.paramSet(param.address, value)
        }
        tree.implementorValueProvider = { [weak self] param in
            guard let self = self else { return 0 }
            self.snapLock.lock(); defer { self.snapLock.unlock() }
            return self.snap[param.address] ?? 0
        }
        _tree = tree
    }

    private func setSnap(_ a: Addr, _ v: Float) { snapLock.lock(); snap[a.rawValue] = v; snapLock.unlock() }

    private func paramSet(_ address: UInt64, _ value: Float) {
        if syncing { return }
        setSnap(Addr(rawValue: address) ?? .mode, value)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let a = Addr(rawValue: address) else { return }
            switch a {
            case .mode: self.setMode(Int(value.rounded()))
            case .selected:
                let i = Int(value.rounded()) - 1
                if i != self.model.selected && self.model.notes.indices.contains(i) { self.model.select(i) }
            case .pitch: self.model.setEdit(cents: Double(value))
            case .audition: if value >= 0.5 { self.model.audition(); self.clearTrigger(a) }
            case .beforeAfter: if value >= 0.5 { self.model.playBeforeAfter(); self.clearTrigger(a) }
            case .snap: if value >= 0.5 { self.model.snap(); self.clearTrigger(a) }
            case .reset: if value >= 0.5 { self.model.reset(); self.clearTrigger(a) }
            case .next: if value >= 0.5 { self.model.move(1); self.clearTrigger(a) }
            case .prev: if value >= 0.5 { self.model.move(-1); self.clearTrigger(a) }
            default: break
            }
        }
    }
    private func clearTrigger(_ a: Addr) {
        syncing = true; pTrig[a]?.value = 0; setSnap(a, 0); syncing = false
    }

    /// Push model state into the parameter tree so Logic's Controls view reads current values.
    private func syncParams() {
        let n = model.notes
        let i = model.selected
        syncing = true
        setSnap(.count, Float(n.count)); pCount.value = Float(n.count)
        if n.indices.contains(i) {
            let note = n[i]
            let vals: [(Addr, AUParameter, Float)] = [
                (.selected, pSel, Float(i + 1)), (.pitch, pPitch, Float(note.editCents)),
                (.detected, pDet, Float(note.detectedMidi)), (.current, pCur, Float(note.currentMidi)),
                (.cents, pCents, Float(note.currentCentsOff))]
            for (a, p, v) in vals { setSnap(a, v); p.value = v }
        } else {
            for (a, p) in [(Addr.selected, pSel!), (.pitch, pPitch!), (.detected, pDet!), (.current, pCur!), (.cents, pCents!)] {
                setSnap(a, 0); p.value = 0
            }
        }
        setSnap(.mode, Float(controls.mode)); pMode.value = Float(controls.mode)
        syncing = false
    }

    private func modelChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.syncParams()
            self.scheduleClipRender()
        }
    }

    private func scheduleClipRender() {
        renderWork?.cancel()
        guard !captured.isEmpty else { return }
        let clip = captured, sr = state.sampleRate, notes = model.notes
        let w = DispatchWorkItem { [weak self] in
            let out = Shifter.renderClip(clip, sampleRate: sr, notes: notes)
            self?.state.setEdited(out)
        }
        renderWork = w
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3, execute: w)
    }

    // MARK: mode / capture
    func setMode(_ m: Int) {
        let prev = controls.mode
        let new = max(0, min(2, m))
        if new == prev { return }
        controls.mode = new
        state.mode = new
        if new == 1 {
            state.resetCapture()
            captured = []; backend.mono = []
            model.notes = []
            controls.status = "Capturing. Start playback in Logic over the region you want to edit."
            model.announce("Capturing. Start playback.")
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.controls.status = String(format: "Capturing, %.1f seconds recorded", self.state.capturedSeconds)
            }
        } else if prev == 1 {
            timer?.invalidate(); timer = nil
            finishCapture()
        }
        syncParams()
    }

    private func finishCapture() {
        let samples = state.copyCaptured()
        if samples.count < Int(state.sampleRate * 0.3) {
            controls.status = "Nothing captured. Set Capture, then play the region."
            model.announce(controls.status)
            return
        }
        captured = samples
        backend.mono = samples
        backend.sampleRate = state.sampleRate
        controls.status = String(format: "Captured %.1f seconds. Analyzing.", Double(samples.count) / state.sampleRate)
        model.analyzeCaptured(samples: samples, sampleRate: state.sampleRate)
    }
}
