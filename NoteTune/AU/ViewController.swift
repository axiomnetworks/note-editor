import AppKit
import SwiftUI
import CoreAudioKit
import AudioToolbox

@objc(NoteTuneAUViewController)
public class AudioUnitViewController: AUViewController, AUAudioUnitFactory {
    var audioUnit: NoteTuneAudioUnit? {
        didSet { DispatchQueue.main.async { self.connect() } }
    }
    private var hosting: NSHostingView<PluginContentView>?

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let au = try NoteTuneAudioUnit(componentDescription: componentDescription, options: [])
        audioUnit = au
        return au
    }

    public override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
    }
    public override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = NSSize(width: 640, height: 420)
        connect()
    }

    private func connect() {
        guard isViewLoaded, hosting == nil, let au = audioUnit else { return }
        let host = NSHostingView(rootView: PluginContentView(model: au.model, controls: au.controls, au: au))
        host.frame = view.bounds
        host.autoresizingMask = [.width, .height]
        view.addSubview(host)
        hosting = host
    }
}
