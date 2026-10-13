import SwiftUI
import AppKit

struct PluginContentView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var controls: PluginControls
    let au: NoteTuneAudioUnit
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
            NoteListView(model: model)
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
    }
    var modeName: String { ["Bypass", "Capture", "Edited playback"][max(0, min(2, controls.mode))] }
}
