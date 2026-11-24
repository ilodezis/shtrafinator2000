import AppKit
import PDFKit
import ShtrafinatorCore
import Vision

/// Текст первой страницы PDF: текстовый слой, а если его нет — OCR верхних 65% страницы через Vision.
struct PDFScanTextExtractor: ScanTextExtracting {
    enum Failure: LocalizedError {
        case unreadable

        var errorDescription: String? { "Не удалось открыть PDF" }
    }

    /// Разрешение рендера для OCR, как в прежней версии.
    private let dpi: CGFloat = 200
    /// Шапка и первый абзац («Между …») всегда в верхней части листа.
    private let topFraction: CGFloat = 0.65

    func lines(fromPDFAt url: URL) throws -> [String] {
        guard let document = PDFDocument(url: url) else { throw Failure.unreadable }
        guard document.pageCount > 0, let page = document.page(at: 0) else { return [] }

        if let text = page.string {
            let lines = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if CompanyRecognition.hasUsableTextLayer(lines) { return lines }
        }

        guard let image = renderTop(of: page) else { return [] }
        return try recognizeText(in: image)
    }

    private func renderTop(of page: PDFPage) -> CGImage? {
        var size = page.bounds(for: .cropBox).size
        if page.rotation % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
        let scale = dpi / 72
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)

        // thumbnail учитывает поворот страницы и рисует на белом фоне.
        let thumbnail = page.thumbnail(of: pixelSize, for: .cropBox)
        var rect = CGRect(origin: .zero, size: thumbnail.size)
        guard let full = thumbnail.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let crop = CGRect(x: 0, y: 0, width: full.width, height: Int(CGFloat(full.height) * topFraction))
        return full.cropping(to: crop) ?? full
    }

    private func recognizeText(in image: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ru-RU", "en-US"]
        request.usesLanguageCorrection = true

        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }
}
