import SwiftUI

struct NoteRow: View {
    @ObservedObject var model: EditorModel
    let idx: Int
    var body: some View {
        let text = model.describe(idx)
        Text(text)
            .tag(idx)
            .accessibilityLabel(text)
            .accessibilityAddTraits(idx == model.selected ? .isSelected : [])
            .accessibilityAction(named: "Pitch up semitone") { model.selected = idx; model.tune(cents: 100) }
            .accessibilityAction(named: "Pitch down semitone") { model.selected = idx; model.tune(cents: -100) }
            .accessibilityAction(named: "Sharpen 5 cents") { model.selected = idx; model.tune(cents: 5) }
            .accessibilityAction(named: "Flatten 5 cents") { model.selected = idx; model.tune(cents: -5) }
            .accessibilityAction(named: "Snap to nearest pitch") { model.selected = idx; model.snap() }
            .accessibilityAction(named: "Reset note") { model.selected = idx; model.reset() }
            .accessibilityAction(named: "Play note") { model.selected = idx; model.audition() }
    }
}

struct NoteListView: View {
    @ObservedObject var model: EditorModel
    var selectionBinding: Binding<Int?> {
        Binding<Int?>(get: { model.selected }, set: { if let s = $0 { model.select(s) } })
    }
    var body: some View {
        ZStack {
            KeyCapture(model: model).frame(width: 1, height: 1).opacity(0.01)
            List(selection: selectionBinding) {
                ForEach(0..<model.notes.count, id: \.self) { idx in
                    NoteRow(model: model, idx: idx)
                }
            }
            .accessibilityLabel("Note list")
        }
    }
}
