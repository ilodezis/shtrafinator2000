import AppKit
import SwiftUI

@main
struct ShtrafinatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Штрафинатор 2000", id: "main") {
            RootView()
                .environment(model)
                .environment(model.generator)
                .environment(model.scans)
                .frame(minWidth: 1020, minHeight: 680)
                .tint(.brand)
        }
        .defaultSize(width: 1200, height: 780)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Открыть реестр…") {
                    model.section = .notices
                    model.generator.chooseRegistry()
                }
                .keyboardShortcut("o")

                Button("Открыть папку со сканами…") {
                    model.section = .scans
                    model.scans.chooseFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("Регламент и правила") { model.showsRules = true }
                    .keyboardShortcut("?", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Нужно при запуске голого бинаря через `swift run`; внутри .app — no-op.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

extension Color {
    /// Фирменный синий CloudPayments.
    static let brand = Color(red: 0, green: 130 / 255, blue: 1)
}
