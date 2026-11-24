import AppKit
import Foundation
import ShtrafinatorCore

enum AppResources {
    /// Ресурс из Contents/Resources собранного .app, а при `swift run` — из папки Resources репозитория.
    static func url(_ name: String, _ ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Services
            .deletingLastPathComponent()  // Shtrafinator
            .deletingLastPathComponent()  // Sources
            .deletingLastPathComponent()
        let candidate = repoRoot.appendingPathComponent("Resources/\(name).\(ext)")
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    static func loadTemplate() throws -> NoticeTemplate {
        guard let url = url("template", "docx") else { throw ShtrafinatorError.templateUnavailable }
        return try NoticeTemplate(contentsOf: url)
    }

    static let logo: NSImage? = url("logo", "png").flatMap(NSImage.init(contentsOf:))
}

enum Finder {
    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func chooseFile(title: String, extensions: [String]) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = extensions.compactMap { .init(filenameExtension: $0) }
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFolder(title: String, startingAt directory: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = directory
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Путь для показа: домашняя папка сокращается до «~».
    static func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}

extension Double {
    /// «4 120 000 ₽».
    var rubles: String {
        formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "ru_RU"))) + " ₽"
    }
}
