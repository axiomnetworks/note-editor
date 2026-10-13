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
                List(selection: Binding(get: { model.selected }, set: { if let s = $0 { model.select(s) } })) {
                    ForEach(Array(model.notes.enumerated()), id: \.element.id) { idx, _ in
                        Text(model.describe(idx))
                            .tag(idx)
                            .accessibilityLabel(model.describe(idx))
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
