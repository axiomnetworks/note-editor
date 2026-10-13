import SwiftUI
import AppKit

struct PluginContentView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var controls: PluginControls
    let au: NoteTuneAudioUnit
    @State private var monitor: Any?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Capture") { au.setMode(1) }
                    .accessibilityHint("Starts recording the track's audio while you play it in Logic")
                Button("Stop Capture and Analyze") { au.setMode(2) }
                Button("Bypass") { au.setMode(0) }
                Text(modeName).accessibilityLabel("Current mode \(modeName)")
            }
            Text(controls.status).accessibilityLabel("Status").fixedSize(horizontal: false, vertical: true)
            Text(model.status).accessibilityLabel("Analysis status").fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Previous Note") { model.move(-1) }
                Button("Next Note") { model.move(1) }
                Button("Play Note") { model.audition() }
                Button("Before and After") { model.playBeforeAfter() }
            }
            HStack {
                Button("Pitch Up Semitone") { model.tune(cents: 100) }
                Button("Pitch Down Semitone") { model.tune(cents: -100) }
                Button("Sharpen 5 Cents") { model.tune(cents: 5) }
                Button("Flatten 5 Cents") { model.tune(cents: -5) }
                Button("Snap") { model.snap() }
                Button("Reset Note") { model.reset() }
            }
            NoteListView(model: model)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
        .onAppear {
            if monitor == nil {
                monitor = EditorKeys.installMonitor(model: model, window: { nil })
            }
        }
    }
    var modeName: String { ["Bypass", "Capture", "Edited playback"][max(0, min(2, controls.mode))] }
}
