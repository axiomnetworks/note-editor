import SwiftUI
import AppKit

/// Focusable view that owns the keyboard for the note editor. Works independently of VoiceOver cursor navigation.
final class KeyNSView: NSView {
    var model: EditorModel?
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "Note editor" }
    override func accessibilityHelp() -> String? {
        "Use left and right bracket to change note, arrow keys to tune, space to play. Question mark lists all keys."
    }
    override func accessibilityValue() -> Any? {
        guard let m = model, !m.notes.isEmpty else { return "No notes" }
        return m.describe(m.selected)
    }

    override func keyDown(with event: NSEvent) {
        guard let m = model else { return }
        let flags = event.modifierFlags.intersection([.shift, .option, .control, .command])
        let chars = event.charactersIgnoringModifiers ?? ""
        let shift = flags.contains(.shift), opt = flags.contains(.option)
        if flags.contains(.command) {
            if chars == "z" { shift ? m.redo() : m.undo(); return }
            super.keyDown(with: event); return
        }
        switch event.keyCode {
        case 126: m.tune(cents: shift ? 1200 : 100)          // up
        case 125: m.tune(cents: shift ? -1200 : -100)        // down
        case 124: m.tune(cents: shift ? 1 : (opt ? 20 : 5))  // right
        case 123: m.tune(cents: shift ? -1 : (opt ? -20 : -5)) // left
        case 49:  m.audition()                                // space
        case 36, 76: m.snap()                                 // return
        case 51, 117: m.reset()                               // delete
        case 53:  m.stop()                                    // escape
        case 115: m.select(0)                                 // home
        case 119: m.select(max(0, m.notes.count - 1))         // end
        default:
            switch chars {
            case "[": opt ? m.jumpOutOfTune(-1) : m.move(-1)
            case "]": opt ? m.jumpOutOfTune(1) : m.move(1)
            case "b", "B": m.playBeforeAfter()
            case "i", "I": m.speakInfo()
            case "?", "/": m.help()
            default: super.keyDown(with: event)
            }
        }
    }
}

struct KeyCapture: NSViewRepresentable {
    @ObservedObject var model: EditorModel
    func makeNSView(context: Context) -> KeyNSView { let v = KeyNSView(); v.model = model; return v }
    func updateNSView(_ v: KeyNSView, context: Context) {
        v.model = model
        NSAccessibility.post(element: v, notification: .valueChanged)
    }
}
