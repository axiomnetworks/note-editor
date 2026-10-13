import SwiftUI
import UniformTypeIdentifiers

@main
struct NoteTuneApp: App {
    @StateObject private var model = EditorModel()
    @State private var importing = false
    init() { NSApplication.shared.setActivationPolicy(.regular); NSApplication.shared.activate(ignoringOtherApps: true) }
    var body: some Scene {
        WindowGroup("NoteTune") {
            ContentView(model: model, importing: $importing)
                .frame(minWidth: 520, minHeight: 360)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Audio File...") { importing = true }.keyboardShortcut("o")
            }
            CommandMenu("Notes") {
                Button("Previous Note") { model.move(-1) }
                Button("Next Note") { model.move(1) }
                Button("Play Note") { model.audition() }
                Button("Before and After") { model.playBeforeAfter() }
                Button("Pitch Up Semitone") { model.tune(cents: 100) }
                Button("Pitch Down Semitone") { model.tune(cents: -100) }
                Button("Nudge Sharp 5 Cents") { model.tune(cents: 5) }
                Button("Nudge Flat 5 Cents") { model.tune(cents: -5) }
                Button("Snap to Nearest Pitch") { model.snap() }
                Button("Reset Note") { model.reset() }
                Button("Next Out of Tune Note") { model.jumpOutOfTune(1) }
                Button("Previous Out of Tune Note") { model.jumpOutOfTune(-1) }
                Button("Speak Note Info") { model.speakInfo() }
                Button("List Key Commands") { model.help() }
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: EditorModel
    @Binding var importing: Bool
    var selectionBinding: Binding<Int?> {
        Binding<Int?>(
            get: { model.selected },
            set: { newValue in
                if let s = newValue { model.select(s) }
            })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Open Audio File") { importing = true }
                Stepper(value: $model.bpm, in: 40...240, step: 1) { Text("Tempo \(Int(model.bpm)) BPM") }
                    .accessibilityLabel("Tempo in beats per minute")
            }
            Text(model.status).accessibilityLabel("Status").fixedSize(horizontal: false, vertical: true)
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
        .padding()
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result {
                let ok = url.startAccessingSecurityScopedResource()
                model.open(url: url)
                if ok { DispatchQueue.main.asyncAfter(deadline: .now() + 30) { url.stopAccessingSecurityScopedResource() } }
            }
        }
    }
}

struct NoteRow: View {
    @ObservedObject var model: EditorModel
    let idx: Int
    var body: some View {
        let label: String = model.describe(idx)
        let traits: AccessibilityTraits = (idx == model.selected) ? .isSelected : []
        Text(label)
            .tag(idx)
            .accessibilityLabel(label)
            .accessibilityAddTraits(traits)
            .accessibilityAction(named: "Pitch up semitone") { pick(); model.tune(cents: 100) }
            .accessibilityAction(named: "Pitch down semitone") { pick(); model.tune(cents: -100) }
            .accessibilityAction(named: "Sharpen 5 cents") { pick(); model.tune(cents: 5) }
            .accessibilityAction(named: "Flatten 5 cents") { pick(); model.tune(cents: -5) }
            .accessibilityAction(named: "Snap to nearest pitch") { pick(); model.snap() }
            .accessibilityAction(named: "Reset note") { pick(); model.reset() }
            .accessibilityAction(named: "Play note") { pick(); model.audition() }
    }
    func pick() { model.selected = idx }
}
