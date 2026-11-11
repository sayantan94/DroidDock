import SwiftUI
import AppKit

@main
struct MacDroidApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel(demo: CommandLine.arguments.contains("--demo") || CommandLine.arguments.contains("--screenshots"))

    var body: some Scene {
        Window("DroidDock", id: "main") {
            ContentView(model: model, camera: model.camera)
                .preferredColorScheme(CommandLine.arguments.contains("--screenshots") ? .dark : nil)
                .frame(minWidth: 980, minHeight: 660)
                .onAppear {
                    delegate.model = model
                    if CommandLine.arguments.contains("--screenshots") { Task { await DocumentationCapture.run(model: model) } }
                    else { model.start() }
                }
                .tint(Palette.accent)
        }
        .defaultSize(width: 1180, height: 790)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .importExport) {
                Button("Copy selected to Mac") { model.importSelected() }
                    .keyboardShortcut("i", modifiers: .command).disabled(!model.canImport)
                Button("Choose destination…") { model.chooseDestination() }.disabled(model.isImporting)
            }
            CommandGroup(replacing: .help) {
                Button("Connect an Android phone") { model.showGuide = true }
                Divider()
                Button("Show sample library") { model.showDemo() }.disabled(model.isImporting || model.mtp.busy)
                Button("Use connected phone") { model.useConnectedPhone() }.disabled(!model.camera.isDemo || model.isImporting)
            }
            CommandGroup(after: .pasteboard) {
                Button("Select all photos in view") { model.selectAll() }.keyboardShortcut("a", modifiers: .command)
                Button("Clear photo selection") { model.selection = [] }.keyboardShortcut("a", modifiers: [.command, .shift]).disabled(model.isImporting)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model?.mtp.deleting == true {
            let alert = NSAlert()
            alert.messageText = "Deleting files from your phone"
            alert.informativeText = "Use Stop after this file and wait for deletion to finish before closing DroidDock."
            alert.addButton(withTitle: "OK"); alert.runModal()
            return .terminateCancel
        }
        guard model?.isImporting == true || model?.mtp.transferring == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "A photo transfer is still running"
        alert.informativeText = "Keep DroidDock open until it finishes, or use Stop after this file. Quitting now can leave an incomplete temporary download."
        alert.addButton(withTitle: "Keep copying"); alert.addButton(withTitle: "Quit now")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateCancel : .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) { model?.camera.shutdown() }
}
