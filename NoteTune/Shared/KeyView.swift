import SwiftUI
import AppKit

enum EditorKeys {
    /// Returns true if the event was handled.
    static func handle(_ event: NSEvent, model m: EditorModel) -> Bool {
        let flags = event.modifierFlags.intersection([.shift, .option, .control, .command])
        let chars = event.charactersIgnoringModifiers ?? ""
        let shift = flags.contains(.shift), opt = flags.contains(.option)
        if flags.contains(.command) {
            if chars == "z" { if shift { m.redo() } else { m.undo() }; return true }
            return false
        }
        if flags.contains(.control) { return false }
        switch event.keyCode {
        case 126: m.tune(cents: shift ? 1200 : 100)
        case 125: m.tune(cents: shift ? -1200 : -100)
        case 124: m.tune(cents: shift ? 1 : (opt ? 20 : 5))
        case 123: m.tune(cents: shift ? -1 : (opt ? -20 : -5))
        case 49:  m.audition()
        case 36, 76: m.snap()
        case 51, 117: m.reset()
        case 53:  m.stop()
        case 115: m.select(0)
        case 119: m.select(max(0, m.notes.count - 1))
        default:
            switch chars {
            case "[": if opt { m.jumpOutOfTune(-1) } else { m.move(-1) }
            case "]": if opt { m.jumpOutOfTune(1) } else { m.move(1) }
            case "b", "B": m.playBeforeAfter()
            case "i", "I": m.speakInfo()
            case "?", "/": m.help()
            default: return false
            }
        }
        return true
    }

    /// Catches keys at window level so they work whatever view has focus (list, button, etc).
    /// Skips text editing. Pass `window` to limit to one window (plugin).
    static func installMonitor(model: EditorModel, window: @escaping () -> NSWindow?) -> Any? {
        return NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if let w = window(), event.window !== w { return event }
            if let r = event.window?.firstResponder, r is NSText { return event }   // typing in a text field
            return handle(event, model: model) ? nil : event
        }
    }
}

/// Focusable view that owns the keyboard for the note editor. Works independently of VoiceOver cursor navigation.
final class KeyNSView: NSView {
    var model: EditorModel? { didSet { model?.announceTarget = self } }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

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
        if !EditorKeys.handle(event, model: m) { super.keyDown(with: event) }
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
