import AppKit
import HeadroomCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = Engine()
    private var hud: HUDController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Background agent: no Dock icon, no menu bar of its own.
        NSApp.setActivationPolicy(.accessory)
        engine.start()
        let hud = HUDController(engine: engine)
        hud.show()
        self.hud = hud
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.usage.flush()
    }
}

let app = NSApplication.shared

// Offscreen render mode for inspecting the HUD without a live machine state.
if let i = CommandLine.arguments.firstIndex(of: "--render"), i + 1 < CommandLine.arguments.count {
    app.setActivationPolicy(.prohibited)
    MainActor.assumeIsolated { Renderer.run(outputDir: CommandLine.arguments[i + 1]) }
}

let delegate = AppDelegate()
app.delegate = delegate
app.run()
