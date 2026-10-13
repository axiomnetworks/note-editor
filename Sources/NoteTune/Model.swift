import Foundation
import AppKit
import SwiftUI

final class EditorModel: ObservableObject {
    @Published var notes: [Note] = []
    @Published var selected: Int = 0
    @Published var status: String = "No file open. Press Command O to open an audio file."
    @Published var bpm: Double = 100
    @Published var busy = false
    let audio = AudioEngine()
    private var undoStack: [[Note]] = []
    private var redoStack: [[Note]] = []
    private var announceWork: DispatchWorkItem?
    private var lastEditTime = Date.distantPast

    // MARK: description
    func position(_ t: Double) -> String {
        let beats = t * bpm / 60
        let bar = Int(beats / 4) + 1
        let beat = beats.truncatingRemainder(dividingBy: 4) + 1
        return String(format: "bar %d beat %.1f", bar, beat)
    }
    func centsText(_ c: Double) -> String {
        let r = Int(c.rounded())
        if r == 0 { return "in tune" }
        return "\(abs(r)) cents \(r > 0 ? "sharp" : "flat")"
    }
    func describe(_ i: Int, full: Bool = true) -> String {
        guard notes.indices.contains(i) else { return "No note" }
        let n = notes[i]
        var s = "Note \(i + 1), \(NoteNames.name(n.currentNearest)), \(centsText(n.currentCentsOff))"
        if full {
            s += String(format: ", %@, length %.2f seconds", position(n.start), n.length)
            if n.editCents != 0 {
                let e = Int(n.editCents.rounded())
                s += ", edited \(e > 0 ? "up" : "down") \(abs(e)) cents"
            } else { s += ", original" }
        }
        return s
    }
    func shortDescribe(_ i: Int) -> String {
        guard notes.indices.contains(i) else { return "" }
        let n = notes[i]
        return "\(NoteNames.name(n.currentNearest)), \(centsText(n.currentCentsOff))"
    }

    // MARK: speech
    func announce(_ text: String, delay: Double = 0) {
        announceWork?.cancel()
        let w = DispatchWorkItem {
            let el: Any = NSApp.mainWindow ?? NSApp as Any
            NSAccessibility.post(element: el, notification: .announcementRequested,
                                 userInfo: [.announcement: text,
                                            .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
        announceWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    // MARK: file
    func open(url: URL) {
        busy = true
        status = "Analyzing \(url.lastPathComponent)"
        announce(status)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.audio.load(url: url)
                let found = Detector.analyze(samples: self.audio.mono, sampleRate: self.audio.sampleRate)
                DispatchQueue.main.async {
                    self.notes = found; self.selected = 0
                    self.undoStack = []; self.redoStack = []
                    self.busy = false
                    self.status = found.isEmpty ? "No notes found in \(url.lastPathComponent)"
                        : "Found \(found.count) notes in \(url.lastPathComponent). " + self.describe(0)
                    self.announce(self.status)
                    if !found.isEmpty { self.audition() }
                }
            } catch {
                DispatchQueue.main.async {
                    self.busy = false
                    self.status = "Could not open file: \(error.localizedDescription)"
                    self.announce(self.status)
                }
            }
        }
    }

    // MARK: commands
    func edge() { NSSound.beep() }

    func move(_ delta: Int) {
        guard !notes.isEmpty else { return }
        let n = selected + delta
        guard notes.indices.contains(n) else { edge(); announce(delta > 0 ? "Last note" : "First note"); return }
        select(n)
    }
    func select(_ n: Int) {
        guard notes.indices.contains(n) else { return }
        selected = n
        audition()
        announce(describe(n), delay: 0.15)
    }
    func jumpOutOfTune(_ delta: Int, threshold: Double = 15) {
        guard !notes.isEmpty else { return }
        var i = selected + delta
        while notes.indices.contains(i) {
            if abs(notes[i].currentCentsOff) > threshold { select(i); return }
            i += delta
        }
        edge(); announce("No more out of tune notes")
    }

    private func pushUndo() {
        // group rapid edits of the same note into one undo step
        if Date().timeIntervalSince(lastEditTime) > 1.0 || undoStack.isEmpty {
            undoStack.append(notes); redoStack = []
        }
        lastEditTime = Date()
    }
    func tune(cents: Double) {
        guard notes.indices.contains(selected) else { return }
        pushUndo()
        notes[selected].editCents += cents
        audition()
        announce(shortDescribe(selected), delay: 0.25)
    }
    func snap() {
        guard notes.indices.contains(selected) else { return }
        pushUndo()
        let n = notes[selected]
        notes[selected].editCents = (Double(n.detectedNearest) - n.detectedMidi) * 100
        audition(); announce("Snapped. " + shortDescribe(selected), delay: 0.25)
    }
    func reset() {
        guard notes.indices.contains(selected) else { return }
        pushUndo(); notes[selected].editCents = 0
        audition(); announce("Reset. " + shortDescribe(selected), delay: 0.25)
    }
    func undo() {
        guard let prev = undoStack.popLast() else { edge(); announce("Nothing to undo"); return }
        redoStack.append(notes); notes = prev; lastEditTime = .distantPast
        audition(); announce("Undone. " + shortDescribe(selected), delay: 0.25)
    }
    func redo() {
        guard let next = redoStack.popLast() else { edge(); announce("Nothing to redo"); return }
        undoStack.append(notes); notes = next; lastEditTime = .distantPast
        audition(); announce("Redone. " + shortDescribe(selected), delay: 0.25)
    }
    func audition() {
        guard notes.indices.contains(selected) else { return }
        let n = notes[selected]
        audio.play(start: n.start, end: n.end, cents: n.editCents)
    }
    func playBeforeAfter() {
        guard notes.indices.contains(selected) else { return }
        let n = notes[selected]
        audio.playBeforeAfter(start: n.start, end: n.end, cents: n.editCents)
        announce("Before, then after", delay: 0)
    }
    func speakInfo() { announce(describe(selected)) }
    func stop() { audio.stop() }
    func help() {
        announce("Left and right bracket: previous and next note. Up and down arrow: semitone. Left and right arrow: 5 cents. Shift with arrows: 1 cent, or octave. Option with left and right: 20 cents. Space: play note. B: before and after. Return: snap to nearest pitch. Delete: reset note. I: note info. Option with bracket: next out of tune note. Command Z: undo. Escape: stop.")
    }
}
